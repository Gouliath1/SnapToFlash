//
//  SnapToFlashTests.swift
//  SnapToFlashTests
//
//  Created by Julien Guille on 2026/02/05.
//

import Testing
import UIKit
@testable import SnapToFlash

struct SnapToFlashTests {
    @MainActor
    @Test
    func appViewModelPersistsOCRProcessingMode() {
        let settings = InMemorySettingsStore()
        let backend = BackendClient(baseURL: URL(string: "http://127.0.0.1:8787")!)
        let anki = AnkiConnectService()

        let initialModel = AppViewModel(
            backend: backend,
            anki: anki,
            visionOCRAvailable: true,
            settings: settings
        )
        #expect(initialModel.ocrProcessingMode == .visionAssist)

        initialModel.setOCRProcessingMode(.llmOnly)
        #expect(initialModel.ocrProcessingMode == .llmOnly)
        #expect(settings.string(forKey: AppSettingsKeys.ocrProcessingMode) == OCRProcessingMode.llmOnly.rawValue)

        let restoredModel = AppViewModel(
            backend: backend,
            anki: anki,
            visionOCRAvailable: true,
            settings: settings
        )
        #expect(restoredModel.ocrProcessingMode == .llmOnly)

        settings.set(OCRProcessingMode.visionAssist.rawValue, forKey: AppSettingsKeys.ocrProcessingMode)
        let unavailableVisionModel = AppViewModel(
            backend: backend,
            anki: anki,
            visionOCRAvailable: false,
            settings: settings
        )
        #expect(unavailableVisionModel.ocrProcessingMode == .llmOnly)
        #expect(settings.string(forKey: AppSettingsKeys.ocrProcessingMode) == OCRProcessingMode.llmOnly.rawValue)
    }

    @Test
    func payloadConfidenceBoundsValidation() {
        let valid = makePayload(
            aggregate: 0.86,
            quality: 0.81,
            lineText: "勉強する",
            lineConfidence: 0.92,
            tokenConfidence: 0.93
        )
        #expect(valid.confidenceValuesAreBounded)

        let invalid = makePayload(
            aggregate: 1.2,
            quality: 0.81,
            lineText: "勉強する",
            lineConfidence: 0.92,
            tokenConfidence: 0.93
        )
        #expect(invalid.confidenceValuesAreBounded == false)
    }

    @Test
    func preprocessorReturnsNaturalAndEnhancedCandidates() {
        let image = makeSolidImage(width: 1200, height: 800)
        let candidates = ImagePreprocessor.prepareOCRCandidates(image, maxLongEdge: 900, jpegQuality: 0.8)

        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.variant == .natural })
        #expect(candidates.contains { $0.variant == .enhanced })
        #expect(candidates.allSatisfy { $0.jpegData.isEmpty == false })
    }

    @Test
    func qualityScorePenalizesNoisyText() {
        let box = OCRBoundingBox(x: 0.1, y: 0.1, width: 0.4, height: 0.1)

        let cleanLines = [
            VisionOCRLine(
                text: "勉強する",
                confidence: 0.9,
                boundingBox: box,
                tokens: [VisionOCRToken(text: "勉強する", confidence: 0.9, boundingBox: box)]
            )
        ]
        let noisyLines = [
            VisionOCRLine(
                text: "@@@ ### ???",
                confidence: 0.9,
                boundingBox: box,
                tokens: [VisionOCRToken(text: "@@@", confidence: 0.9, boundingBox: box)]
            )
        ]

        let cleanScore = VisionOCRService.qualityScore(for: cleanLines)
        let noisyScore = VisionOCRService.qualityScore(for: noisyLines)

        #expect((0...1).contains(cleanScore))
        #expect((0...1).contains(noisyScore))
        #expect(cleanScore > noisyScore)
    }

    @Test
    func selectBestUsesDeterministicTieBreaks() {
        let better = VisionOCRService.ScoredCandidate(
            variant: .enhanced,
            payload: makePayload(
                selectedVariant: "enhanced",
                aggregate: 0.88,
                quality: 0.9,
                lineText: "練習",
                lineConfidence: 0.88,
                tokenConfidence: 0.88
            ),
            score: 0.9
        )
        let worse = VisionOCRService.ScoredCandidate(
            variant: .natural,
            payload: makePayload(
                selectedVariant: "natural",
                aggregate: 0.86,
                quality: 0.8,
                lineText: "練習",
                lineConfidence: 0.86,
                tokenConfidence: 0.86
            ),
            score: 0.8
        )

        let best = VisionOCRService.selectBest([worse, better])
        #expect(best?.variant == .enhanced)

        let tieEnhanced = VisionOCRService.ScoredCandidate(
            variant: .enhanced,
            payload: makePayload(
                selectedVariant: "enhanced",
                aggregate: 0.8,
                quality: 0.8,
                lineText: "読む",
                lineConfidence: 0.8,
                tokenConfidence: 0.8
            ),
            score: 0.8
        )
        let tieNatural = VisionOCRService.ScoredCandidate(
            variant: .natural,
            payload: makePayload(
                selectedVariant: "natural",
                aggregate: 0.8,
                quality: 0.8,
                lineText: "読む",
                lineConfidence: 0.8,
                tokenConfidence: 0.8
            ),
            score: 0.8
        )

        let tieWinner = VisionOCRService.selectBest([tieEnhanced, tieNatural])
        #expect(tieWinner?.variant == .natural)
    }

    private func makePayload(
        selectedVariant: String = "natural",
        aggregate: Double,
        quality: Double,
        lineText: String,
        lineConfidence: Double,
        tokenConfidence: Double
    ) -> VisionOCRPayload {
        let box = OCRBoundingBox(x: 0.2, y: 0.2, width: 0.3, height: 0.1)
        let token = VisionOCRToken(text: lineText, confidence: tokenConfidence, boundingBox: box)
        let line = VisionOCRLine(text: lineText, confidence: lineConfidence, boundingBox: box, tokens: [token])
        return VisionOCRPayload(
            sourceImageId: "page_1",
            selectedVariant: selectedVariant,
            languageCode: "ja-JP",
            aggregateConfidence: aggregate,
            qualityScore: quality,
            lines: [line]
        )
    }

    private func makeSolidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.black.setFill()
            context.fill(CGRect(x: 120, y: 160, width: 400, height: 32))
        }
    }
}

private final class InMemorySettingsStore: AppSettingsStoring {
    private var storage: [String: Any] = [:]

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}
