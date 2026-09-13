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

public struct StatusResponse: Codable, Sendable, Equatable {
    public var schema: String?
    public var generatedAt: FlexibleTimestamp?
    public var serviceState: String?
    public var version: String?
    public var uptimeS: Double?
    public var accounts: AccountTotals?

    public init(
        schema: String? = nil,
        generatedAt: FlexibleTimestamp? = nil,
        serviceState: String? = nil,
        version: String? = nil,
        uptimeS: Double? = nil,
        accounts: AccountTotals? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.serviceState = serviceState
        self.version = version
        self.uptimeS = uptimeS
        self.accounts = accounts
    }
}

public struct AccountTotals: Codable, Sendable, Equatable {
    public var configured: Double?
    public var paused: Double?

    public init(
        configured: Double? = nil,
        paused: Double? = nil
    ) {
        self.configured = configured
        self.paused = paused
    }
}

public struct AccountsResponse: Codable, Sendable, Equatable {
    public var schema: String?
    public var generatedAt: FlexibleTimestamp?
    public var accounts: [Account]?

    public init(
        schema: String? = nil,
        generatedAt: FlexibleTimestamp? = nil,
        accounts: [Account]? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.accounts = accounts
    }
}

public struct Account: Codable, Sendable, Equatable {
    public var id: String?
    public var name: String?
    public var provider: String?
    public var availability: Availability?
    public var credential: Credential?
    public var measurementState: String?
    public var usageObservedAt: FlexibleTimestamp?
    public var windows: [UsageWindow]?

    public init(
        id: String? = nil,
        name: String? = nil,
        provider: String? = nil,
        availability: Availability? = nil,
        credential: Credential? = nil,
        measurementState: String? = nil,
        usageObservedAt: FlexibleTimestamp? = nil,
        windows: [UsageWindow]? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.availability = availability
        self.credential = credential
        self.measurementState = measurementState
        self.usageObservedAt = usageObservedAt
        self.windows = windows
    }
}

public struct Availability: Codable, Sendable, Equatable {
    public var state: String?
    public var reason: String?
    public var availableAt: FlexibleTimestamp?

    public init(
        state: String? = nil,
        reason: String? = nil,
        availableAt: FlexibleTimestamp? = nil
    ) {
        self.state = state
        self.reason = reason
        self.availableAt = availableAt
    }
}

public struct Credential: Codable, Sendable, Equatable {
    public var state: String?
    public var expiresAt: FlexibleTimestamp?

    public init(
        state: String? = nil,
        expiresAt: FlexibleTimestamp? = nil
    ) {
        self.state = state
        self.expiresAt = expiresAt
    }
}

public struct UsageWindow: Codable, Sendable, Equatable {
    public var kind: String?
    public var scopeId: String?
    public var label: String?
    public var utilizationPct: Double?
    public var observedAt: FlexibleTimestamp?
    public var resetsAt: FlexibleTimestamp?
    public var forecast: WindowForecast?

    public init(
        kind: String? = nil,
        scopeId: String? = nil,
        label: String? = nil,
        utilizationPct: Double? = nil,
        observedAt: FlexibleTimestamp? = nil,
        resetsAt: FlexibleTimestamp? = nil,
        forecast: WindowForecast? = nil
    ) {
        self.kind = kind
        self.scopeId = scopeId
        self.label = label
        self.utilizationPct = utilizationPct
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.forecast = forecast
    }
}

public struct WindowForecast: Codable, Sendable, Equatable {
    public var outcome: String?
    public var quality: String?
    public var reason: String?
    public var exhaustsAt: FlexibleTimestamp?
    public var reassessAt: FlexibleTimestamp?

    public init(
        outcome: String? = nil,
        quality: String? = nil,
        reason: String? = nil,
        exhaustsAt: FlexibleTimestamp? = nil,
        reassessAt: FlexibleTimestamp? = nil
    ) {
        self.outcome = outcome
        self.quality = quality
        self.reason = reason
        self.exhaustsAt = exhaustsAt
        self.reassessAt = reassessAt
    }
}

public struct WorkloadsResponse: Codable, Sendable, Equatable {
    public var schema: String?
    public var generatedAt: FlexibleTimestamp?
    public var workloads: [Workload]?

    public init(
        schema: String? = nil,
        generatedAt: FlexibleTimestamp? = nil,
        workloads: [Workload]? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.workloads = workloads
    }
}

public struct Workload: Codable, Sendable, Equatable {
    public var id: String?
    public var label: String?
    public var parentWorkloadId: String?
    public var availability: WorkloadAvailability?
    public var weekly: WeeklyBudget?

