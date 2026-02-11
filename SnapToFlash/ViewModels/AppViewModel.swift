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

    private let backend: BackendClient
    private let anki: AnkiConnectService

    convenience init() {
        self.init(backend: BackendClient(), anki: AnkiConnectService())
    }

    init(backend: BackendClient, anki: AnkiConnectService) {
        self.backend = backend
        self.anki = anki
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
        pages.removeAll { $0.id == page.id }
    }

    private func appendPage(image: UIImage, filename: String) {
        let page = PageInput(image: image, filename: filename)
        pages.append(page)
    }

    func analyzePages() {
        guard pages.isNotEmpty else {
            errorMessage = "Add at least one photo first."
            return
        }

        Task {
            isAnalyzing = true
            errorMessage = nil
            statusText = "Uploading \(pages.count) page(s)..."
            warnings = []

            var collectedNotes: [AnkiNote] = []

            for (index, page) in pages.enumerated() {
                statusText = "Analyzing page \(index + 1) of \(pages.count)..."
                guard let data = ImagePreprocessor.preprocess(page.image) else {
                    warnings.append("Could not preprocess \(page.filename)."); continue
                }
                do {
                    let response = try await backend.analyzePage(imageData: data, pageId: page.filename)
                    warnings.append(contentsOf: response.warnings)
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
                            confOcr: raw.confOcr
                        )
                    }
                    collectedNotes.append(contentsOf: pageNotes)
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }

            pendingNotes = dedupe(collectedNotes)
            warnings = dedupeWarnings(warnings)
            notes = []
            statusText = "Generated \(pendingNotes.count) cards (needs validation)"
            isAnalyzing = false
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

    func exportCSV() -> String {
        CSVExporter.makeCSV(from: notes)
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
}

struct PageInput: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let filename: String
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
