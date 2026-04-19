import XCTest
@testable import Harvest

final class ISO8601Tests: XCTestCase {

    private let decoder = ISO8601JSON.makeDecoder()

    func testDecodesPlainISO8601ZuluTime() throws {
        let json = #"{ "when": "2026-04-17T12:00:00Z" }"#.data(using: .utf8)!
        struct Envelope: Decodable { let when: Date }
        let envelope = try decoder.decode(Envelope.self, from: json)

        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: envelope.when
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.hour, 12)
    }

    func testDecodesFractionalSecondsVariant() throws {
        let json = #"{ "when": "2026-04-17T12:00:00.123Z" }"#.data(using: .utf8)!
        struct Envelope: Decodable { let when: Date }
        XCTAssertNoThrow(try decoder.decode(Envelope.self, from: json))
    }

    func testRejectsMalformedDate() {
        let json = #"{ "when": "not a date" }"#.data(using: .utf8)!
        struct Envelope: Decodable { let when: Date }
        XCTAssertThrowsError(try decoder.decode(Envelope.self, from: json))
    }
}
