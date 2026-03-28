import Foundation

enum AppFeatureFlags {
    static var visionOCREnabled: Bool {
        boolValue(forInfoPlistKey: "VisionOCREnabled")
    }

    static var defaultOCRProcessingMode: OCRProcessingMode {
        visionOCREnabled ? .visionAssist : .llmOnly
    }

    private static func boolValue(forInfoPlistKey key: String) -> Bool {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) else {
            return false
        }

        if let value = rawValue as? Bool {
            return value
        }

        if let value = rawValue as? NSNumber {
            return value.boolValue
        }

        if let value = rawValue as? String {
            return NSString(string: value).boolValue
        }

        return false
    }
}
