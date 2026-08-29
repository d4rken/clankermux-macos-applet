import Foundation

// MARK: - Value types

public enum Severity: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical
}

public enum StateKey: String, Sendable, Equatable {
    case available
    case paused
    case limited
    case error
}

public enum ForecastConfidence: String, Sendable, Equatable {
    case low
    case high
    case unknown
}

public struct WindowView: Sendable, Equatable, Identifiable {
    public let key: String
    public let kind: String
    public let scopeId: String?
    public let label: String
    public let percent: Int
    public let observedAt: Date?
    public let resetsAt: Date?
    public let projectedAtReset: Double?
    public let exhaustsAt: Date?
    public let willExhaust: Bool?
    public let forecastConfidence: ForecastConfidence
    public let predictionState: String?
    public let severity: Severity
    public let stale: Bool
    public let scoped: Bool

    public var id: String { key }
}

public struct AccountStateView: Sendable, Equatable {
    public let key: StateKey
    public let label: String
    public let until: Date?
}

public struct CredentialNotice: Sendable, Equatable {
    public let key: StateKey
    public let label: String
}

public struct UsagePool: Sendable, Equatable, Identifiable {
    public let key: String
    public let label: String
    public let scoped: Bool
    public let provider: String?
    public let usedPercent: Int
    public let remainingPercent: Int
    public let accountCount: Int
    public let unknownCount: Int
    public let nextResetAt: Date?
    public let severity: Severity

    public var id: String { key }
}

public struct ProviderOverload: Sendable, Equatable, Identifiable {
    public let key: String
    public let provider: String
    public let state: String
    public let until: Date?
    public let probeActive: Bool
    public let providerWide: Bool
    public let accountCount: Int

    public var id: String { key }
}

public struct RunwayCoverage: Sendable, Equatable {
    public let activeKeyCount: Int
    public let statedKeyCount: Int
    public let unobservedKeyCount: Int
}

public struct RunwayView: Sendable, Equatable {
    public let kind: String
    public let value: String
    public let panelText: String
    public let severity: Severity
    public let complete: Bool
    public let exhaustsAt: Date?
    public let causes: [String]
    public let summary: String
    public let coverage: RunwayCoverage
    public let coverageText: String
    public let horizonMs: Double
    public let horizonText: String
    public let generatedAt: Date?
    public let ageMs: Double?
    public let available: Bool
}

/// The subset of an account the runway cause labels need.
public struct RunwayAccount: Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AccountView: Sendable, Equatable, Identifiable {
    public let index: Int
    public let id: String
    public let name: String
    public let provider: String
    public let providerKey: String
    public let defaultCandidate: Bool
    public let state: AccountStateView
    public let stateClass: StateKey
    public let credential: CredentialNotice?
    public let measurementNotice: String?
    public let windows: [WindowView]
    public let stale: Bool
}

public struct PoolSummary: Sendable, Equatable {
    public let configured: Int
    public let defaultRoutable: Int
    public let paused: Int
    public let rateLimited: Int
    public let usageExhausted: Int
    public let nextAvailableAt: Date?
}

public struct UsageView: Sendable, Equatable {
    public let now: Date
    public let accounts: [AccountView]
    public let usagePools: [UsagePool]
    public let providerOverloads: [ProviderOverload]
    public let runway: RunwayView
    public let pool: PoolSummary
    public let status: String
    public let healthy: Bool
}

/// Display settings that change the view without refetching.
public struct ViewOptions: Sendable, Equatable {
    public var usageWarningThreshold: Double
    public var showScoped: Bool
    public var defaultCandidateFirst: Bool
    public var runwayWarningHours: Double
    public var statusReceivedAt: Date?
    public var runwayReceivedAt: Date?

    public init(
        usageWarningThreshold: Double = UsageModel.defaultUsageWarningPct,
        showScoped: Bool = true,
        defaultCandidateFirst: Bool = true,
        runwayWarningHours: Double = 72,
        statusReceivedAt: Date? = nil,
        runwayReceivedAt: Date? = nil
    ) {
        self.usageWarningThreshold = usageWarningThreshold
        self.showScoped = showScoped
        self.defaultCandidateFirst = defaultCandidateFirst
        self.runwayWarningHours = runwayWarningHours
        self.statusReceivedAt = statusReceivedAt
        self.runwayReceivedAt = runwayReceivedAt
    }
}

