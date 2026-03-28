import Foundation
import SwiftUI
import PhotosUI
import Combine
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var pages: [PageInput] = []
    @Published var notes: [AnkiNote] = []            // validated or ready-to-validate notes
    @Published var pendingNotes: [AnkiNote] = []     // staged for validation
    @Published var warnings: [String] = []
    @Published var isAnalyzing = false
    @Published var statusText: String?
    @Published var errorMessage: String?
    @Published var backendAvailable: Bool = false
    @Published var ankiAvailable: Bool = false
    @Published var ocrDebugByPage: [UUID: String] = [:]
    @Published var ocrProcessingMode: OCRProcessingMode

    private let backend: BackendClient
    private let anki: AnkiConnectService
    private let visionOCR: VisionOCRService
    private let visionOCRAvailable: Bool
    private let settings: AppSettingsStoring

    convenience init() {
        self.init(
            backend: BackendClient(),
            anki: AnkiConnectService(),
            visionOCR: VisionOCRService(),
            visionOCRAvailable: AppFeatureFlags.visionOCREnabled,
            settings: UserDefaults.standard
        )
    }

    init(
        backend: BackendClient,
        anki: AnkiConnectService,
        visionOCR: VisionOCRService = VisionOCRService(),
        visionOCRAvailable: Bool = AppFeatureFlags.visionOCREnabled,
        settings: AppSettingsStoring = UserDefaults.standard
    ) {
        self.backend = backend
        self.anki = anki
        self.visionOCR = visionOCR
        self.visionOCRAvailable = visionOCRAvailable
        self.settings = settings
        let resolvedMode = Self.resolveOCRProcessingMode(
            storedRawValue: settings.string(forKey: AppSettingsKeys.ocrProcessingMode),
            visionOCRAvailable: visionOCRAvailable
        )
        self.ocrProcessingMode = resolvedMode

        if let storedRawValue = settings.string(forKey: AppSettingsKeys.ocrProcessingMode),
           storedRawValue != resolvedMode.rawValue {
            settings.set(resolvedMode.rawValue, forKey: AppSettingsKeys.ocrProcessingMode)
        }
    }

    func refreshAnkiAvailability() async {
        ankiAvailable = await anki.isAvailable()
    }

    func refreshBackendAvailability() async {
        backendAvailable = await backend.isAvailable()
    }

    func refreshServiceAvailability() async {
        async let backendStatus = backend.isAvailable()
        async let ankiStatus = anki.isAvailable()
        backendAvailable = await backendStatus
        ankiAvailable = await ankiStatus
    }

    var backendTargetLabel: String {
        let host = (backend.baseURL.host ?? "").lowercased()
        if host == "127.0.0.1" || host == "localhost" {
            return "Local"
        }
        return "Fly"
    }

    var availableOCRProcessingModes: [OCRProcessingMode] {
        OCRProcessingMode.availableModes(isVisionOCRAvailable: visionOCRAvailable)
    }

    var ocrProcessingDescription: String {
        if ocrProcessingMode == .visionAssist && visionOCRAvailable == false {
            return "On-device Apple Vision OCR is disabled for this build, so the app will send images straight to the backend LLM."
        }
        return ocrProcessingMode.descriptionText
    }

    func setOCRProcessingMode(_ mode: OCRProcessingMode) {
        let resolvedMode = Self.resolveOCRProcessingMode(mode, visionOCRAvailable: visionOCRAvailable)
        ocrProcessingMode = resolvedMode
        settings.set(resolvedMode.rawValue, forKey: AppSettingsKeys.ocrProcessingMode)
    }

    func addPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { continue }
                let name = item.itemIdentifier ?? "page_\(pages.count + 1)"
                appendPage(image: uiImage, filename: name)
            }
        }
    }

    func addCapturedPhoto(_ image: UIImage) {
        let filename = "camera_\(Int(Date().timeIntervalSince1970))"
        appendPage(image: image, filename: filename)
    }

    func removePage(_ page: PageInput) {
        print("Removing page: \(page.filename) [\(page.id)]")
        pages.removeAll { $0.id == page.id }
        ocrDebugByPage.removeValue(forKey: page.id)
        print("Remaining selected pages: \(pages.count)")
        print("Remaining filenames: \(pages.map(\.filename).joined(separator: ", "))")
    }

    private func appendPage(image: UIImage, filename: String) {
        let page = PageInput(image: image, filename: filename)
        pages.append(page)
        print("Added page: \(filename) [\(page.id)]")
        print("Current selected pages (\(pages.count)): \(pages.map(\.filename).joined(separator: ", "))")
    }

    func analyzePages() {
        guard pages.isNotEmpty else {
            errorMessage = "Add at least one photo first."
            return
        }

        Task {
            isAnalyzing = true
            defer { isAnalyzing = false }
            errorMessage = nil
            statusText = "Uploading \(pages.count) page(s)..."
            warnings = []
            ocrDebugByPage = [:]
            let selectedOCRProcessingMode = ocrProcessingMode

            var collectedNotes: [AnkiNote] = []
            print("Starting analysis for \(pages.count) selected page(s): \(pages.map(\.filename).joined(separator: ", "))")

            for (index, page) in pages.enumerated() {
                statusText = "Analyzing page \(index + 1) of \(pages.count)..."
                print("Analyzing page \(index + 1)/\(pages.count): \(page.filename)")
                let candidates = ImagePreprocessor.prepareOCRCandidates(page.image)
                guard let naturalCandidate = preferredBackendCandidate(from: candidates) else {
                    warnings.append("Could not preprocess \(page.filename).")
                    print("Preprocess failed for \(page.filename)")
                    continue
                }
                setPreprocessedPreview(naturalCandidate.image, for: page.id)
                print("Preprocess ready for \(page.filename) -> variant=\(naturalCandidate.variant.rawValue), size=\(Int(naturalCandidate.image.size.width))x\(Int(naturalCandidate.image.size.height))")

                var ocrPayloadForBackend: VisionOCRPayload?
                if selectedOCRProcessingMode.usesOnDeviceVision && visionOCRAvailable {
                    statusText = "Running on-device OCR for \(page.filename)..."
                    ocrPayloadForBackend = await runVisionOCRIfEnabled(
                        candidates: candidates,
                        pageID: page.id,
                        pageFilename: page.filename
                    )
                } else {
                    print(
                        "Vision OCR skipped for \(page.filename) (mode=\(selectedOCRProcessingMode.rawValue), available=\(visionOCRAvailable))"
                    )
                    setOCRDebugText(
                        selectedOCRProcessingMode.debugStatusText(isVisionOCRAvailable: visionOCRAvailable),
                        for: page.id
                    )
                }

                do {
                    statusText = "Generating cards for \(page.filename)..."
                    print("Sending \(page.filename) to backend: \(backend.baseURL.absoluteString)")
                    let response = try await backend.analyzePage(
                        imageData: naturalCandidate.jpegData,
                        pageId: page.filename,
                        ocrPayload: ocrPayloadForBackend
                    )
                    warnings.append(
                        contentsOf: normalizeBackendWarnings(
                            response.warnings,
                            pageFilename: page.filename,
                            ocrProcessingMode: selectedOCRProcessingMode,
                            visionPayload: ocrPayloadForBackend
                        )
                    )
                    let pageNotes = response.ankiNotes.map { raw in
                        let resolvedID = UUID(uuidString: raw.id ?? "") ?? UUID()
                        return AnkiNote(
                            id: resolvedID,
                            expressionOrWord: raw.front,
                            reading: raw.hiragana,
                            meaning: raw.back ?? "",
                            example: raw.notes,
                            confidence: raw.confMatch ?? 0.5,
                            needsReview: raw.needsReview,
                            sourcePage: page.filename,
                            handTranslation: raw.handTranslation,
                            aiTranslation: raw.aiTranslation,
                            bookMatch: raw.bookMatch,
                            confMatch: raw.confMatch,
                            confOcr: raw.confOcr,
                            visionOCRQuality: ocrPayloadForBackend?.qualityScore,
                            visionOCRVariant: ocrPayloadForBackend?.selectedVariant
                        )
                    }
                    collectedNotes.append(contentsOf: pageNotes)
                    print("Backend response for \(page.filename): \(pageNotes.count) card(s), \(response.warnings.count) warning(s)")
                } catch {
                    print("Analysis failed for \(page.filename): \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    break
                }
            }

            pendingNotes = dedupe(collectedNotes)
            warnings = dedupeWarnings(warnings)
            notes = []
            statusText = "Generated \(pendingNotes.count) cards (needs validation)"
            print("Analysis completed. Pending cards: \(pendingNotes.count), warnings: \(warnings.count)")
        }
    }

    func validateAllPending() {
        notes.append(contentsOf: pendingNotes)
        pendingNotes.removeAll()
    }

    func validate(note: AnkiNote) {
        if let idx = pendingNotes.firstIndex(of: note) {
            notes.append(pendingNotes.remove(at: idx))
        }
    }

    func reject(note: AnkiNote) {
        pendingNotes.removeAll { $0 == note }
    }

    func sendToAnki(deckName: String) async {
        guard notes.isNotEmpty else { return }
        do {
            try await anki.addNotes(deckName: deckName, notes: notes)
            statusText = "Sent \(notes.count) cards to Anki"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSVFileURL(suggestedName: String) throws -> URL {
        try CSVExporter.writeTempCSV(from: notes, suggestedName: suggestedName)
    }

    func exportAnkiImportFileURL(suggestedName: String, deckName: String) throws -> URL {
        try AnkiImportFileExporter.writeTempImportFile(from: notes, suggestedName: suggestedName, deckName: deckName)
    }

    private func runVisionOCRIfEnabled(
        candidates: [ImagePreprocessor.OCRCandidate],
        pageID: UUID,
        pageFilename: String
    ) async -> VisionOCRPayload? {
        let timeoutSeconds: Double = 15
        let service = visionOCR
        let startedAt = Date()
        print("Vision OCR dispatch start for \(pageFilename): candidates=\(candidates.count), app_timeout=\(Int(timeoutSeconds))s")

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false
            var timeoutWorkItem: DispatchWorkItem?

            func finish(_ payload: VisionOCRPayload?, reason: String) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard hasResumed == false else {
                    print("Vision OCR finish ignored for \(pageFilename): reason=\(reason) (already resumed)")
                    return false
                }
                hasResumed = true
                timeoutWorkItem?.cancel()
                let elapsedMs = Date().timeIntervalSince(startedAt) * 1000
                print(
                    "Vision OCR continuation resumed for \(pageFilename): reason=\(reason), payload=\(payload != nil ? "yes" : "no"), elapsed_ms=\(String(format: "%.1f", elapsedMs))"
                )
                continuation.resume(returning: payload)
                return true
            }

            DispatchQueue.global(qos: .userInitiated).async {
                print("Vision OCR worker started for \(pageFilename)")
                do {
                    let payload = try service.recognizeBestBlocking(from: candidates, sourceImageId: pageFilename)
                    DispatchQueue.main.async {
                        guard finish(payload, reason: "success") else { return }
                        print("Vision OCR for \(pageFilename): variant=\(payload.selectedVariant), lines=\(payload.lines.count), aggregate=\(String(format: "%.2f", payload.aggregateConfidence)), quality=\(String(format: "%.2f", payload.qualityScore))")
                        self.setOCRDebugText(self.formatOCRPreview(payload), for: pageID)
                        if payload.lines.isEmpty {
                            self.warnings.append("On-device Apple Vision OCR found no text on \(pageFilename). Backend LLM image OCR fallback will be used.")
                        } else if payload.qualityScore < 0.45 {
                            let quality = Int((payload.qualityScore * 100).rounded())
                            self.warnings.append("On-device Apple Vision OCR quality is low on \(pageFilename) (\(quality)%). Backend LLM may rely on image OCR fallback.")
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard finish(nil, reason: "error") else { return }
                        print("Vision OCR failed for \(pageFilename): \(error.localizedDescription)")
                        self.warnings.append("On-device Apple Vision OCR failed on \(pageFilename): \(error.localizedDescription). Backend LLM image OCR fallback will be used.")
                        self.setOCRDebugText("On-device Apple Vision OCR failed: \(error.localizedDescription)\nFallback: backend LLM image OCR.", for: pageID)
                    }
                }
            }

            let timeout = DispatchWorkItem {
                guard finish(nil, reason: "app_timeout") else { return }
                print("Vision OCR app-level timeout for \(pageFilename) after \(Int(timeoutSeconds))s; proceeding with backend image fallback.")
                self.warnings.append("On-device Apple Vision OCR timed out on \(pageFilename) after \(Int(timeoutSeconds))s; backend LLM image OCR fallback is being used.")
                self.setOCRDebugText("On-device Apple Vision OCR timed out after \(Int(timeoutSeconds))s.\nFallback: backend LLM image OCR.", for: pageID)
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        }
    }

    private func preferredBackendCandidate(from candidates: [ImagePreprocessor.OCRCandidate]) -> ImagePreprocessor.OCRCandidate? {
        if let natural = candidates.first(where: { $0.variant == .natural }) {
            return natural
        }
        return candidates.first
    }

    private func setPreprocessedPreview(_ image: UIImage?, for pageID: UUID) {
        guard let idx = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[idx].preprocessedImage = image
    }

    private func setOCRDebugText(_ text: String, for pageID: UUID) {
        ocrDebugByPage[pageID] = text
    }

    private func formatOCRPreview(_ payload: VisionOCRPayload) -> String {
        let header =
            "Variant: \(payload.selectedVariant)\n" +
            "Aggregate: \(String(format: "%.2f", payload.aggregateConfidence))  " +
            "Quality: \(String(format: "%.2f", payload.qualityScore))\n"

        if payload.lines.isEmpty {
            return header + "\n(No lines recognized)"
        }

        let maxLines = 24
        let lines = payload.lines.prefix(maxLines).enumerated().map { index, line in
            let text = line.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return String(format: "%02d. [%.2f] %@", index + 1, line.confidence, text)
        }

        var out = header + "\n" + lines.joined(separator: "\n")
        if payload.lines.count > maxLines {
            out += "\n... (\(payload.lines.count - maxLines) more line(s))"
        }
        return out
    }

    private func dedupe(_ notes: [AnkiNote]) -> [AnkiNote] {
        var ordered: [AnkiNote] = []
        var seenByMeaningKey: [String: Int] = [:]

        for note in notes {
            let expressionKey = normalizeKey(note.expressionOrWord)
            let readingKey = normalizeKey(note.reading ?? "")
            let meaningKey = normalizeKey(note.meaning)
            let key = "\(expressionKey)|\(readingKey)|\(meaningKey)"

            if let idx = seenByMeaningKey[key] {
                var merged = ordered[idx]
                merged.sourcePage = mergeSourcePages(merged.sourcePage, note.sourcePage)
                merged.needsReview = merged.needsReview || note.needsReview
                merged.confidence = max(merged.confidence, note.confidence)
                merged.confMatch = maxOptional(merged.confMatch, note.confMatch)
                merged.confOcr = maxOptional(merged.confOcr, note.confOcr)
                merged.visionOCRQuality = maxOptional(merged.visionOCRQuality, note.visionOCRQuality)
                merged.visionOCRVariant = merged.visionOCRVariant ?? note.visionOCRVariant
                ordered[idx] = merged
            } else {
                seenByMeaningKey[key] = ordered.count
                ordered.append(note)
            }
        }
        return ordered
    }

    private func mergeSourcePages(_ lhs: String?, _ rhs: String?) -> String? {
        let parts = [lhs, rhs]
            .compactMap { $0 }
            .flatMap { value in
                value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            }
            .filter { !$0.isEmpty }

        guard parts.isNotEmpty else { return nil }

        var orderedUnique: [String] = []
        var seen = Set<String>()
        for item in parts where seen.insert(item).inserted {
            orderedUnique.append(item)
        }
        return orderedUnique.joined(separator: ", ")
    }

    private func maxOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
        if let lhs, let rhs { return max(lhs, rhs) }
        return lhs ?? rhs
    }

    private func normalizeKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func dedupeWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }

    private func normalizeBackendWarnings(
        _ incomingWarnings: [String],
        pageFilename: String,
        ocrProcessingMode: OCRProcessingMode,
        visionPayload: VisionOCRPayload?
    ) -> [String] {
        incomingWarnings.map { warning in
            let normalized = warning.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = normalized.lowercased()

            if lowered.contains("low confidence in ocr") {
                if let visionPayload {
                    let quality = Int((visionPayload.qualityScore * 100).rounded())
                    return "Backend LLM reported low OCR confidence for \(pageFilename). On-device Apple Vision OCR quality was \(quality)% (\(visionPayload.selectedVariant)); LLM image OCR fallback may be used for unclear lines."
                }
                if ocrProcessingMode == .llmOnly {
                    return "Backend LLM reported low OCR confidence for \(pageFilename). On-device Apple Vision OCR was skipped because LLM Only mode is selected."
                }
                if visionOCRAvailable == false {
                    return "Backend LLM reported low OCR confidence for \(pageFilename). On-device Apple Vision OCR is unavailable in this build, so the page was sent directly to the backend LLM."
                }
                return "Backend LLM reported low OCR confidence for \(pageFilename). On-device Apple Vision OCR was unavailable; LLM image OCR fallback was used."
            }

            return normalized
        }
    }

    private static func resolveOCRProcessingMode(
        storedRawValue: String?,
        visionOCRAvailable: Bool
    ) -> OCRProcessingMode {
        let storedMode = storedRawValue.flatMap(OCRProcessingMode.init(rawValue:))
        return resolveOCRProcessingMode(
            storedMode ?? AppFeatureFlags.defaultOCRProcessingMode,
            visionOCRAvailable: visionOCRAvailable
        )
    }

    private static func resolveOCRProcessingMode(
        _ mode: OCRProcessingMode,
        visionOCRAvailable: Bool
    ) -> OCRProcessingMode {
        if mode.usesOnDeviceVision && visionOCRAvailable == false {
            return .llmOnly
        }
        return mode
    }
}

