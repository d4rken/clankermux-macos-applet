import Foundation

/// Everything that can go wrong reaching or reading `/public/v1`.
public enum ApiError: Error, Sendable, Equatable {
    case emptyUrl
    case invalidUrl
    case http(status: Int, reason: String)
    case unsupportedSchema(label: String, found: String)
    case unexpectedResponse(label: String)
    case decoding(String)
    case connectionFailed
    case transport(String)

    /// The text shown in the panel tooltip and the popup.
    public var userMessage: String {
        switch self {
        case .emptyUrl:
            return "Server URL is empty"
        case .invalidUrl:
            return "Invalid server URL"
        case .http(let status, let reason):
            return "HTTP \(status): \(reason)"
        case .unsupportedSchema(let label, let found):
            return "Unsupported \(label) schema: \(found.isEmpty ? "missing" : found)"
        case .unexpectedResponse(let label):
            return "Unexpected \(label) response"
        case .decoding(let message):
            return message
        case .connectionFailed:
            return "Could not connect to Clankermux"
        case .transport(let message):
            return message
        }
    }
}

extension Error {
    /// The panel-facing rendering of any error a refresh can produce.
    public var clankermuxUserMessage: String {
        (self as? ApiError)?.userMessage ?? localizedDescription
    }
}

public protocol ApiClientProtocol: Sendable {
    func fetchStatus(baseURL: String, timeout: TimeInterval) async throws -> StatusResponse
    func fetchAccounts(baseURL: String, timeout: TimeInterval) async throws -> AccountsResponse
    func fetchRunway(baseURL: String, timeout: TimeInterval) async throws -> RunwayResponse
}

/// Reads the three public endpoints over `URLSession`.
///
/// The session is built from an injected configuration so tests can install a `URLProtocol` stub
/// into the very session under test.
public struct URLSessionApiClient: ApiClientProtocol {
    private let session: URLSession
    private let userAgent: String

    public init(
        configuration: URLSessionConfiguration = .ephemeral,
        requestTimeout: TimeInterval = 8,
        userAgent: String = "ClankermuxUsage/1.0.0"
    ) {
        configuration.timeoutIntervalForRequest = requestTimeout
        self.session = URLSession(configuration: configuration)
        self.userAgent = userAgent
    }

    public func fetchStatus(baseURL: String, timeout: TimeInterval) async throws -> StatusResponse {
        let response: StatusResponse = try await get(
            baseURL: baseURL, path: "/public/v1/status", timeout: timeout, label: "status")
        try validate(
            response.schema, expected: "clankermux.public.status.v1", label: "status",
            shape: response.pool != nil)
        return response
    }

    public func fetchAccounts(baseURL: String, timeout: TimeInterval) async throws
        -> AccountsResponse
    {
        let response: AccountsResponse = try await get(
            baseURL: baseURL, path: "/public/v1/accounts", timeout: timeout, label: "accounts")
        try validate(
            response.schema, expected: "clankermux.public.accounts.v1", label: "accounts",
            shape: response.accounts != nil)
        return response
    }

    public func fetchRunway(baseURL: String, timeout: TimeInterval) async throws -> RunwayResponse {
        let response: RunwayResponse = try await get(
            baseURL: baseURL, path: "/public/v1/runway", timeout: timeout, label: "runway")
        try validate(
            response.schema, expected: "clankermux.public.runway.v1", label: "runway",
            shape: response.coverage != nil)
        return response
    }

    /// A schema mismatch is a hard failure. Rendering an unrecognized payload as an empty view
    /// would look like a healthy pool with no usage.
    private func validate(
        _ schema: String?, expected: String, label: String, shape: Bool
    ) throws {
        guard schema == expected else {
            throw ApiError.unsupportedSchema(label: label, found: schema ?? "")
        }
        guard shape else { throw ApiError.unexpectedResponse(label: label) }
    }

    private func get<T: Decodable>(
        baseURL: String, path: String, timeout: TimeInterval, label: String
    ) async throws -> T {
        let base = Formatting.normalizeBaseUrl(baseURL)
        guard !base.isEmpty else { throw ApiError.emptyUrl }
        guard let url = URL(string: base + path) else { throw ApiError.invalidUrl }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.mapped(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ApiError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.httpError(http)
        }

        // Only a 2xx body reaches the decoder, so a failure here is a malformed payload rather
        // than an error page that was never meant to be JSON.
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw ApiError.unexpectedResponse(label: label)
        }
        return decoded
    }

    private static func httpError(_ response: HTTPURLResponse) -> ApiError {
        .http(
            status: response.statusCode,
            reason: HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        )
    }

    private static func mapped(_ error: URLError) -> ApiError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
            .notConnectedToInternet:
            return .connectionFailed
        case .cancelled:
            return .transport("Refresh cancelled")
        default:
            return .transport(error.localizedDescription)
        }
    }
}
