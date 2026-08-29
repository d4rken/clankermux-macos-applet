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

    @Test("decodes the status payload")
    func decodesStatus() async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/status", body: Fixtures.statusJSON)

        let response = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(response.schema == "clankermux.public.status.v1")
        #expect(response.generatedAt.instant == Fixtures.now)
        #expect(response.pool?.configured == 3)
        #expect(response.pool?.configuredPresence == .present)
        #expect(response.usage?.fiveHour?.meanUtilizationPct == 37.5)
        #expect(response.providers?.count == 2)
        #expect(response.providers?[0].scopedLimits?[0].label == "Fable")
    }

    @Test("decodes the accounts payload, keeping an unreadable window unreadable")
    func decodesAccounts() async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/accounts", body: Fixtures.accountsJSON)

        let response = try await client.fetchAccounts(baseURL: baseURL, timeout: 5)
        #expect(response.accounts?.count == 2)
        #expect(response.accounts?[0].windows?.count == 3)
        #expect(response.accounts?[0].windows?[0].prediction?.predictedUtilizationAtResetPct == 95)
        #expect(response.accounts?[1].windows?[0].utilizationPct == nil)
        #expect(response.accounts?[1].windows?[0].resetsAt.instant == nil)
    }

    @Test("decodes the runway payload")
    func decodesRunway() async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/runway", body: Fixtures.runwayJSON)

        let response = try await client.fetchRunway(baseURL: baseURL, timeout: 5)
        #expect(response.coverage?.activeKeyCount == 2)
        #expect(response.horizonMs == 1_209_600_000)
        #expect(response.worstStatedOutcome?.kind == "runway")
        #expect(response.worstStatedOutcome?.causes?.first?.accountId == "account-c")
    }

    /// Every timestamp the server emits carries milliseconds, which a default
    /// `ISO8601DateFormatter` rejects outright.
    @Test("fractional-second timestamps parse")
    func fractionalSecondTimestamps() async throws {
        let client = makeClient()
        StubURLProtocol.set(path: "/public/v1/status", body: Fixtures.statusJSON)

        let response = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(
            response.pool?.nextAvailableAt.instant == Fixtures.date("2026-08-24T12:30:00.000Z"))
    }

    @Test("timestamps sent as JSON numbers or numeric strings parse as epoch milliseconds")
    func numericTimestamps() async throws {
        let client = makeClient()
        let epoch = Fixtures.now.timeIntervalSince1970 * 1000
        StubURLProtocol.set(
            path: "/public/v1/status",
            body: """
                {
                  "schema": "clankermux.public.status.v1",
                  "generatedAt": \(Int(epoch)),
                  "status": "ok",
                  "pool": { "configured": 1, "defaultRoutable": 1,
                            "nextAvailableAt": "\(Int(epoch))" }
                }
                """
        )

        let response = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(response.generatedAt.instant == Fixtures.now)
        #expect(response.pool?.nextAvailableAt.instant == Fixtures.now)
    }

    @Test("a non-ISO, non-numeric timestamp reads as unknown rather than failing the payload")
    func unreadableTimestamp() async throws {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/status",
            body: """
                {
                  "schema": "clankermux.public.status.v1",
                  "generatedAt": "not-a-date",
                  "pool": { "configured": 1 }
                }
                """
        )
        let response = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(response.generatedAt.instant == nil)
    }

    @Test("a missing pool.configured and an explicit null both fall back to the derived count")
    func poolConfiguredPresence() async throws {
        let client = makeClient()
        StubURLProtocol.set(
            path: "/public/v1/status",
            body: """
                {"schema": "clankermux.public.status.v1", "pool": {"paused": 0}}
                """
        )
        let missing = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(missing.pool?.configuredPresence == .missing)
        #expect(missing.pool?.configured == nil)

        StubURLProtocol.set(
            path: "/public/v1/status",
            body: """
                {"schema": "clankermux.public.status.v1",
                 "pool": {"configured": null, "defaultRoutable": null}}
                """
        )
        let explicitNull = try await client.fetchStatus(baseURL: baseURL, timeout: 5)
        #expect(explicitNull.pool?.configuredPresence == .explicitNull)
        #expect(explicitNull.pool?.configured == nil)
        #expect(explicitNull.pool?.defaultRoutablePresence == .explicitNull)

        for status in [missing, explicitNull] {
            let view = UsageModel.buildView(
                accounts: Fixtures.accounts(), status: status, runway: nil,
                options: ViewOptions(), localNow: Fixtures.now)
            #expect(view.pool.configured == 3)
            #expect(view.pool.defaultRoutable == 2)
        }
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
        await #expect(throws: ApiError.unsupportedSchema(
            label: "status", found: "clankermux.public.status.v2")) {
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
            path: "/public/v1/runway", body: "{\"schema\": \"clankermux.public.runway.v1\"}")
        await #expect(throws: ApiError.unexpectedResponse(label: "runway")) {
            _ = try await client.fetchRunway(baseURL: baseURL, timeout: 5)
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
