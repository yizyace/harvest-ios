import XCTest
@testable import Harvest

final class APIErrorEnvelopeTests: XCTestCase {

    func testMapsSimpleErrorEnvelopeOn401() {
        let data = #"{"error":"Not authenticated"}"#.data(using: .utf8)!
        let error = APIError.from(statusCode: 401, data: data)
        XCTAssertEqual(error, .unauthorized)
    }

    func testMapsValidationErrorEnvelopeOn422() {
        let data = #"""
        {"errors":[{"field":"url","message":"has already been taken"}]}
        """#.data(using: .utf8)!
        let error = APIError.from(statusCode: 422, data: data)
        XCTAssertEqual(
            error,
            .validation([FieldError(field: "url", message: "has already been taken")])
        )
    }

    func testMaps422WithPlainErrorKeyToSimpleError() {
        // handoff §5 shows `{"error":"Invalid email address"}` on 422 for
        // /auth/magic_link. Our parser falls through to `.simple`.
        let data = #"{"error":"Invalid email address"}"#.data(using: .utf8)!
        let error = APIError.from(statusCode: 422, data: data)
        XCTAssertEqual(error, .simple("Invalid email address"))
    }

    func testMaps404ToNotFoundWithMessage() {
        let data = #"{"error":"Not found"}"#.data(using: .utf8)!
        let error = APIError.from(statusCode: 404, data: data)
        XCTAssertEqual(error, .notFound("Not found"))
    }

    func testFallsThroughToUnexpectedStatusOnUnknownBody() {
        let data = #"this is not json"#.data(using: .utf8)!
        let error = APIError.from(statusCode: 500, data: data)
        XCTAssertEqual(error, .unexpectedStatus(code: 500, body: "this is not json"))
    }

    func testValidationTakesPrecedenceOverError() {
        let data = #"""
        {"errors":[{"field":"url","message":"bad"}],"error":"also bad"}
        """#.data(using: .utf8)!
        let error = APIError.from(statusCode: 422, data: data)
        XCTAssertEqual(
            error,
            .validation([FieldError(field: "url", message: "bad")])
        )
    }
}