    public init(
        id: String? = nil,
        label: String? = nil,
        parentWorkloadId: String? = nil,
        availability: WorkloadAvailability? = nil,
        weekly: WeeklyBudget? = nil
    ) {
        self.id = id
        self.label = label
        self.parentWorkloadId = parentWorkloadId
        self.availability = availability
        self.weekly = weekly
    }
}

public struct WorkloadAvailability: Codable, Sendable, Equatable {
    public var computedAt: FlexibleTimestamp?
    public var context: String?
    public var availableAccounts: Double?
    public var constrainedAccounts: Double?
    public var unknownAccounts: Double?
    public var nextRecoveryAt: FlexibleTimestamp?

    public init(
        computedAt: FlexibleTimestamp? = nil,
        context: String? = nil,
        availableAccounts: Double? = nil,
        constrainedAccounts: Double? = nil,
        unknownAccounts: Double? = nil,
        nextRecoveryAt: FlexibleTimestamp? = nil
    ) {
        self.computedAt = computedAt
        self.context = context
        self.availableAccounts = availableAccounts
        self.constrainedAccounts = constrainedAccounts
        self.unknownAccounts = unknownAccounts
        self.nextRecoveryAt = nextRecoveryAt
    }
}

public struct WeeklyBudget: Codable, Sendable, Equatable {
    public var computedAt: FlexibleTimestamp?
    public var evidenceObservedAt: FlexibleTimestamp?
    public var period: WeeklyPeriod?
    public var outcome: String?
    public var quality: String?
    public var coverage: WeeklyCoverage?
    public var accountRisk: AccountRisk?
    public var exhaustsAt: FlexibleTimestamp?
    public var pace: WeeklyPace?
    public var reason: String?

    public init(
        computedAt: FlexibleTimestamp? = nil,
        evidenceObservedAt: FlexibleTimestamp? = nil,
        period: WeeklyPeriod? = nil,
        outcome: String? = nil,
        quality: String? = nil,
        coverage: WeeklyCoverage? = nil,
        accountRisk: AccountRisk? = nil,
        exhaustsAt: FlexibleTimestamp? = nil,
        pace: WeeklyPace? = nil,
        reason: String? = nil
    ) {
        self.computedAt = computedAt
        self.evidenceObservedAt = evidenceObservedAt
        self.period = period
        self.outcome = outcome
        self.quality = quality
        self.coverage = coverage
        self.accountRisk = accountRisk
        self.exhaustsAt = exhaustsAt
        self.pace = pace
        self.reason = reason
    }
}

public struct WeeklyPeriod: Codable, Sendable, Equatable {
    public var startsAt: FlexibleTimestamp?
    public var endsAt: FlexibleTimestamp?
    public var endReason: String?

    public init(
        startsAt: FlexibleTimestamp? = nil,
        endsAt: FlexibleTimestamp? = nil,
        endReason: String? = nil
    ) {
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.endReason = endReason
    }
}

public struct WeeklyCoverage: Codable, Sendable, Equatable {
    public var eligibleAccounts: Double?
    public var modeledAccounts: Double?
    public var idleAccounts: Double?
    public var learningAccounts: Double?
    public var unavailableAccounts: Double?

    public init(
        eligibleAccounts: Double? = nil,
        modeledAccounts: Double? = nil,
        idleAccounts: Double? = nil,
        learningAccounts: Double? = nil,
        unavailableAccounts: Double? = nil
    ) {
        self.eligibleAccounts = eligibleAccounts
        self.modeledAccounts = modeledAccounts
        self.idleAccounts = idleAccounts
        self.learningAccounts = learningAccounts
        self.unavailableAccounts = unavailableAccounts
    }
}

public struct AccountRisk: Codable, Sendable, Equatable {
    public var spentAccounts: Double?
    public var atRiskAccounts: Double?
    public var withinBudgetAccounts: Double?
    public var unknownAccounts: Double?

    public init(
        spentAccounts: Double? = nil,
        atRiskAccounts: Double? = nil,
        withinBudgetAccounts: Double? = nil,
        unknownAccounts: Double? = nil
    ) {
        self.spentAccounts = spentAccounts
        self.atRiskAccounts = atRiskAccounts
        self.withinBudgetAccounts = withinBudgetAccounts
        self.unknownAccounts = unknownAccounts
    }
}

public struct WeeklyPace: Codable, Sendable, Equatable {
    public var state: String?
    public var changePct: Double?
    public var qualification: String?
    public var reason: String?

    public init(
        state: String? = nil,
        changePct: Double? = nil,
        qualification: String? = nil,
        reason: String? = nil
    ) {
        self.state = state
        self.changePct = changePct
        self.qualification = qualification
        self.reason = reason
    }
}