// MARK: - Model

/// Pure derivations from the `/public/v1` payloads. Foundation only, so every rule below is
/// exercisable in a headless test process.
public enum UsageModel {
    public static let defaultUsageWarningPct: Double = 80

    // MARK: Windows

    static func windowKey(_ window: UsageWindow, index: Int) -> String {
        if let kind = window.kind, kind == "five_hour" || kind == "seven_day" { return kind }
        let scope = nonEmpty(window.scopeId) ?? nonEmpty(window.label) ?? String(index)
        return "scope:\(scope.lowercased())"
    }

    static func windowLabel(_ window: UsageWindow) -> String {
        if let label = nonEmpty(window.label) { return label }
        if window.kind == "five_hour" { return "5 hour" }
        if window.kind == "seven_day" { return "7 day" }
        return Formatting.humanizeStatus(nonEmpty(window.scopeId) ?? window.kind)
    }

    /// The readable quota windows of one account.
    ///
    /// A window whose percentage cannot be read is omitted rather than shown as 0%.
    public static func accountWindows(
        account: Account?,
        showScoped: Bool = true,
        warningThreshold: Double = defaultUsageWarningPct
    ) -> [WindowView] {
        var result: [WindowView] = []
        let measurementState = (nonEmpty(account?.measurementState) ?? "other").lowercased()
        for (index, raw) in (account?.windows ?? []).enumerated() {
            let scoped = raw.kind == "weekly_scoped" || raw.scopeId != nil
            if scoped && !showScoped { continue }

            guard let percent = Percent.clampPercent(raw.utilizationPct) else { continue }

            let prediction = raw.prediction
            let projectedAtReset = Percent.clampNumber(prediction?.predictedUtilizationAtResetPct)
            let lowConfidence = prediction?.lowConfidence ?? false
            let willExhaust: Bool? =
                prediction == nil ? nil : (prediction?.willExhaustBeforeReset ?? false)
            let certainlyExhausts = percent >= 100 || (willExhaust == true && !lowConfidence)
            let nearExhaustion =
                willExhaust == true
                || Double(percent) >= warningThreshold
                || (projectedAtReset.map { $0 >= warningThreshold } ?? false)

            result.append(
                WindowView(
                    key: windowKey(raw, index: index),
                    kind: nonEmpty(raw.kind) ?? "other",
                    scopeId: raw.scopeId,
                    label: windowLabel(raw),
                    percent: percent,
                    observedAt: raw.observedAt.instant,
                    resetsAt: raw.resetsAt.instant,
                    projectedAtReset: projectedAtReset,
                    exhaustsAt: prediction?.exhaustsAt.instant,
                    willExhaust: willExhaust,
                    forecastConfidence: prediction == nil
                        ? .unknown : (lowConfidence ? .low : .high),
                    predictionState: prediction?.state,
                    severity: certainlyExhausts ? .critical : (nearExhaustion ? .warning : .normal),
                    stale: measurementState == "stale",
                    scoped: scoped
                ))
        }
        return result
    }

    // MARK: Account state

    public static func accountState(account: Account?) -> AccountStateView {
        let availability = account?.availability
        let state = (nonEmpty(availability?.state) ?? "other").lowercased()
        let labels: [String: String] = [
            "available": "Available",
            "paused": "Paused",
            "rate_limited": "Rate limited",
            "usage_exhausted": "Usage exhausted",
            "blocked": "Blocked",
            "other": "Unknown availability",
        ]
        let keys: [String: StateKey] = [
            "available": .available,
            "paused": .paused,
            "rate_limited": .limited,
            "usage_exhausted": .limited,
            "blocked": .error,
            "other": .error,
        ]
        var label = labels[state] ?? Formatting.humanizeStatus(state)
        if let reason = nonEmpty(availability?.reason) {
            label += " · \(Formatting.humanizeStatus(reason))"
        }
        return AccountStateView(
            key: keys[state] ?? .error,
            label: label,
            until: availability?.availableAt.instant
        )
    }

    /// Credential health, kept separate from availability so an expiring key is visible even while
    /// the account is routable.
    public static func credentialNotice(account: Account?) -> CredentialNotice? {
        let state = (nonEmpty(account?.credential?.state) ?? "other").lowercased()
        if state == "valid" || state == "not_applicable" { return nil }
        if state == "refreshable" {
            return CredentialNotice(key: .available, label: "Credential refreshable")
        }
        return CredentialNotice(
            key: .error,
            label: state == "other"
                ? "Credential state unknown"
                : "Credential \(Formatting.humanizeStatus(state).lowercased())"
        )
    }

