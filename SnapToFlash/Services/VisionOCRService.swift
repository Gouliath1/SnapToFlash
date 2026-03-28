import Foundation
import UIKit
import Vision
import CoreImage

struct VisionOCRService {
    struct ScoredCandidate: Hashable {
        var variant: ImagePreprocessor.OCRVariant
        var payload: VisionOCRPayload
        var score: Double
    }

    enum VisionOCRError: LocalizedError {
        case noCandidates
        case unsupportedImage
        case timedOut(seconds: Double)

        var errorDescription: String? {
            switch self {
            case .noCandidates:
                return "No OCR image candidates were provided."
            case .unsupportedImage:
                return "The image could not be converted to a supported format for Vision OCR."
            case .timedOut(let seconds):
                return "Vision OCR timed out after \(Int(seconds))s."
            }
        }
    }

    func recognizeBest(
        from candidates: [ImagePreprocessor.OCRCandidate],
        sourceImageId: String
    ) async throws -> VisionOCRPayload {
        Self.log("recognizeBest start | source=\(sourceImageId) | candidates=\(candidates.count)")
        guard candidates.isEmpty == false else {
            Self.log("recognizeBest fail | source=\(sourceImageId) | reason=no_candidates")
            throw VisionOCRError.noCandidates
        }

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            func finish(_ result: Result<VisionOCRPayload, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard hasResumed == false else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let startedAt = Date()
                Self.log("recognizeBest worker start | source=\(sourceImageId)")
                do {
                    let payload = try Self.recognizeBestSynchronously(from: candidates, sourceImageId: sourceImageId)
                    let elapsedMs = Date().timeIntervalSince(startedAt) * 1000
                    Self.log(
                        "recognizeBest worker done | source=\(sourceImageId) | lines=\(payload.lines.count) | variant=\(payload.selectedVariant) | elapsed_ms=\(String(format: "%.1f", elapsedMs))"
                    )
                    finish(.success(payload))
                } catch {       
                    let elapsedMs = Date().timeIntervalSince(startedAt) * 1000
                    Self.log(
                        "recognizeBest worker error | source=\(sourceImageId) | elapsed_ms=\(String(format: "%.1f", elapsedMs)) | error=\(error.localizedDescription)"
                    )
                    finish(.failure(error))
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.recognitionTimeoutSeconds) {
                Self.log("recognizeBest timeout | source=\(sourceImageId) | seconds=\(Int(Self.recognitionTimeoutSeconds))")
                finish(.failure(VisionOCRError.timedOut(seconds: Self.recognitionTimeoutSeconds)))
            }
        }
    }

    func recognizeBestBlocking(
        from candidates: [ImagePreprocessor.OCRCandidate],
        sourceImageId: String
    ) throws -> VisionOCRPayload {
        let startedAt = Date()
        Self.log("recognizeBestBlocking start | source=\(sourceImageId) | candidates=\(candidates.count)")
        let payload = try Self.recognizeBestSynchronously(from: candidates, sourceImageId: sourceImageId)
        let elapsedMs = Date().timeIntervalSince(startedAt) * 1000
        Self.log(
            "recognizeBestBlocking done | source=\(sourceImageId) | lines=\(payload.lines.count) | variant=\(payload.selectedVariant) | elapsed_ms=\(String(format: "%.1f", elapsedMs))"
        )
        return payload
    }

