import Foundation

// What the iOS share extension extracts client-side via Defuddle and ships
// to `POST /api/v1/bookmarks` as `bookmark[extracted]`. When this is present
// the backend should skip its own scrape entirely; when absent (Defuddle
// gave us nothing usable, or the share didn't come from Safari), the
// backend either gets `bookmark[html]` or falls back to fetching the URL.
struct ExtractedContent: Encodable, Equatable {
    let title: String
    let content: String
    let author: String?
    let description: String?
    let published: String?
    let image: String?
    let domain: String?
    let site: String?
    let language: String?
    let wordCount: Int?

    private enum CodingKeys: String, CodingKey {
        case title, content, author, description, published, image, domain, site, language
        case wordCount = "word_count"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(author?.nilIfEmpty, forKey: .author)
        try container.encodeIfPresent(description?.nilIfEmpty, forKey: .description)
        try container.encodeIfPresent(published?.nilIfEmpty, forKey: .published)
        try container.encodeIfPresent(image?.nilIfEmpty, forKey: .image)
        try container.encodeIfPresent(domain?.nilIfEmpty, forKey: .domain)
        try container.encodeIfPresent(site?.nilIfEmpty, forKey: .site)
        try container.encodeIfPresent(language?.nilIfEmpty, forKey: .language)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
