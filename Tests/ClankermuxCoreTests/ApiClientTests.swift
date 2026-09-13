import Foundation
import Testing

@testable import ClankermuxCore

/// Answers requests from a table keyed by path, so the client under test exercises its real
/// `URLSession` path without a server.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data
    }

    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    private static let lock = NSLock()

    static func set(path: String, statusCode: Int = 200, body: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs[path] = Stub(statusCode: statusCode, body: Data(body.utf8))
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
    }

    private static func stub(for path: String) -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        return stubs[path]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stub(for: url.path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("API client", .serialized)
struct ApiClientTests {
    private let baseURL = "http://clankermux.test:8080"

    private func makeClient() -> URLSessionApiClient {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionApiClient(configuration: configuration, requestTimeout: 5)
    }

    @Test("decodes the proxy's published status and account examples")
    func publishedExamples() async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/status", body: try example("status"))
        StubURLProtocol.set(path: "/public/v1/accounts", body: try example("accounts"))
        let status = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(status.serviceState == "ready")
        #expect(status.accounts?.configured == 1)
        #expect(status.version == "2026.9.example")
        let accounts = try await client.fetchAccounts(baseURL: baseURL, timeout: 5)
        #expect(accounts.accounts?.first?.windows?.first?.forecast?.outcome == "lasts_until_reset")
        #expect(
            accounts.accounts?.first?.windows?.first?.resetsAt.instant
                == Fixtures.date("2026-09-09T15:00:00.000Z"))
    }

    @Test(
        "decodes all published workload variants",
        arguments: [
            "workloads", "workloads.partial", "workloads.family", "workloads.increase-limit",
            "workloads.reduction-limit",
        ])
    func workloadExamples(name: String) async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/workloads", body: try example(name))
        let payload = try await client.fetchWorkloads(baseURL: baseURL, timeout: 5)
        #expect(payload.schema == "clankermux.public.workloads.v1")
        #expect(payload.workloads?.isEmpty == false)
        #expect(payload.workloads?.first?.weekly?.computedAt.instant != nil)
        let view = UsageModel.buildView(
            accounts: [], workloads: payload, localNow: Fixtures.date("2026-09-09T12:00:10.000Z"))
        #expect(!view.workloads.isEmpty)
        if name == "workloads.partial" {
            #expect(view.workloads.allSatisfy { !$0.signal.numeric })
        }
        if name == "workloads.reduction-limit" {
            #expect(view.workloads.contains { $0.signal.value.contains("insufficient") })
        }
        if name == "workloads.increase-limit" {
            #expect(view.workloads.contains { $0.signal.value.contains("≥") })
        }
    }

    @Test("timestamps accept ISO, numeric strings, numbers and unreadable values")
    func timestamps() throws {
        for json in ["1787000000000", "\"1787000000000\""] {
            let value = try JSONDecoder().decode(FlexibleTimestamp.self, from: Data(json.utf8))
            #expect(value.date == Date(timeIntervalSince1970: 1_787_000_000))
        }
        for json in ["\"not-a-date\"", "null"] {
            let value = try JSONDecoder().decode(FlexibleTimestamp.self, from: Data(json.utf8))
            #expect(value.date == nil)
        }
    }

    @Test("the retired status shape is rejected even though its schema ID is unchanged")
    func retiredStatus() async {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/status",
            body:
                #"{"schema":"clankermux.public.status.v1","pool":{"configured":3},"status":"ok"}"#)
        await #expect(throws: ApiError.unexpectedResponse(label: "status")) {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        }
    }

    private func example(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Examples"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("a wrong schema is rejected rather than rendered as an empty view")
    func rejectsWrongSchema() async throws {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/status",
            body: """
                {"schema": "clankermux.public.status.v2", "pool": {"configured": 1}}
                """
        )
        await #expect(
            throws: ApiError.unsupportedSchema(
                label: "status", found: "clankermux.public.status.v2")
        ) {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        }

        StubURLProtocol.set(path: "/public/v1/status", body: "{\"pool\": {\"configured\": 1}}")
        do {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
            Issue.record("expected a schema rejection")
        } catch let error as ApiError {
            #expect(error.userMessage == "Unsupported status schema: missing")
        }
    }

    @Test("a payload of the right schema but the wrong shape is rejected")
    func rejectsWrongShape() async throws {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/accounts",
            body: "{\"schema\": \"clankermux.public.accounts.v1\", \"accounts\": null}")
        await #expect(throws: ApiError.unexpectedResponse(label: "accounts")) {
            _ = try await client.fetchAccounts(baseURL: baseURL, timeout: 5)
        }

        StubURLProtocol.set(
            path: "/public/v1/workloads", body: "{\"schema\": \"clankermux.public.workloads.v1\"}")
        await #expect(throws: ApiError.unexpectedResponse(label: "workloads")) {
            _ = try await client.fetchWorkloads(baseURL: baseURL, timeout: 5)
        }
    }

    @Test("an HTTP error carries its status and reason")
    func httpError() async throws {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/status", statusCode: 500, body: Fixtures.statusJSON)
        do {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
            Issue.record("expected an HTTP failure")
        } catch let error as ApiError {
            #expect(error.userMessage.hasPrefix("HTTP 500: "))
        }
    }

    @Test("a non-2xx response reports its status even when the body is not JSON")
    func httpErrorWithNonJSONBody() async throws {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/status", statusCode: 500,
            body: "<html><body><h1>500 Internal Server Error</h1></body></html>")
        do {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
            Issue.record("expected an HTTP failure")
        } catch let error as ApiError {
            guard case .http(let status, _) = error else {
                Issue.record("expected an HTTP error, got \(error)")
                return
            }
            #expect(status == 500)
            #expect(error.userMessage.hasPrefix("HTTP 500: "))
        }
    }

    @Test("a body that is not JSON is reported as an unexpected response")
    func malformedJSON() async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/status", body: "<html>nope</html>")
        await #expect(throws: ApiError.unexpectedResponse(label: "status")) {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        }
    }

    @Test("an empty server URL fails before any request is attempted")
    func emptyURL() async throws {
        let client = makeClient()
        await #expect(throws: ApiError.emptyUrl) {
            _ = try await client.fetchStatus(baseURL: "   ", timeout: 5)
        }
        #expect(ApiError.emptyUrl.userMessage == "Server URL is empty")
    }

    @Test("a connection failure reads as a connection failure, not as a URL error dump")
    func connectionFailureMessage() async throws {
        let client = makeClient()
        do {
            _ = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
            Issue.record("expected a connection failure")
        } catch let error as ApiError {
            #expect(error.userMessage == "Could not connect to Clankermux")
        }
    }
}
