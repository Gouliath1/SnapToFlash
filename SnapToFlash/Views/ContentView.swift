import SwiftUI
import PhotosUI
import UIKit
import Combine

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var deckName: String = "Deckify"
    @State private var showCSVShare = false
    @State private var csvString: String = ""
    @State private var showCameraPicker = false
    @State private var showLoadOptions = false
    @State private var showValidationOptions = false
    @State private var showPhotoLibraryPicker = false
    @State private var showExportOptions = false
    @State private var shouldPresentCSVAfterExportSheet = false

    private let actionBarHeight: CGFloat = 120
    private let brandBlue = Color(red: 0.16, green: 0.59, blue: 0.95)
    private let brandTeal = Color(red: 0.13, green: 0.73, blue: 0.69)
    private let brandSun = Color(red: 1.00, green: 0.64, blue: 0.18)

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroHeader
                        captureSection
                        if shouldShowProgressSection {
                            progressSection
                        }
                        resultsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .padding(.bottom, actionBarHeight)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        backendStatus
                        ankiStatus
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .task {
            await model.refreshServiceAvailability()
        }
        .onChange(of: pickerItems) { _, newItems in
            model.addPhotos(newItems)
        }
        .photosPicker(
            isPresented: $showPhotoLibraryPicker,
            selection: $pickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .confirmationDialog("Load image(s)", isPresented: $showLoadOptions, titleVisibility: .visible) {
            Button("Import from Photos") {
                DispatchQueue.main.async {
                    showPhotoLibraryPicker = true
                }
            }
#if DEBUG
            Button("Load bundled samples") {
                model.performSampleReload()
            }
#endif
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take picture") {
                    DispatchQueue.main.async {
                        showCameraPicker = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose image source")
        }
        .confirmationDialog("Validate cards", isPresented: $showValidationOptions, titleVisibility: .visible) {
            Button("Accept all pending (\(model.pendingNotes.count))") {
                model.validateAllPending()
            }
            .disabled(model.pendingNotes.isEmpty)

            Button("Clear pending (\(model.pendingNotes.count))", role: .destructive) {
                model.pendingNotes.removeAll()
            }
            .disabled(model.pendingNotes.isEmpty)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Approve or discard pending cards")
        }
        .sheet(
            isPresented: $showExportOptions,
            onDismiss: {
                if shouldPresentCSVAfterExportSheet {
                    shouldPresentCSVAfterExportSheet = false
                    showCSVShare = true
                }
            }
        ) {
            ExportOptionsSheet(
                ankiEnabled: canAnkiExport,
                csvEnabled: canExport
            ) {
                showExportOptions = false
                Task { await model.sendToAnki(deckName: deckName) }
            } onCSV: {
                csvString = model.exportCSV()
                shouldPresentCSVAfterExportSheet = true
                showExportOptions = false
            }
        }
        .sheet(isPresented: $showCSVShare) {
            ShareSheet(activityItems: [csvString])
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraCaptureView { image in
                model.addCapturedPhoto(image)
                showCameraPicker = false
            } onCancel: {
                showCameraPicker = false
            }
        }
    }

    private var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                    Color(red: 0.95, green: 0.98, blue: 1.00),
                    Color(red: 0.95, green: 0.99, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(brandBlue.opacity(0.15))
                .frame(width: 260, height: 260)
                .offset(x: -150, y: -320)

            Circle()
                .fill(brandSun.opacity(0.13))
                .frame(width: 230, height: 230)
                .offset(x: 170, y: -250)
        }
    }

    private var heroHeader: some View {
        HStack(spacing: 14) {
            DeckifyBrandImage()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: brandBlue.opacity(0.30), radius: 14, y: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text("Deckify")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text("Capture Notes. Generate Flash Cards. Learn Faster")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private var shouldShowProgressSection: Bool {
        model.statusText != nil || model.errorMessage != nil || model.warnings.isNotEmpty
    }

    private var captureSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("1) Capture or import annotated pages")
                    .font(.headline)

                if model.pages.isNotEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(model.pages) { page in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: page.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 140, height: 180)
                                        .clipped()
                                        .cornerRadius(10)
                                        .shadow(radius: 2)
                                    Button(role: .destructive) {
                                        model.removePage(page)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .red)
                                            .shadow(radius: 1)
                                    }
                                    .padding(6)
                                }
                            }
                        }
                    }
                } else {
                    Text("No photos added yet.")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var progressSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("System status")
                    .font(.headline)

                if let status = model.statusText {
                    HStack {
                        if model.isAnalyzing { ProgressView() }
                        Text(status)
                    }
                    .font(.subheadline)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }

                if model.warnings.isNotEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warnings")
                            .font(.subheadline.bold())
                        ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                        }
                    }
                }
            }
        }
    }

    private var resultsSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("2) Review & send to Anki")
                    .font(.headline)

                if model.notes.isEmpty {
                    if model.pendingNotes.isEmpty {
                        Text("Cards will appear here after analysis.")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Review pending cards below. Only approved cards are sent to Anki.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(Array(model.notes.enumerated()), id: \.element.id) { index, note in
                        CardRow(note: note, cardIndex: index + 1, showValidation: false, onApprove: {}, onReject: {})
                    }

                    if model.ankiAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anki deck name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Deck name", text: $deckName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if model.pendingNotes.isNotEmpty {
                    Divider().padding(.vertical, 8)
                    Text("Pending validation")
                        .font(.subheadline.bold())
                    ForEach(Array(model.pendingNotes.enumerated()), id: \.element.id) { index, note in
                        CardRow(note: note, cardIndex: index + 1, showValidation: true) {
                            model.validate(note: note)
                        } onReject: {
                            model.reject(note: note)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                showLoadOptions = true
            } label: {
                ActionBarButtonLabel(
                    title: "Load",
                    subtitle: "Photo/Cam",
                    systemImage: "camera.on.rectangle.fill",
                    isEnabled: canLoadImages
                )
            }
            .disabled(canLoadImages == false)

            Button {
                model.analyzePages()
            } label: {
                ActionBarButtonLabel(
                    title: "Gen. Cards",
                    subtitle: "AI",
                    systemImage: "sparkles",
                    isEnabled: canGenerate
                )
            }
            .disabled(canGenerate == false)

            Button {
                showValidationOptions = true
            } label: {
                ActionBarButtonLabel(
                    title: "Validate",
                    subtitle: "Approve",
                    systemImage: "checkmark.circle.fill",
                    isEnabled: canValidate
                )
            }
            .disabled(canValidate == false)

            Button {
                showExportOptions = true
            } label: {
                ActionBarButtonLabel(
                    title: "Export",
                    subtitle: "Anki/CSV",
                    systemImage: "square.and.arrow.up.fill",
                    isEnabled: canExport
                )
            }
            .disabled(canExport == false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: -4)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [brandBlue.opacity(0.22), brandTeal.opacity(0.20), brandSun.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: brandBlue.opacity(0.08), radius: 14, y: 8)
    }

    private var canLoadImages: Bool {
        model.isAnalyzing == false
    }

    private var canGenerate: Bool {
        model.isAnalyzing == false && model.pages.isNotEmpty
    }

    private var canValidate: Bool {
        model.isAnalyzing == false && model.pendingNotes.isNotEmpty
    }

    private var canExport: Bool {
        model.isAnalyzing == false && model.notes.isNotEmpty
    }

    private var canAnkiExport: Bool {
        canExport && model.ankiAvailable
    }

    private var ankiStatus: some View {
        StatusPill(
            title: "Anki",
            systemImage: "paperplane.fill",
            isOnline: model.ankiAvailable,
            accent: Color.orange
        )
        .onTapGesture { Task { await model.refreshAnkiAvailability() } }
    }

    private var backendStatus: some View {
        StatusPill(
            title: model.backendTargetLabel,
            systemImage: model.backendTargetLabel == "Local" ? "desktopcomputer" : "cloud.fill",
            isOnline: model.backendAvailable,
            accent: Color.blue
        )
        .onTapGesture { Task { await model.refreshBackendAvailability() } }
    }
}

private struct DeckifyBrandImage: View {
#if DEBUG
    @State private var liveImage: UIImage? = DeckifyBrandImageLoader.loadFromDisk()
    @State private var lastModified: Date? = DeckifyBrandImageLoader.modificationDate()
    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
#endif

    var body: some View {
        Group {
#if DEBUG
            if let liveImage {
                Image(uiImage: liveImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("DeckifyBrand")
                    .resizable()
                    .scaledToFill()
            }
#else
            Image("DeckifyBrand")
                .resizable()
                .scaledToFill()
#endif
        }
#if DEBUG
        .onAppear {
            refreshIfNeeded(force: true)
        }
        .onReceive(refreshTimer) { _ in
            refreshIfNeeded()
        }
#endif
    }

#if DEBUG
    private func refreshIfNeeded(force: Bool = false) {
        let modified = DeckifyBrandImageLoader.modificationDate()
        guard force || modified != lastModified else { return }
        lastModified = modified
        liveImage = DeckifyBrandImageLoader.loadFromDisk()
    }
#endif
}

private enum DeckifyBrandImageLoader {
    private static let plistKey = "DeckifyBrandIconPath"

    static func loadFromDisk() -> UIImage? {
        guard let path = iconPath() else { return nil }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        return trimTransparentBounds(image)
    }

    static func modificationDate() -> Date? {
        guard let path = iconPath() else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    private static func iconPath() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String else {
            return nil
        }
        let resolved = (raw as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: resolved) else {
            return nil
        }
        return resolved
    }

    /// Crops transparent padding so wide PNG logos still fill the hero icon frame.
    private static func trimTransparentBounds(_ image: UIImage) -> UIImage {
        guard let sourceCG = image.cgImage else { return image }

        let width = sourceCG.width
        let height = sourceCG.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        else {
            return image
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(sourceCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        let threshold: UInt8 = 6

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let alpha = pixels[rowOffset + (x * bytesPerPixel) + 3]
                if alpha > threshold {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard
            maxX >= minX,
            maxY >= minY,
            let raster = context.makeImage()
        else {
            return image
        }

        let rect = CGRect(
            x: minX,
            y: minY,
            width: (maxX - minX + 1),
            height: (maxY - minY + 1)
        )

        guard let cropped = raster.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }
}

private struct CardRow: View {
    let note: AnkiNote
    let cardIndex: Int
    var showValidation: Bool
    var onApprove: () -> Void
    var onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Card \(cardIndex)")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.expressionOrWord)
                        .font(.title3.bold())
                    if let reading = note.reading, !reading.isEmpty {
                        Text(reading)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if note.needsReview {
                    Text("Needs review")
                        .font(.caption2)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
                        .foregroundColor(.orange)
                }
            }

            if let book = note.bookMatch, !book.isEmpty {
                Label(book, systemImage: "book")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let ai = note.aiTranslation, let hand = note.handTranslation, ai != hand, !ai.isEmpty, !hand.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Handwritten translation: \(hand)")
                    Text("AI translation: \(ai)")
                        .foregroundColor(.secondary)
                }
                .font(.footnote)
            }

            Text(note.meaning)
                .font(.body)

            if let example = note.example, !example.isEmpty {
                Text(example)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let source = note.sourcePage {
                Text("Image: \(source)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                if let conf = note.confMatch {
                    ProgressView(value: conf)
                        .tint(note.needsReview ? .orange : .green)
                        .frame(maxWidth: 120)
                }
                if let ocr = note.confOcr {
                    Text(String(format: "OCR %.0f%%", ocr * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if showValidation {
                HStack {
                    Button("Approve") { onApprove() }
                        .buttonStyle(.borderedProminent)
                    Button("Reject") { onReject() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ActionBarButtonLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let activeTop = Color(red: 0.76, green: 0.90, blue: 1.00)
        let activeBottom = Color(red: 0.74, green: 0.91, blue: 0.90)
        let activeStroke = Color(red: 0.34, green: 0.65, blue: 0.88)
        let disabledTop = Color(red: 0.81, green: 0.86, blue: 0.92)
        let disabledBottom = Color(red: 0.77, green: 0.82, blue: 0.89)
        let disabledStroke = Color(red: 0.66, green: 0.72, blue: 0.80)

        VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .lineLimit(1)
                .opacity(isEnabled ? 0.82 : 0.95)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundColor(
            isEnabled
                ? Color(red: 0.07, green: 0.27, blue: 0.46)
                : Color(red: 0.37, green: 0.44, blue: 0.54)
        )
        .background { shape.fill(.ultraThinMaterial) }
        .overlay {
            shape.fill(
                LinearGradient(
                    colors: isEnabled ? [activeTop, activeBottom] : [disabledTop, disabledBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(isEnabled ? 0.52 : 0.45)
        }
        .overlay {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.62), Color.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(isEnabled ? 1.0 : 0.7)
        }
        .overlay(
            shape
                .stroke(
                    isEnabled
                        ? activeStroke.opacity(0.68)
                        : disabledStroke.opacity(0.88),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(isEnabled ? 0.07 : 0.04), radius: 8, y: 4)
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let isOnline: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.systemBackground).opacity(0.88))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(accent.opacity(0.26), lineWidth: 1)
        )
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }
    }
}

private struct ExportOptionsSheet: View {
    let ankiEnabled: Bool
    let csvEnabled: Bool
    var onAnki: () -> Void
    var onCSV: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export cards")
                .font(.headline)
            Text("Choose export destination")
                .font(.footnote)
                .foregroundColor(.secondary)

            Button {
                onAnki()
            } label: {
                Label("Anki", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(ankiEnabled == false)

            Button {
                onCSV()
            } label: {
                Label("CSV", systemImage: "tablecells.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(csvEnabled == false)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.height(240)])
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Skip SwiftUI previews when the preview plugin is unavailable (e.g., CI or headless builds).
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
#endif
