import Foundation

// Two server envelope shapes per handoff §5. The client's job is to detect
// both and convert to a typed error the UI can match on.
enum APIError: Error, Equatable {
    case unauthorized                              // 401
    case notFound(String?)                         // 404 — optional server-provided message
    case invalidCursor                             // 400 {"error": "Invalid cursor"} — stale or malformed
    case validation([FieldError])                  // 422 — {"errors": [{field, message}]}
    case simple(String)                            // {"error": "..."} envelope
    case transport(URLError)                       // underlying network failure
    case decoding(String)                          // JSON decode or response-shape failure
    case unexpectedStatus(code: Int, body: String?) // catch-all for unhandled statuses
}

struct FieldError: Codable, Equatable, Sendable {
    let field: String
    let message: String
}

// Wire envelope shapes. `errors` (array) takes precedence over `error` when
// both are present; in practice the server returns exactly one.
struct ErrorEnvelope: Codable {
    let error: String?
    let errors: [FieldError]?
}

extension APIError {
    /// Map an HTTP status + body to a typed `APIError`. Falls through to
    /// `unexpectedStatus` when the body doesn't match either envelope.
    static func from(statusCode: Int, data: Data) -> APIError {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let body = String(data: data, encoding: .utf8)

        switch statusCode {
        case 400:
            if envelope?.error == "Invalid cursor" {
                return .invalidCursor
            }
            if let message = envelope?.error {
                return .simple(message)
            }
            return .unexpectedStatus(code: 400, body: body)
        case 401:
            return .unauthorized
        case 404:
            return .notFound(envelope?.error)
        case 422:
            if let errors = envelope?.errors, !errors.isEmpty {
                return .validation(errors)
            }
            if let message = envelope?.error {
                return .simple(message)
            }
            return .unexpectedStatus(code: 422, body: body)
        default:
            if let message = envelope?.error {
                return .simple(message)
            }
            return .unexpectedStatus(code: statusCode, body: body)
        }
    }
}

// MARK: - User-facing message

extension APIError {
    var userFacingMessage: String {
        switch self {
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .notFound(let message):
            return message ?? "Not found."
        case .invalidCursor:
            return "Refreshing…"
        case .validation(let errors):
            return errors.first.map { "\($0.field): \($0.message)" } ?? "Validation failed."
        case .simple(let message):
            return message
        case .transport:
            return "Can't reach Harvest. Check your connection and try again."
        case .decoding:
            return "The server returned an unexpected response."
        case .unexpectedStatus(let code, _):
            return "Server error (HTTP \(code))."
        }
    }
}
