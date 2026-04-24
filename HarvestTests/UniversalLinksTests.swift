import XCTest
@testable import Harvest

final class UniversalLinksTests: XCTestCase {

    private let prodHost = "harvest.bitrat.io"
    private let devHost = "harvest.bitrat.test"

    func testExtractsTokenFromVerifyURL() {
        let url = URL(string: "https://harvest.bitrat.io/auth/verify?token=abc123")!
        XCTAssertEqual(UniversalLinks.verifyToken(from: url, expectedHost: prodHost), "abc123")
    }

    func testExtractsTokenFromDevVerifyURL() {
        let url = URL(string: "https://harvest.bitrat.test/auth/verify?token=abc123")!
        XCTAssertEqual(UniversalLinks.verifyToken(from: url, expectedHost: devHost), "abc123")
    }

    func testRejectsDevURLWhenProdHostExpected() {
        let url = URL(string: "https://harvest.bitrat.test/auth/verify?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url, expectedHost: prodHost))
    }

    func testIgnoresWrongHost() {
        let url = URL(string: "https://evil.example.com/auth/verify?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url, expectedHost: prodHost))
    }

    func testIgnoresWrongPath() {
        let url = URL(string: "https://harvest.bitrat.io/bookmarks?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url, expectedHost: prodHost))
    }

    func testIgnoresMissingToken() {
        let url = URL(string: "https://harvest.bitrat.io/auth/verify")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url, expectedHost: prodHost))
    }

    func testIgnoresEmptyToken() {
        let url = URL(string: "https://harvest.bitrat.io/auth/verify?token=")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url, expectedHost: prodHost))
    }

    func testIgnoresHTTPScheme() {
        let url = URL(string: "http://harvest.bitrat.io/auth/verify?token=abc")!
        XCTAssertNil(UniversalLinks.verifyToken(from: url, expectedHost: prodHost))
    }
}
