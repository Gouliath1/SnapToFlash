import Foundation
import UniformTypeIdentifiers

struct BackendClient {
    var baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = BackendClient.defaultBaseURL(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func isAvailable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse { return 200..<300 ~= http.statusCode }
        } catch {
            return false
        }
        return false
    }

    func analyzePage(imageData: Data, pageId: String?) async throws -> PageAnalysisResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/analyze-page"))
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let filename = (pageId ?? "page") + ".jpg"
        let fieldName = "image"
        let mimeType = UTType.jpeg.identifier

        // image data
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")

        // optional pageId
        if let pageId {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"page_id\"\r\n\r\n")
            body.appendString(pageId)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw BackendError.badStatus
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(PageAnalysisResponse.self, from: data)
            return payload
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(600) ?? "<non-utf8>"
            throw BackendError.decodingFailed(error, bodyPreview: String(bodyPreview))
        }
    }

    enum BackendError: Error, LocalizedError {
        case badStatus
        case decodingFailed(Error, bodyPreview: String)

        var errorDescription: String? {
            switch self {
            case .badStatus: return "Server returned an error status."
            case .decodingFailed(let err, let bodyPreview):
                return "Unable to decode response: \(describeDecodingError(err)). Body: \(bodyPreview)"
            }
        }

        private func describeDecodingError(_ error: Error) -> String {
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    return "Type mismatch for \(type): \(context.debugDescription) at \(codingPath(context.codingPath))"
                case .valueNotFound(let type, let context):
                    return "Missing value for \(type): \(context.debugDescription) at \(codingPath(context.codingPath))"
                case .keyNotFound(let key, let context):
                    return "Missing key '\(key.stringValue)': \(context.debugDescription) at \(codingPath(context.codingPath))"
                case .dataCorrupted(let context):
                    return "Data corrupted: \(context.debugDescription) at \(codingPath(context.codingPath))"
                @unknown default:
                    return error.localizedDescription
                }
            }
            return error.localizedDescription
        }

        private func codingPath(_ path: [CodingKey]) -> String {
            path.map(\.stringValue).joined(separator: ".")
        }
    }
}

// MARK: - Helpers

extension BackendClient {
    /// Reads BackendBaseURL{Debug|Release} based on build configuration,
    /// then falls back to BackendBaseURL and finally 127.0.0.1.
    static func defaultBaseURL() -> URL {
        #if DEBUG
        let preferredKey = "BackendBaseURLDebug"
        #else
        let preferredKey = "BackendBaseURLRelease"
        #endif

        if let str = Bundle.main.object(forInfoDictionaryKey: preferredKey) as? String,
           let url = URL(string: str) {
            return url
        }

        if let str = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           let url = URL(string: str) {
            return url
        }
        return URL(string: "http://127.0.0.1:8787")!
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
