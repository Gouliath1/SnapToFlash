import Foundation

enum AnkiImportFileExporter {
    enum ExportError: LocalizedError {
        case noData

        var errorDescription: String? {
            switch self {
            case .noData:
                return "Failed to encode Anki import file."
            }
        }
    }

    static func makeImportText(from notes: [AnkiNote], deckName: String) -> String {
        var rows: [String] = [
            "#separator:tab",
            "#html:true",
            "#notetype:Basic",
            "#deck:\(sanitizeHeaderValue(deckName))",
            "#columns:Front\tBack"
        ]

        for note in notes {
            let front = frontField(for: note)
            let back = backField(for: note)
            rows.append("\(field(front))\t\(field(back))")
        }

        return rows.joined(separator: "\n")
    }

    static func writeTempImportFile(from notes: [AnkiNote], suggestedName: String, deckName: String) throws -> URL {
        let text = makeImportText(from: notes, deckName: deckName)
        guard let data = text.data(using: .utf8) else { throw ExportError.noData }

        let filename = sanitizedFilename(from: suggestedName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)-\(timestamp())-anki-import.txt")

        try data.write(to: url, options: .atomic)
        return url
    }

    private static func frontField(for note: AnkiNote) -> String {
        let head = htmlEscape(note.expressionOrWord)
        let reading = (note.reading ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard reading.isEmpty == false else { return head }
        return "\(head)<div style=\"color:#666;font-size:0.9em;\">\(htmlEscape(reading))</div>"
    }

    private static func backField(for note: AnkiNote) -> String {
        var parts: [String] = []
        let meaning = note.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if meaning.isEmpty == false {
            parts.append("<div>\(htmlEscape(meaning))</div>")
        }

        let example = (note.example ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if example.isEmpty == false {
            parts.append("<div style=\"margin-top:10px;\">\(htmlEscape(example))</div>")
        }

        if parts.isEmpty {
            return "<div></div>"
        }
        return parts.joined()
    }

    private static func field(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func sanitizeHeaderValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Deckify"
        }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func sanitizedFilename(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Deckify" }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))

        return collapsed.isEmpty ? "Deckify" : collapsed
    }
}
