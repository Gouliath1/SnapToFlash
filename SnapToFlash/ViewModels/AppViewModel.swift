import Foundation
import SwiftUI
import PhotosUI
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var pages: [PageInput] = []
    @Published var notes: [AnkiNote] = []
    @Published var warnings: [String] = []
    @Published var isAnalyzing = false
    @Published var statusText: String?
    @Published var errorMessage: String?
    @Published var ankiAvailable: Bool = false

    private let backend: BackendClient
    private let anki: AnkiConnectService

    convenience init() {
        self.init(backend: BackendClient(), anki: AnkiConnectService())
    }

    init(backend: BackendClient, anki: AnkiConnectService) {
        self.backend = backend
        self.anki = anki
        Task { await refreshAnkiAvailability() }
    }

    func refreshAnkiAvailability() async {
        ankiAvailable = await anki.isAvailable()
    }

    func addPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { continue }
                let name = item.itemIdentifier ?? "page_\(pages.count + 1)"
                let page = PageInput(image: uiImage, filename: name)
                pages.append(page)
            }
        }
    }

    func removePage(_ page: PageInput) {
        pages.removeAll { $0.id == page.id }
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
                    collectedNotes.append(contentsOf: response.ankiNotes)
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }

            // dedupe
            notes = dedupe(collectedNotes)
            statusText = "Generated \(notes.count) cards"
            isAnalyzing = false
        }
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
        var seen: [String: AnkiNote] = [:]
        for note in notes {
            let key = "\(note.expressionOrWord.lowercased().trimmingCharacters(in: .whitespaces))|\(note.reading?.lowercased() ?? "")"
            if let existing = seen[key] {
                // keep both only if meaning differs
                if existing.meaning != note.meaning {
                    seen[key + "#\(UUID().uuidString)"] = note
                }
            } else {
                seen[key] = note
            }
        }
        return Array(seen.values)
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
