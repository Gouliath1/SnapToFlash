import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var deckName: String = "SnapToFlash"
    @State private var showCSVShare = false
    @State private var csvString: String = ""
    @State private var showCameraPicker = false
    @State private var showLoadOptions = false
    @State private var showValidationOptions = false
    @State private var showPhotoLibraryPicker = false
    @State private var showExportOptions = false
    @State private var shouldPresentCSVAfterExportSheet = false

    private let actionBarHeight: CGFloat = 120

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    captureSection
                    progressSection
                    resultsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .padding(.bottom, actionBarHeight)
            }
            .navigationTitle("SnapToFlash")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ankiStatus } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .onChange(of: pickerItems) { newItems in
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

    private var captureSection: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var resultsSection: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                showLoadOptions = true
            } label: {
                ActionBarButtonLabel(
                    title: "Load",
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
        .overlay(alignment: .top) {
            Divider()
        }
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
        HStack(spacing: 6) {
            Circle()
                .fill(model.ankiAvailable ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(model.ankiAvailable ? "Anki" : "Anki off")
                .font(.footnote)
        }
        .onTapGesture { Task { await model.refreshAnkiAvailability() } }
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
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

private struct ActionBarButtonLabel: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundColor(isEnabled ? .accentColor : .gray)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isEnabled ? Color.accentColor.opacity(0.14) : Color.gray.opacity(0.12))
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
