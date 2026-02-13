import Foundation

enum CSVExporter {
    enum CSVError: LocalizedError {
        case noData

        var errorDescription: String? {
            switch self {
            case .noData:
                return "Failed to encode CSV."
            }
        }
    }

    static func makeCSV(from notes: [AnkiNote]) -> String {
        var rows = ["ExpressionOrWord,Reading,Meaning,Example"]
        for note in notes {
            let line = [note.expressionOrWord, note.reading ?? "", note.meaning, note.example ?? ""]
                .map { escape($0) }
                .joined(separator: ",")
            rows.append(line)
        }
        return rows.joined(separator: "\n")
    }

    static func writeTempCSV(from notes: [AnkiNote], suggestedName: String) throws -> URL {
        let csv = makeCSV(from: notes)
        guard let data = csv.data(using: .utf8) else { throw CSVError.noData }

        let filename = sanitizedFilename(from: suggestedName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)-\(timestamp()).csv")

        try data.write(to: url, options: .atomic)
        return url
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

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
