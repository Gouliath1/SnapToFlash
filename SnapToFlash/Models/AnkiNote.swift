import Foundation

struct AnkiNote: Identifiable, Codable, Hashable {
    let id: UUID
    var expressionOrWord: String
    var reading: String?
    var meaning: String
    var example: String?
    var confidence: Double
    var needsReview: Bool

    init(id: UUID = UUID(), expressionOrWord: String, reading: String?, meaning: String, example: String?, confidence: Double, needsReview: Bool) {
        self.id = id
        self.expressionOrWord = expressionOrWord
        self.reading = reading
        self.meaning = meaning
        self.example = example
        self.confidence = confidence
        self.needsReview = needsReview
    }
}
