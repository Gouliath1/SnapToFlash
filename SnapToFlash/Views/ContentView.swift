import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var deckName: String = "SnapToFlash"
    @State private var showCSVShare = false
    @State private var csvString: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    captureSection
                    progressSection
                    resultsSection
                }
                .padding()
            }
            .navigationTitle("SnapToFlash")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ankiStatus } }
        }
        .sheet(isPresented: $showCSVShare) {
            ShareSheet(activityItems: [csvString])
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1) Capture or import annotated pages")
                .font(.headline)

            #if DEBUG
            Button {
                model.analyzePages() // placeholder to keep button style consistent
            } label: {
                EmptyView()
            }.hidden() // keeps alignment if we add more debug UI later
            #endif

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("Import photos", systemImage: "photo.on.rectangle")
            }
            .onChange(of: pickerItems) { newItems in
                model.addPhotos(newItems)
            }

            #if DEBUG
            Button {
                // Force reload of bundled samples in case they weren't found at init.
                model.performSampleReload()
            } label: {
                Label("Load bundled sample pages", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.bordered)
            #endif

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

            Button {
                model.analyzePages()
            } label: {
                Label("Generate flashcards", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isAnalyzing || model.pages.isEmpty)
        }
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

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Deck name", text: $deckName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Send to Anki") {
                            Task { await model.sendToAnki(deckName: deckName) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isAnalyzing || model.notes.isEmpty || model.ankiAvailable == false)

                        Button("Export CSV") {
                            csvString = model.exportCSV()
                            showCSVShare = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.notes.isEmpty)
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
                HStack {
                    Button("Accept all pending") { model.validateAllPending() }
                        .buttonStyle(.borderedProminent)
                    Button("Clear pending") { model.pendingNotes.removeAll() }
                        .buttonStyle(.bordered)
                }
            }
        }
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