    /// Measurement freshness, so cached or missing usage cannot pass as current.
    ///
    /// An absent `measurementState` defaults to `other`, which reads as "usage state unknown".
    public static func measurementNotice(account: Account?) -> String? {
        let state = (nonEmpty(account?.measurementState) ?? "other").lowercased()
        if state == "fresh" || state == "not_applicable" { return nil }
        let labels: [String: String] = [
            "stale": "cached usage",
            "missing": "usage missing",
            "other": "usage state unknown",
        ]
        return labels[state] ?? "usage \(Formatting.humanizeStatus(state).lowercased())"
    }

    // MARK: Pools

    static func poolSeverity(_ percent: Int?, warningThreshold: Double) -> Severity {
        guard let percent else { return .normal }
        if percent >= 100 { return .critical }
        return Double(percent) >= warningThreshold ? .warning : .normal
    }

    static func usagePool(
        key: String,
        label: String,
        aggregate: UsageAggregate?,
        scoped: Bool,
        warningThreshold: Double,
        provider: String? = nil
    ) -> UsagePool? {
        guard let usedPercent = Percent.clampPercent(aggregate?.meanUtilizationPct) else {
            return nil
        }
        return UsagePool(
            key: key,
            label: label,
            scoped: scoped,
            provider: provider,
            usedPercent: usedPercent,
            remainingPercent: 100 - usedPercent,
            accountCount: count(aggregate?.contributingAccountCount),
            unknownCount: count(aggregate?.unknownAccountCount),
            nextResetAt: aggregate?.earliestResetsAt.instant,
            severity: poolSeverity(usedPercent, warningThreshold: warningThreshold)
        )
    }

    /// Pool usage as the server reports it.
    ///
    /// These are the server's own aggregates; the applet never recomputes a mean from per-account
    /// windows, so a partial mean cannot pass as full coverage.
    public static func usagePools(
        status: StatusResponse?,
        showScoped: Bool = true,
        warningThreshold: Double = defaultUsageWarningPct
    ) -> [UsagePool] {
        var pools: [UsagePool] = []
        if let fiveHour = usagePool(
            key: "five_hour", label: "5h", aggregate: status?.usage?.fiveHour, scoped: false,
            warningThreshold: warningThreshold)
        {
            pools.append(fiveHour)
        }
        if let sevenDay = usagePool(
            key: "seven_day", label: "7d", aggregate: status?.usage?.sevenDay, scoped: false,
            warningThreshold: warningThreshold)
        {
            pools.append(sevenDay)
        }

        guard showScoped else { return pools }
        for provider in status?.providers ?? [] {
            let providerKey = nonEmpty(provider.provider) ?? "unknown"
            for limit in provider.scopedLimits ?? [] {
                let scopeId = nonEmpty(limit.scopeId) ?? "other"
                if let pool = usagePool(
                    key: "scope:\(providerKey):\(scopeId)",
                    label: nonEmpty(limit.label) ?? Formatting.humanizeStatus(scopeId),
                    aggregate: limit,
                    scoped: true,
                    warningThreshold: warningThreshold,
                    provider: provider.provider)
                {
                    pools.append(pool)
                }
            }
        }
        return pools
    }

    /// The compact panel drops unused scoped families but keeps 5h and 7d visible at 0%.
    public static func panelUsagePools(_ pools: [UsagePool]) -> [UsagePool] {
        pools.filter { !$0.scoped || $0.usedPercent > 0 }
    }

    // MARK: Overloads

