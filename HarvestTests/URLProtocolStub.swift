import Foundation

// Intercepts URL requests issued through a stubbed `URLSession`. Tests enqueue
// responses per URL; the protocol pops one per matching request. Use the
// `session()` helper to build a URLSession that exclusively uses this stub.
final class URLProtocolStub: URLProtocol {

    struct Stub {
        let statusCode: Int
        let body: Data
        let headers: [String: String]
        init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }
    }

    struct RecordedRequest {
        let url: URL
        let method: String?
        let headers: [String: String]
        let body: Data?
    }

    // Tests read + write `responses` / `recorded` via the helper APIs below.
    nonisolated(unsafe) private static var responses: [String: [Stub]] = [:]
    nonisolated(unsafe) private static var recorded: [RecordedRequest] = []
    private static let lock = NSLock()

    static func enqueue(_ stub: Stub, for url: URL) {
        lock.withLock {
            let key = canonicalize(url)
            responses[key, default: []].append(stub)
        }
    }

    static func reset() {
        lock.withLock {
            responses.removeAll()
            recorded.removeAll()
        }
    }

    static var allRecorded: [RecordedRequest] {
        lock.withLock { recorded }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func canonicalize(_ url: URL) -> String {
        // Canonicalize by path + (sorted) query so tests can enqueue without
        // caring about query-item ordering.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.sorted { $0.name < $1.name }
        return components.url?.absoluteString ?? url.absoluteString
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolStub.lock.lock()
        let key = URLProtocolStub.canonicalize(request.url!)
        let stub = URLProtocolStub.responses[key]?.first
        if stub != nil {
            URLProtocolStub.responses[key]?.removeFirst()
        }
        URLProtocolStub.recorded.append(
            RecordedRequest(
                url: request.url!,
                method: request.httpMethod,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBodyStreamAsData() ?? request.httpBody
            )
        )
        URLProtocolStub.lock.unlock()

        guard let stub else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "URLProtocolStub",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No stub for \(key)"]
                )
            )
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    // Test fixtures can send bodies either as `httpBody` or `httpBodyStream`
    // depending on URLSession's internals. Read either.
    func httpBodyStreamAsData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
