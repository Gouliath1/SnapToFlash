import Foundation

struct AnnotationMark: Identifiable, Codable, Hashable {
    enum MarkType: String, Codable {
        case underline, overline, highlight, circle, box, arrow, marginNote, strikethrough, handwriting, other
    }

    let id: UUID
    var type: MarkType
    var color: String?
    var boundingBox: [Double]? // [x1, y1, x2, y2]
    var annotationText: String?
    var targetText: String?
    var targetContext: String?
    var confidence: Double

    init(id: UUID = UUID(), type: MarkType, color: String?, boundingBox: [Double]?, annotationText: String?, targetText: String?, targetContext: String?, confidence: Double) {
        self.id = id
        self.type = type
        self.color = color
        self.boundingBox = boundingBox
        self.annotationText = annotationText
        self.targetText = targetText
        self.targetContext = targetContext
        self.confidence = confidence
    }
}
