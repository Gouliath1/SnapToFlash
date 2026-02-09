import Foundation

/// Mirrors the backend anki_note payload (snake_case decoded via convertFromSnakeCase).
struct RawNote: Codable {
    var id: String?
    var front: String
    var back: String?
    var hiragana: String?
    var kanji: String?
    var source: String?
    var bookMatch: String?
    var handTranslation: String?
    var aiTranslation: String?
    var needsReview: Bool
    var confOcr: Double?
    var confMatch: Double?
    var notes: String?
}