struct PageInput: Identifiable, Hashable {
    let id: UUID
    let image: UIImage
    let filename: String
    var preprocessedImage: UIImage?

    init(id: UUID = UUID(), image: UIImage, filename: String, preprocessedImage: UIImage? = nil) {
        self.id = id
        self.image = image
        self.filename = filename
        self.preprocessedImage = preprocessedImage
    }
}

extension Array {
    var isNotEmpty: Bool { isEmpty == false }
}

#if DEBUG
// MARK: - Sample pages preload (debug-only)
extension AppViewModel {
    func performSampleReload() {
        preloadSamplePages()
    }

    func preloadSamplePages() {
        var all: [URL] = []
        let fm = FileManager.default

        // Allowed extensions for debug sample pages.
        let exts = ["jpg", "jpeg", "png", "heic", "heif"]
        let blockedNamePrefixes = ["appicon", "accentcolor", "contents", "deckify icon"]
        let blockedPathTokens = [".appiconset", ".colorset"]

        func isSampleImageURL(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            guard exts.contains(ext) else { return false }

            let filename = url.deletingPathExtension().lastPathComponent.lowercased()
            if blockedNamePrefixes.contains(where: { filename.hasPrefix($0) }) {
                return false
            }

            let path = url.path.lowercased()
            if blockedPathTokens.contains(where: { path.contains($0) }) {
                return false
            }

            return true
        }

        func appendImages(from directory: URL) {
            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            all.append(contentsOf: contents.filter(isSampleImageURL))
        }

        if let root = Bundle.main.resourceURL {
            // 1) Search explicit SamplePages directories first.
            let explicitDirs = [
                root.appendingPathComponent("SamplePages", isDirectory: true),
                root.appendingPathComponent("Resources/SamplePages", isDirectory: true)
            ]
            for dir in explicitDirs where fm.fileExists(atPath: dir.path) {
                appendImages(from: dir)
            }

            // 2) Fallback to bundle root (synchronized resources may be flattened here).
            if all.isEmpty {
                appendImages(from: root)
            }

            // 3) Last fallback: recursively search directories named SamplePages.
            if all.isEmpty,
               let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
               ) {
                for case let url as URL in enumerator where url.lastPathComponent == "SamplePages" {
                    appendImages(from: url)
                }
            }
        }

        all = all.filter(isSampleImageURL)
        all = Array(Set(all.map { $0.path })).map(URL.init(fileURLWithPath:))

        print("SamplePages search -> found \(all.count) file(s)")
        if let root = Bundle.main.resourceURL {
            print("Bundle resource root: \(root.path)")
        }
        all.forEach { print(" - \($0.lastPathComponent)") }

        let loaded: [PageInput] = all.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else { return nil }
            return PageInput(image: img, filename: url.lastPathComponent)
        }
        .sorted { lhs, rhs in
            lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
        }
        if loaded.isNotEmpty {
            pages = loaded
            print("Loaded \(loaded.count) sample page(s) into memory.")
        } else {
            print("No sample pages loaded. Verify SamplePages is a folder reference in the target.")
        }
    }
}
#endif
