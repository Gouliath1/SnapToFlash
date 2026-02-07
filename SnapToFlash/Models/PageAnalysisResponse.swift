import Foundation

struct PageAnalysisResponse: Codable {
    var pageId: String?
    var confidence: Double
    var needsReview: Bool
    var warnings: [String]
    var annotations: [AnnotationMark]
    var ankiNotes: [AnkiNote]
}
