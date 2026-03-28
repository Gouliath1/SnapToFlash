import Foundation

struct VisionOCRPayload: Codable, Hashable {
    var sourceImageId: String
    var selectedVariant: String
    var languageCode: String
    var aggregateConfidence: Double
    var qualityScore: Double
    var lines: [VisionOCRLine]

    var confidenceValuesAreBounded: Bool {
        let rootValuesAreBounded = (0...1).contains(aggregateConfidence) && (0...1).contains(qualityScore)
        guard rootValuesAreBounded else { return false }
        return lines.allSatisfy(\.confidenceValuesAreBounded)
    }
}

struct VisionOCRLine: Codable, Hashable {
    var text: String
    var confidence: Double
    var boundingBox: OCRBoundingBox
    var tokens: [VisionOCRToken]

    var confidenceValuesAreBounded: Bool {
        guard (0...1).contains(confidence), boundingBox.isNormalized else {
            return false
        }
        return tokens.allSatisfy(\.confidenceValuesAreBounded)
    }
}

struct VisionOCRToken: Codable, Hashable {
    var text: String
    var confidence: Double
    var boundingBox: OCRBoundingBox

    var confidenceValuesAreBounded: Bool {
        (0...1).contains(confidence) && boundingBox.isNormalized
    }
}

struct OCRBoundingBox: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isNormalized: Bool {
        (0...1).contains(x) &&
        (0...1).contains(y) &&
        (0...1).contains(width) &&
        (0...1).contains(height)
    }
}
