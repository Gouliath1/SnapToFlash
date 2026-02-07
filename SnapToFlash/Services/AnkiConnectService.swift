import Foundation

struct AnkiConnectService {
    private let endpoint = URL(string: "http://127.0.0.1:8765")!
    private let session: URLSession = .shared

    func isAvailable() async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try? encode(action: "version", params: [:])
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse { return http.statusCode == 200 }
        } catch { return false }
        return false
    }

    func addNotes(deckName: String, modelName: String = "SnapToFlash", notes: [AnkiNote]) async throws {
        guard !notes.isEmpty else { return }

        let payload: [String: Any] = [
            "action": "addNotes",
            "version": 6,
            "params": [
                "notes": notes.map { note in
                    [
                        "deckName": deckName,
                        "modelName": modelName,
                        "fields": [
                            "ExpressionOrWord": note.expressionOrWord,
                            "Reading": note.reading ?? "",
                            "Meaning": note.meaning,
                            "Example": note.example ?? ""
                        ],
                        "options": [
                            "allowDuplicate": false,
                            "duplicateScope": "deck"
                        ]
                    ]
                }
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AnkiError.badStatus
        }

        // AnkiConnect returns { result: [noteIds] | null, error: string | null }
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let error = json["error"] as? String, error.isEmpty == false {
            throw AnkiError.apiError(error)
        }
    }

    private func encode(action: String, params: [String: Any]) throws -> Data {
        let json: [String: Any] = ["action": action, "version": 6, "params": params]
        return try JSONSerialization.data(withJSONObject: json)
    }

    enum AnkiError: Error, LocalizedError {
        case badStatus
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .badStatus: return "AnkiConnect unreachable"
            case .apiError(let message): return message
            }
        }
    }
}