    static func selectBest(_ candidates: [ScoredCandidate]) -> ScoredCandidate? {
        candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            if lhs.payload.aggregateConfidence != rhs.payload.aggregateConfidence {
                return lhs.payload.aggregateConfidence > rhs.payload.aggregateConfidence
            }

            return lhs.variant.tieBreakRank < rhs.variant.tieBreakRank
        }.first
    }

    static func aggregateConfidence(for lines: [VisionOCRLine]) -> Double {
        let confidences = lines.flatMap { line -> [Double] in
            if line.tokens.isEmpty {
                return [line.confidence]
            }
            return line.tokens.map(\.confidence)
        }

        guard confidences.isEmpty == false else {
            return 0
        }

        let mean = confidences.reduce(0, +) / Double(confidences.count)
        return clamp(mean)
    }

    static func qualityScore(for lines: [VisionOCRLine]) -> Double {
        guard lines.isEmpty == false else {
            return 0
        }

        let confidence = aggregateConfidence(for: lines)
        let script = scriptMetrics(for: lines)
        let emptyLineRatio = Double(lines.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(lines.count)

        let rawScore =
            (0.72 * confidence) +
            (0.24 * script.japaneseRatio) -
            (0.28 * script.noiseRatio) -
            (0.12 * emptyLineRatio)

        return clamp(rawScore)
    }

    private static func recognizeBestSynchronously(
        from candidates: [ImagePreprocessor.OCRCandidate],
        sourceImageId: String
    ) throws -> VisionOCRPayload {
        log("recognizeBestSynchronously start | source=\(sourceImageId) | candidates=\(candidates.count)")
        var scored: [ScoredCandidate] = []
        for candidate in candidates {
            let candidateStartedAt = Date()
            log(
                "candidate start | source=\(sourceImageId) | variant=\(candidate.variant.rawValue) | size=\(Int(candidate.image.size.width))x\(Int(candidate.image.size.height))"
            )
            var payload = try recognizeSynchronously(candidate, sourceImageId: sourceImageId)
            let score = qualityScore(for: payload.lines)
            payload.aggregateConfidence = aggregateConfidence(for: payload.lines)
            payload.qualityScore = score
            let elapsedMs = Date().timeIntervalSince(candidateStartedAt) * 1000
            log(
                "candidate done | source=\(sourceImageId) | variant=\(candidate.variant.rawValue) | lines=\(payload.lines.count) | aggregate=\(String(format: "%.2f", payload.aggregateConfidence)) | quality=\(String(format: "%.2f", payload.qualityScore)) | elapsed_ms=\(String(format: "%.1f", elapsedMs))"
            )
            scored.append(ScoredCandidate(variant: candidate.variant, payload: payload, score: score))
        }

        guard let selected = selectBest(scored) else {
            log("recognizeBestSynchronously fail | source=\(sourceImageId) | reason=no_scored_candidates")
            throw VisionOCRError.noCandidates
        }
        log(
            "recognizeBestSynchronously selected | source=\(sourceImageId) | variant=\(selected.variant.rawValue) | lines=\(selected.payload.lines.count) | score=\(String(format: "%.2f", selected.score))"
        )
        return selected.payload
    }

    private static func recognizeSynchronously(
        _ candidate: ImagePreprocessor.OCRCandidate,
        sourceImageId: String
    ) throws -> VisionOCRPayload {
        guard let cgImage = cgImage(from: candidate.image) else {
            log("recognizeSynchronously fail | source=\(sourceImageId) | variant=\(candidate.variant.rawValue) | reason=unsupported_image")
            throw VisionOCRError.unsupportedImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [recognitionLanguageCode]
        request.usesLanguageCorrection = true

        let performStartedAt = Date()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let performElapsedMs = Date().timeIntervalSince(performStartedAt) * 1000
        log(
            "vision request done | source=\(sourceImageId) | variant=\(candidate.variant.rawValue) | elapsed_ms=\(String(format: "%.1f", performElapsedMs)) | observations=\((request.results ?? []).count)"
        )

        let lines = (request.results ?? [])
            .compactMap { observation -> VisionOCRLine? in
                guard let top = observation.topCandidates(1).first else {
                    return nil
                }

                let lineText = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard lineText.isEmpty == false else {
                    return nil
                }

                let lineBox = normalizedTopLeftBoundingBox(from: observation.boundingBox)
                let confidence = clamp(Double(top.confidence))
                let tokens = extractTokens(from: top, lineText: lineText, fallbackBox: lineBox)

                return VisionOCRLine(
                    text: lineText,
                    confidence: confidence,
                    boundingBox: lineBox,
                    tokens: tokens
                )
            }
            .sorted(by: readingOrderSort)

        return VisionOCRPayload(
            sourceImageId: sourceImageId,
            selectedVariant: candidate.variant.rawValue,
            languageCode: recognitionLanguageCode,
            aggregateConfidence: aggregateConfidence(for: lines),
            qualityScore: qualityScore(for: lines),
            lines: lines
        )
    }

    private static func extractTokens(
        from recognizedText: VNRecognizedText,
        lineText: String,
        fallbackBox: OCRBoundingBox
    ) -> [VisionOCRToken] {
        let ranges = tokenRanges(in: lineText)
        let confidence = clamp(Double(recognizedText.confidence))

        var tokens: [VisionOCRToken] = []
        tokens.reserveCapacity(max(1, ranges.count))

        for range in ranges {
            let tokenText = String(lineText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard tokenText.isEmpty == false else {
                continue
            }

            let tokenBox: OCRBoundingBox
            if let bounding = try? recognizedText.boundingBox(for: range) {
                tokenBox = normalizedTopLeftBoundingBox(from: bounding.boundingBox)
            } else {
                tokenBox = fallbackBox
            }

            tokens.append(VisionOCRToken(text: tokenText, confidence: confidence, boundingBox: tokenBox))
        }

        if tokens.isEmpty {
            return [VisionOCRToken(text: lineText, confidence: confidence, boundingBox: fallbackBox)]
        }
        return tokens
    }

    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex

        while start < text.endIndex {
            while start < text.endIndex, text[start].isWhitespace {
                start = text.index(after: start)
            }
            guard start < text.endIndex else { break }

            var end = start
            while end < text.endIndex, text[end].isWhitespace == false {
                end = text.index(after: end)
            }

            ranges.append(start..<end)
            start = end
        }

        return ranges
    }

    private static func readingOrderSort(_ lhs: VisionOCRLine, _ rhs: VisionOCRLine) -> Bool {
        let verticalDelta = lhs.boundingBox.y - rhs.boundingBox.y
        if abs(verticalDelta) > 0.015 {
            return verticalDelta < 0
        }
        return lhs.boundingBox.x < rhs.boundingBox.x
    }

    private static func scriptMetrics(for lines: [VisionOCRLine]) -> (japaneseRatio: Double, noiseRatio: Double) {
        let text = lines.map(\.text).joined(separator: " ")

        var japaneseCount = 0
        var noiseCount = 0
        var measuredCount = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            measuredCount += 1
            if isJapanese(scalar) {
                japaneseCount += 1
                continue
            }

            if isAllowedNonJapanese(scalar) == false {
                noiseCount += 1
            }
        }

        guard measuredCount > 0 else {
            return (0, 1)
        }

        return (
            Double(japaneseCount) / Double(measuredCount),
            Double(noiseCount) / Double(measuredCount)
        )
    }

    private static func isJapanese(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, // Hiragana
             0x30A0...0x30FF, // Katakana
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0x3400...0x4DBF, // CJK Extension A
             0xFF66...0xFF9D: // Half-width Katakana
            return true
        default:
            return false
        }
    }

    private static func isAllowedNonJapanese(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.decimalDigits.contains(scalar) || CharacterSet.letters.contains(scalar) {
            return true
        }

        return allowedPunctuation.contains(scalar)
    }

    private static func normalizedTopLeftBoundingBox(from rect: CGRect) -> OCRBoundingBox {
        let x = clamp(rect.origin.x)
        let y = clamp(1 - rect.origin.y - rect.size.height)
        let width = clamp(rect.size.width)
        let height = clamp(rect.size.height)
        return OCRBoundingBox(x: x, y: y, width: width, height: height)
    }

    private static func cgImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }

        guard let ciImage = image.ciImage else {
            return nil
        }

        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private static func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private static func clamp(_ value: CGFloat) -> Double {
        clamp(Double(value))
    }

    private static let recognitionLanguageCode = "ja-JP"
    private static let recognitionTimeoutSeconds: Double = 25
    private static let ciContext = CIContext(options: nil)
    private static let allowedPunctuation = CharacterSet(charactersIn: "。、，,.！？!?・:;：；「」『』（）()[]{}-ー_/\\\"'~")

    private static func log(_ message: String) {
        print("[VisionOCR] \(message)")
    }
}

private extension ImagePreprocessor.OCRVariant {
    var tieBreakRank: Int {
        switch self {
        case .natural: return 0
        case .enhanced: return 1
        }
    }
}
