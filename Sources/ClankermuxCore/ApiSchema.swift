import Foundation

// MARK: - Timestamps

/// A `/public/v1` timestamp, which the server may send as an ISO-8601 string, a numeric string, or
/// a JSON number of epoch milliseconds.
///
///     1_787_000_000_000          -> Date
///     "1787000000000"            -> Date
///     "2026-08-24T12:00:00.000Z" -> Date
///     "not-a-date"               -> nil
public struct FlexibleTimestamp: Codable, Sendable, Equatable {
    /// The resolved instant, or nil when the value could not be read as one.
    public let date: Date?

    public init(date: Date?) {
        self.date = date
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            date = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            date = Self.fromEpochMilliseconds(number)
            return
        }
        let text = try container.decode(String.self)
        date = Self.parse(text)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let date else {
            try container.encodeNil()
            return
        }
        try container.encode(Self.iso(fractionalSeconds: true).string(from: date))
    }

    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = Double(trimmed), number.isFinite {
            return fromEpochMilliseconds(number)
        }
        if let parsed = iso(fractionalSeconds: true).date(from: trimmed) { return parsed }
        return iso(fractionalSeconds: false).date(from: trimmed)
    }

    private static func fromEpochMilliseconds(_ value: Double) -> Date? {
        guard value.isFinite else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }

    // Every timestamp the server emits carries milliseconds ("2026-08-24T12:00:00.000Z"), which a
    // default-configured ISO8601DateFormatter rejects.
    private static func iso(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =
            fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

extension Optional where Wrapped == FlexibleTimestamp {
    /// The resolved instant, collapsing "field absent", "field null" and "field unreadable".
    public var instant: Date? { self?.date }
}

// MARK: - Field presence

/// Whether a JSON field was absent, explicitly null, or carried a value.
public enum FieldPresence: String, Sendable, Equatable {
    case missing
    case explicitNull
    case present
}

// MARK: - Shared aggregates

/// A server-computed mean across the accounts that supplied one quota window.
///
/// Backs `usage.fiveHour`, `usage.sevenDay` and each entry of `providers[].scopedLimits`.
public struct UsageAggregate: Codable, Sendable, Equatable {
    public let scopeId: String?
    public let label: String?
    public let meanUtilizationPct: Double?
    public let contributingAccountCount: Double?
    public let unknownAccountCount: Double?
    public let earliestResetsAt: FlexibleTimestamp?

    public init(
        scopeId: String? = nil,
        label: String? = nil,
        meanUtilizationPct: Double? = nil,
        contributingAccountCount: Double? = nil,
        unknownAccountCount: Double? = nil,
        earliestResetsAt: FlexibleTimestamp? = nil
    ) {
        self.scopeId = scopeId
        self.label = label
        self.meanUtilizationPct = meanUtilizationPct
        self.contributingAccountCount = contributingAccountCount
        self.unknownAccountCount = unknownAccountCount
        self.earliestResetsAt = earliestResetsAt
    }
}

// MARK: - /public/v1/status

public struct StatusResponse: Codable, Sendable, Equatable {
    public let schema: String?
    public let generatedAt: FlexibleTimestamp?
    public let status: String?
    public let pool: PoolInfo?
    public let usage: UsageSection?
    public let providers: [ProviderStatus]?

    public init(
        schema: String? = nil,
        generatedAt: FlexibleTimestamp? = nil,
        status: String? = nil,
        pool: PoolInfo? = nil,
        usage: UsageSection? = nil,
        providers: [ProviderStatus]? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.status = status
        self.pool = pool
        self.usage = usage
        self.providers = providers
    }
}

public struct UsageSection: Codable, Sendable, Equatable {
    public let fiveHour: UsageAggregate?
    public let sevenDay: UsageAggregate?

    public init(fiveHour: UsageAggregate? = nil, sevenDay: UsageAggregate? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// Routing-pool counters.
///
/// `configured` and `defaultRoutable` keep their wire presence so an explicit null stays
/// distinguishable from an absent field; both resolve to nil and fall back to the derived account
/// count.
public struct PoolInfo: Codable, Sendable, Equatable {
    public let configured: Double?
    public let configuredPresence: FieldPresence
    public let defaultRoutable: Double?
    public let defaultRoutablePresence: FieldPresence
    public let paused: Double?
    public let rateLimited: Double?
    public let usageExhausted: Double?
    public let nextAvailableAt: FlexibleTimestamp?

    private enum CodingKeys: String, CodingKey {
        case configured
        case defaultRoutable
        case paused
        case rateLimited
        case usageExhausted
        case nextAvailableAt
    }

    public init(
        configured: Double? = nil,
        configuredPresence: FieldPresence = .missing,
        defaultRoutable: Double? = nil,
        defaultRoutablePresence: FieldPresence = .missing,
        paused: Double? = nil,
        rateLimited: Double? = nil,
        usageExhausted: Double? = nil,
        nextAvailableAt: FlexibleTimestamp? = nil
    ) {
        self.configured = configured
        self.configuredPresence = configuredPresence
        self.defaultRoutable = defaultRoutable
        self.defaultRoutablePresence = defaultRoutablePresence
        self.paused = paused
        self.rateLimited = rateLimited
        self.usageExhausted = usageExhausted
        self.nextAvailableAt = nextAvailableAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        (configured, configuredPresence) = try Self.count(container, .configured)
        (defaultRoutable, defaultRoutablePresence) = try Self.count(container, .defaultRoutable)
        paused = try container.decodeIfPresent(Double.self, forKey: .paused)
        rateLimited = try container.decodeIfPresent(Double.self, forKey: .rateLimited)
        usageExhausted = try container.decodeIfPresent(Double.self, forKey: .usageExhausted)
        nextAvailableAt = try container.decodeIfPresent(
            FlexibleTimestamp.self, forKey: .nextAvailableAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch configuredPresence {
        case .missing: break
        case .explicitNull: try container.encodeNil(forKey: .configured)
        case .present: try container.encode(configured, forKey: .configured)
        }
        switch defaultRoutablePresence {
        case .missing: break
        case .explicitNull: try container.encodeNil(forKey: .defaultRoutable)
        case .present: try container.encode(defaultRoutable, forKey: .defaultRoutable)
        }
        try container.encodeIfPresent(paused, forKey: .paused)
        try container.encodeIfPresent(rateLimited, forKey: .rateLimited)
        try container.encodeIfPresent(usageExhausted, forKey: .usageExhausted)
        try container.encodeIfPresent(nextAvailableAt, forKey: .nextAvailableAt)
    }

    private static func count(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> (Double?, FieldPresence) {
        guard container.contains(key) else { return (nil, .missing) }
        if try container.decodeNil(forKey: key) { return (nil, .explicitNull) }
        return (try container.decode(Double.self, forKey: key), .present)
    }
}

public struct ProviderStatus: Codable, Sendable, Equatable {
    public let provider: String?
    public let anyOverload: BreakerState?
    public let providerWideOverload: BreakerState?
    public let scopedLimits: [UsageAggregate]?

    public init(
        provider: String? = nil,
        anyOverload: BreakerState? = nil,
        providerWideOverload: BreakerState? = nil,
        scopedLimits: [UsageAggregate]? = nil
    ) {
        self.provider = provider
        self.anyOverload = anyOverload
        self.providerWideOverload = providerWideOverload
        self.scopedLimits = scopedLimits
    }
}

public struct BreakerState: Codable, Sendable, Equatable {
    public let state: String?
    public let until: FlexibleTimestamp?
    public let probeActive: Bool?

    public init(state: String? = nil, until: FlexibleTimestamp? = nil, probeActive: Bool? = nil) {
        self.state = state
        self.until = until
        self.probeActive = probeActive
    }
}

// MARK: - /public/v1/accounts

public struct AccountsResponse: Codable, Sendable, Equatable {
    public let schema: String?
    public let accounts: [Account]?

    public init(schema: String? = nil, accounts: [Account]? = nil) {
        self.schema = schema
        self.accounts = accounts
    }
}

public struct Account: Codable, Sendable, Equatable {
    public let id: String?
    public let name: String?
    public let provider: String?
    public let isDefaultCandidate: Bool?
    public let availability: Availability?
    public let credential: Credential?
    public let measurementState: String?
    public let windows: [UsageWindow]?

    public init(
        id: String? = nil,
        name: String? = nil,
        provider: String? = nil,
        isDefaultCandidate: Bool? = nil,
        availability: Availability? = nil,
        credential: Credential? = nil,
        measurementState: String? = nil,
        windows: [UsageWindow]? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.isDefaultCandidate = isDefaultCandidate
        self.availability = availability
        self.credential = credential
        self.measurementState = measurementState
        self.windows = windows
    }
}

public struct Availability: Codable, Sendable, Equatable {
    public let state: String?
    public let reason: String?
    public let availableAt: FlexibleTimestamp?

    public init(state: String? = nil, reason: String? = nil, availableAt: FlexibleTimestamp? = nil)
    {
        self.state = state
        self.reason = reason
        self.availableAt = availableAt
    }
}

public struct Credential: Codable, Sendable, Equatable {
    public let state: String?
    public let expiresAt: FlexibleTimestamp?

    public init(state: String? = nil, expiresAt: FlexibleTimestamp? = nil) {
        self.state = state
        self.expiresAt = expiresAt
    }
}

public struct UsageWindow: Codable, Sendable, Equatable {
    public let kind: String?
    public let scopeId: String?
    public let label: String?
    public let utilizationPct: Double?
    public let observedAt: FlexibleTimestamp?
    public let resetsAt: FlexibleTimestamp?
    public let prediction: Prediction?

    public init(
        kind: String? = nil,
        scopeId: String? = nil,
        label: String? = nil,
        utilizationPct: Double? = nil,
        observedAt: FlexibleTimestamp? = nil,
        resetsAt: FlexibleTimestamp? = nil,
        prediction: Prediction? = nil
    ) {
        self.kind = kind
        self.scopeId = scopeId
        self.label = label
        self.utilizationPct = utilizationPct
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.prediction = prediction
    }
}

public struct Prediction: Codable, Sendable, Equatable {
    public let predictedUtilizationAtResetPct: Double?
    public let exhaustsAt: FlexibleTimestamp?
    public let willExhaustBeforeReset: Bool?
    public let lowConfidence: Bool?
    public let state: String?

    public init(
        predictedUtilizationAtResetPct: Double? = nil,
        exhaustsAt: FlexibleTimestamp? = nil,
        willExhaustBeforeReset: Bool? = nil,
        lowConfidence: Bool? = nil,
        state: String? = nil
    ) {
        self.predictedUtilizationAtResetPct = predictedUtilizationAtResetPct
        self.exhaustsAt = exhaustsAt
        self.willExhaustBeforeReset = willExhaustBeforeReset
        self.lowConfidence = lowConfidence
        self.state = state
    }
}

// MARK: - /public/v1/runway

public struct RunwayResponse: Codable, Sendable, Equatable {
    public let schema: String?
    public let generatedAt: FlexibleTimestamp?
    public let horizonMs: Double?
    public let coverage: Coverage?
    public let worstStatedOutcome: StatedOutcome?

    public init(
        schema: String? = nil,
        generatedAt: FlexibleTimestamp? = nil,
        horizonMs: Double? = nil,
        coverage: Coverage? = nil,
        worstStatedOutcome: StatedOutcome? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.horizonMs = horizonMs
        self.coverage = coverage
        self.worstStatedOutcome = worstStatedOutcome
    }
}

public struct Coverage: Codable, Sendable, Equatable {
    public let activeKeyCount: Double?
    public let statedKeyCount: Double?
    public let unobservedKeyCount: Double?

    public init(
        activeKeyCount: Double? = nil,
        statedKeyCount: Double? = nil,
        unobservedKeyCount: Double? = nil
    ) {
        self.activeKeyCount = activeKeyCount
        self.statedKeyCount = statedKeyCount
        self.unobservedKeyCount = unobservedKeyCount
    }
}

public struct StatedOutcome: Codable, Sendable, Equatable {
    public let kind: String?
    public let exhaustsAt: FlexibleTimestamp?
    public let causes: [OutcomeCause]?

    public init(
        kind: String? = nil,
        exhaustsAt: FlexibleTimestamp? = nil,
        causes: [OutcomeCause]? = nil
    ) {
        self.kind = kind
        self.exhaustsAt = exhaustsAt
        self.causes = causes
    }
}

public struct OutcomeCause: Codable, Sendable, Equatable {
    public let accountId: String?
    public let windowKind: String?

    public init(accountId: String? = nil, windowKind: String? = nil) {
        self.accountId = accountId
        self.windowKind = windowKind
    }
}
