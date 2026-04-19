import XCTest
@testable import Harvest

final class UniversalLinksTests: XCTestCase {

    func testExtractsTokenFromVerifyURL() {
        let url = URL(string: "https://harvest.bitrat.io/auth/verify?token=abc123")!
        XCTAssertEqual(UniversalLinks.verifyToken(from: url), "abc123")
    }

    func testIgnoresWrongHost() {
        let url = URL(string: "https://evil.example.com/auth/verify?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url))
    }

    func testIgnoresWrongPath() {
        let url = URL(string: "https://harvest.bitrat.io/bookmarks?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url))
    }

    func testIgnoresMissingToken() {
        let url = URL(string: "https://harvest.bitrat.io/auth/verify")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url))
    }

    func testIgnoresEmptyToken() {
        let url = URL(string: "https://harvest.bitrat.io/auth/verify?token=")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url))
    }

    func testIgnoresHTTPScheme() {
        let url = URL(string: "http://harvest.bitrat.io/auth/verify?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url))
    }
}
