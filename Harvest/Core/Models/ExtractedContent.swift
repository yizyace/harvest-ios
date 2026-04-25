import Foundation

// What the iOS share extension extracts client-side via Defuddle and ships
// to `POST /api/v1/bookmarks` as `bookmark[client_extracted]`. When this is
// present the backend should skip its own scrape entirely; when absent
// (Defuddle gave us nothing usable, or the share didn't come from Safari),
// the backend either gets `bookmark[html]` or falls back to fetching the URL.
struct ExtractedContent: Encodable, Equatable {
    let title: String
    let content: String
    let description: String?
    let byline: String?
    let published: String?
    let wordCount: Int?
    let extractor: String

    private enum CodingKeys: String, CodingKey {
        case title, content, description, byline, published, extractor
        case wordCount = "word_count"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(description?.nilIfEmpty, forKey: .description)
        try container.encodeIfPresent(byline?.nilIfEmpty, forKey: .byline)
        try container.encodeIfPresent(published?.nilIfEmpty, forKey: .published)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
        try container.encode(extractor, forKey: .extractor)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