    public static func providerOverloads(status: StatusResponse?, accounts: [Account] = [])
        -> [ProviderOverload]
    {
        var result: [ProviderOverload] = []
        for provider in status?.providers ?? [] {
            let any = provider.anyOverload
            let state = nonEmpty(any?.state) ?? "other"
            if state == "closed" { continue }
            let wideState = nonEmpty(provider.providerWideOverload?.state) ?? "closed"
            result.append(
                ProviderOverload(
                    key: nonEmpty(provider.provider) ?? "provider",
                    provider: Formatting.humanizeStatus(nonEmpty(provider.provider) ?? "provider"),
                    state: state,
                    until: any?.until.instant,
                    probeActive: any?.probeActive ?? false,
                    providerWide: wideState != "closed",
                    accountCount: accounts.filter { $0.provider == provider.provider }.count
                ))
        }
        return result.enumerated()
            .sorted { left, right in
                let comparison = left.element.provider.localizedCompare(right.element.provider)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    // MARK: Runway

    static func runwayCauseLabel(_ cause: OutcomeCause, accounts: [RunwayAccount]) -> String {
        let account = accounts.first { $0.id == cause.accountId }
        let accountName = account.flatMap { nonEmpty($0.name) } ?? "Unknown account"
        let labels = [
            "five_hour": "5-hour", "seven_day": "weekly", "weekly_scoped": "scoped weekly",
        ]
        let windowLabel =
            labels[cause.windowKind ?? ""]
            ?? Formatting.humanizeStatus(nonEmpty(cause.windowKind) ?? "window")
        return "\(accountName) · \(windowLabel)"
    }

    /// The headline projection.
    ///
    /// `kind` stays a raw string. A closed enum would collapse an unrecognized server kind onto
    /// `other`, which renders `R ?` where the applet must render `R –`.
    public static func runwayView(
        runway: RunwayResponse?,
        accounts: [RunwayAccount] = [],
        warningHours: Double = 72,
        localNow: Date,
        receivedAt: Date? = nil
    ) -> RunwayView {
        let coverage = RunwayCoverage(
            activeKeyCount: count(runway?.coverage?.activeKeyCount),
            statedKeyCount: count(runway?.coverage?.statedKeyCount),
            unobservedKeyCount: count(runway?.coverage?.unobservedKeyCount)
        )
        let complete =
            coverage.unobservedKeyCount == 0 && coverage.statedKeyCount == coverage.activeKeyCount
        let now = Formatting.anchoredNow(
            generatedAt: runway?.generatedAt.instant, receivedAt: receivedAt, localNow: localNow)
        let generatedAt = runway?.generatedAt.instant
        let horizonMs = max(0, positive(runway?.horizonMs) ?? 0)
        let horizonText = horizonMs > 0 ? Formatting.formatDuration(horizonMs) : "unknown"
        let outcome = runway?.worstStatedOutcome
        let kind = nonEmpty(outcome?.kind) ?? "unknown"
        let causes = (outcome?.causes ?? []).map { runwayCauseLabel($0, accounts: accounts) }
        let thresholdMs = max(1, positive(warningHours) ?? 72) * 60 * 60 * 1000

        var value = "–"
        var summary = "No stateable quota runway"
        var severity = Severity.warning
        var exhaustsAt: Date?

        switch kind {
        case "runway":
            exhaustsAt = outcome?.exhaustsAt.instant
            if let exhaustsAt {
                let remainingMs = max(0, exhaustsAt.timeIntervalSince(now) * 1000)
                value = Formatting.formatDuration(remainingMs)
                summary = "Projected quota run-out: \(Formatting.formatTimestamp(exhaustsAt))"
                severity =
                    remainingMs <= 0 ? .critical : (remainingMs <= thresholdMs ? .warning : .normal)
            }
        case "beyond_horizon":
            value = horizonMs > 0 ? ">\(Formatting.formatDuration(horizonMs))" : ">horizon"
            summary = "No quota run-out projected within the \(horizonText) model horizon"
            severity = .normal
        case "out_now":
            value = "OUT"
            summary = "Pool is out of quota now"
            severity = .critical
        case "no_accounts":
            summary = "No accounts are available to the quota model"
            severity = .critical
        case "other":
            value = "?"
            summary = "Quota runway state is not recognized"
        default:
            if outcome != nil {
                summary = "Quota runway is unknown because no readable window was available"
            }
        }

        // An unobserved key could have less runway than the stated projection, so incomplete
        // coverage never reads as comfortable.
        if !complete && severity == .normal { severity = .warning }
        let marker = complete ? "" : "*"
        let coverageText: String
        if coverage.activeKeyCount != 0 {
            let unobserved =
                coverage.unobservedKeyCount != 0
                ? " · \(coverage.unobservedKeyCount) unobserved" : ""
            coverageText =
                "\(coverage.statedKeyCount) of \(coverage.activeKeyCount) active keys observed"
                + unobserved
        } else {
            coverageText = "No active API keys"
        }

        return RunwayView(
            kind: kind,
            value: value,
            panelText: "R \(value)\(marker)",
            severity: severity,
            complete: complete,
            exhaustsAt: exhaustsAt,
            causes: causes,
            summary: summary,
            coverage: coverage,
            coverageText: coverageText,
            horizonMs: horizonMs,
            horizonText: horizonText,
            generatedAt: generatedAt,
            ageMs: generatedAt.map { max(0, now.timeIntervalSince($0) * 1000) },
            available: runway != nil
        )
    }

    // MARK: Composition

    public static func buildView(
        accounts: [Account]?,
        status: StatusResponse?,
        runway: RunwayResponse?,
        options: ViewOptions = ViewOptions(),
        localNow: Date
    ) -> UsageView {
        let list = accounts ?? []
        let warningThreshold = positive(options.usageWarningThreshold) ?? defaultUsageWarningPct
        let now = Formatting.anchoredNow(
            generatedAt: status?.generatedAt.instant,
            receivedAt: options.statusReceivedAt,
            localNow: localNow
        )
        var mapped = list.enumerated().map { index, account -> AccountView in
            let state = accountState(account: account)
            let credential = credentialNotice(account: account)
            return AccountView(
                index: index,
                id: nonEmpty(account.id) ?? nonEmpty(account.name) ?? String(index),
                name: nonEmpty(account.name) ?? "Account \(index + 1)",
                provider: Formatting.humanizeStatus(nonEmpty(account.provider) ?? "unknown"),
                providerKey: nonEmpty(account.provider) ?? "unknown",
                defaultCandidate: account.isDefaultCandidate ?? false,
                state: state,
                stateClass: credential?.key == .error ? .error : state.key,
                credential: credential,
                measurementNotice: measurementNotice(account: account),
                windows: accountWindows(
                    account: account,
                    showScoped: options.showScoped,
                    warningThreshold: warningThreshold
                ),
                stale: account.measurementState == "stale"
            )
        }

        if options.defaultCandidateFirst {
            mapped.sort { left, right in
                if left.defaultCandidate != right.defaultCandidate { return left.defaultCandidate }
                let leftAvailable = left.state.key == .available
                let rightAvailable = right.state.key == .available
                if leftAvailable != rightAvailable { return rightAvailable }
                return left.index < right.index
            }
        }

        // An explicit null is treated as a missing count and falls back to the derived value.
        let configured = finite(status?.pool?.configured).map { clampedInt($0) } ?? mapped.count
        let derivedRoutable = mapped.filter { $0.state.key == .available }.count
        let defaultRoutable =
            finite(status?.pool?.defaultRoutable).map { clampedInt($0) } ?? derivedRoutable

        let runwayNow = runwayView(
            runway: runway,
            accounts: mapped.map { RunwayAccount(id: $0.id, name: $0.name) },
            warningHours: options.runwayWarningHours,
            localNow: localNow,
            receivedAt: options.runwayReceivedAt
        )

        return UsageView(
            now: now,
            accounts: mapped,
            usagePools: usagePools(
                status: status, showScoped: options.showScoped, warningThreshold: warningThreshold),
            providerOverloads: providerOverloads(status: status, accounts: list),
            runway: runwayNow,
            pool: PoolSummary(
                configured: configured,
                defaultRoutable: defaultRoutable,
                paused: numberOrZero(status?.pool?.paused),
                rateLimited: numberOrZero(status?.pool?.rateLimited),
                usageExhausted: numberOrZero(status?.pool?.usageExhausted),
                nextAvailableAt: status?.pool?.nextAvailableAt.instant
            ),
            status: nonEmpty(status?.status) ?? "other",
            healthy: nonEmpty(status?.status).map { $0 == "ok" } ?? (defaultRoutable > 0)
        )
    }
}

// MARK: - Helpers

func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

/// A count reported by the server, floored at zero and defaulting to zero when unreadable.
func count(_ value: Double?) -> Int {
    guard let value, value.isFinite else { return 0 }
    return clampedInt(max(0, value))
}

/// A server-reported number that is passed through as-is, defaulting to zero when unreadable.
func numberOrZero(_ value: Double?) -> Int {
    guard let value, value.isFinite else { return 0 }
    return clampedInt(value)
}

func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

/// A configured magnitude, where zero means "unset" and falls back to the caller's default.
func positive(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value != 0 else { return nil }
    return value
}
