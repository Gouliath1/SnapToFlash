import Foundation

struct AnkiNote: Identifiable, Codable, Hashable {
    let id: UUID
    var expressionOrWord: String
    var reading: String?
    var meaning: String
    var example: String?
    var confidence: Double
    var needsReview: Bool
    var sourcePage: String?
    var handTranslation: String?
    var aiTranslation: String?
    var bookMatch: String?
    var confMatch: Double?
    var confOcr: Double?
    var visionOCRQuality: Double?
    var visionOCRVariant: String?

    init(
        id: UUID = UUID(),
        expressionOrWord: String,
        reading: String?,
        meaning: String,
        example: String?,
        confidence: Double,
        needsReview: Bool,
        sourcePage: String? = nil,
        handTranslation: String? = nil,
        aiTranslation: String? = nil,
        bookMatch: String? = nil,
        confMatch: Double? = nil,
        confOcr: Double? = nil,
        visionOCRQuality: Double? = nil,
        visionOCRVariant: String? = nil
    ) {
        self.id = id
        self.expressionOrWord = expressionOrWord
        self.reading = reading
        self.meaning = meaning
        self.example = example
        self.confidence = confidence
        self.needsReview = needsReview
        self.sourcePage = sourcePage
        self.handTranslation = handTranslation
        self.aiTranslation = aiTranslation
        self.bookMatch = bookMatch
        self.confMatch = confMatch
        self.confOcr = confOcr
        self.visionOCRQuality = visionOCRQuality
        self.visionOCRVariant = visionOCRVariant
    }
}
