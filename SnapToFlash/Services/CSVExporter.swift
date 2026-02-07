import Foundation

enum CSVExporter {
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

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
