import Foundation
import UniformTypeIdentifiers

struct BackendClient {
    var baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL = BackendClient.defaultBaseURL(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
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
            throw BackendError.decodingFailed(error)
        }
    }

    enum BackendError: Error, LocalizedError {
        case badStatus
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .badStatus: return "Server returned an error status."
            case .decodingFailed(let err): return "Unable to decode response: \(err.localizedDescription)"
            }
        }
    }
}

// MARK: - Helpers

extension BackendClient {
    /// Reads BackendBaseURL from Info.plist; falls back to localhost.
    static func defaultBaseURL() -> URL {
        if let str = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           let url = URL(string: str) {
            return url
        }
        return URL(string: "http://localhost:8787")!
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
