import Foundation

enum OCRProcessingMode: String, CaseIterable, Identifiable {
    case visionAssist = "vision_assist"
    case llmOnly = "llm_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visionAssist:
            return "Vision + LLM"
        case .llmOnly:
            return "LLM Only"
        }
    }

    var badgeTitle: String {
        switch self {
        case .visionAssist:
            return "Local Vision"
        case .llmOnly:
            return "Direct LLM"
        }
    }

    var usesOnDeviceVision: Bool {
        self == .visionAssist
    }

    var descriptionText: String {
        switch self {
        case .visionAssist:
            return "Run Apple Vision OCR on-device first, then send the image and OCR context to the backend LLM."
        case .llmOnly:
            return "Skip on-device OCR and let the backend LLM read the page image directly."
        }
    }

    func debugStatusText(isVisionOCRAvailable: Bool) -> String {
        switch self {
        case .visionAssist where isVisionOCRAvailable:
            return "On-device Apple Vision OCR enabled for this run."
        case .visionAssist:
            return "On-device Apple Vision OCR is unavailable in this build. Sending the image directly to the backend LLM."
        case .llmOnly:
            return "LLM Only mode selected. On-device Apple Vision OCR was skipped."
        }
    }

    static func availableModes(isVisionOCRAvailable: Bool) -> [Self] {
        isVisionOCRAvailable ? Self.allCases : [.llmOnly]
    }
}

enum AppSettingsKeys {
    static let ocrProcessingMode = "OCRProcessingMode"
}

protocol AppSettingsStoring: AnyObject {
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: AppSettingsStoring {}
