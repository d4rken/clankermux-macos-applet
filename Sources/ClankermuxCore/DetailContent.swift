import Foundation

public enum DetailStyle: String, Sendable, Equatable {
    case normal
    case warning
    case error
}

public struct InfoBlock: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let style: DetailStyle
}

public struct PoolRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let usedPercent: Int
    public let severity: Severity
    /// For example `2 accts · 1 unknown · next in 1h`.
    public let detail: String
}

public struct PoolSummaryBlock: Sendable, Equatable {
    public let title: String
    public let subtitle: String
    public let rows: [PoolRow]
}

public struct WindowRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let percent: Int
    public let severity: Severity
    public let percentText: String
    /// The projection at reset, for example `→95%`, empty when the server states none.
    public let forecastText: String
    public let resetText: String
    public let scoped: Bool
}

public struct AccountBlock: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isDefaultCandidate: Bool
    public let provider: String
    public let stateText: String
    public let stateKey: StateKey
    public let windows: [WindowRow]
    /// Stands in for the usage bars when the account has no readable window.
    public let emptyText: String?
}

/// Everything the popover renders, already formatted, so the SwiftUI layer makes no display
/// decisions of its own.
public struct DetailContent: Sendable, Equatable {
    /// The loading or unavailable placeholder, present only while nothing has loaded.
    public let placeholder: InfoBlock?
    public let header: InfoBlock?
    public let runway: InfoBlock?
    public let overloads: [InfoBlock]
    public let pools: PoolSummaryBlock?
    public let accounts: [AccountBlock]
    public let emptyAccountsNotice: InfoBlock?
    public let errorNotice: InfoBlock?
    public let lastRefreshText: String

    public static func make(
        state: LoadState,
        view: UsageView,
        baseURL: String,
        lastError: String,
        lastRunwayError: String,
        lastSuccess: Date?,
        now: Date
    ) -> DetailContent {
        let lastRefreshText = Self.lastRefreshText(lastSuccess: lastSuccess, now: now)

        guard state.isLoaded else {
            let failed = !lastError.isEmpty
            let details = [
                failed ? lastError : Formatting.normalizeBaseUrl(baseURL),
                lastRefreshText,
            ].filter { !$0.isEmpty }.joined(separator: "\n")
            return DetailContent(
                placeholder: InfoBlock(
                    id: "placeholder",
                    title: failed ? "Clankermux is unavailable" : "Loading usage…",
                    subtitle: details,
                    style: failed ? .error : .normal
                ),
                header: nil,
                runway: nil,
                overloads: [],
                pools: nil,
                accounts: [],
                emptyAccountsNotice: nil,
                errorNotice: nil,
                lastRefreshText: lastRefreshText
            )
        }

        var subtitle =
            "\(view.pool.defaultRoutable) of \(view.pool.configured) accounts available in the default routing context"
        if !lastError.isEmpty { subtitle += " · showing cached data" }
        subtitle += "\n\(lastRefreshText)"

        var runwayDetails = [
            view.runway.summary,
            "Coverage: \(view.runway.coverageText)",
            "Model horizon: \(view.runway.horizonText)",
        ]
        if let ageMs = view.runway.ageMs {
            runwayDetails.append("Projection updated: \(Formatting.formatDuration(ageMs)) ago")
        }
        if !view.runway.causes.isEmpty {
            runwayDetails.append("Cause: \(view.runway.causes.joined(separator: " + "))")
        }
        if !lastRunwayError.isEmpty {
            runwayDetails.append("Last runway refresh failed: \(lastRunwayError)")
        }

        let overloads = view.providerOverloads.map { overload -> InfoBlock in
            let scope = overload.providerWide ? "Provider-wide breaker" : "Provider/model breaker"
            let recovery: String
            if let until = overload.until {
                recovery = "retry \(Formatting.formatReset(until, now: view.now))"
            } else {
                recovery = overload.probeActive
                    ? "recovery probe active" : "awaiting recovery probe"
            }
            let plural = overload.accountCount == 1 ? "" : "s"
            return InfoBlock(
                id: "overload:\(overload.key)",
                title: "\(overload.provider) overload \(overload.state)",
                subtitle:
                    "\(scope) · \(overload.accountCount) account\(plural) · \(recovery)",
                style: .error
            )
        }

        let pools: PoolSummaryBlock? =
            view.usagePools.isEmpty
            ? nil
            : PoolSummaryBlock(
                title: "Pool usage",
                subtitle: "Server-reported mean across accounts that supplied each quota window",
                rows: view.usagePools.map { pool in
                    let unknown = pool.unknownCount != 0 ? " · \(pool.unknownCount) unknown" : ""
                    let nextReset =
                        nonEmpty(Formatting.formatReset(pool.nextResetAt, now: view.now)) ?? "–"
                    let plural = pool.accountCount == 1 ? "" : "s"
                    return PoolRow(
                        id: pool.key,
                        label: pool.label,
                        usedPercent: pool.usedPercent,
                        severity: pool.severity,
                        detail: "\(pool.accountCount) acct\(plural)\(unknown) · next \(nextReset)"
                    )
                }
            )

        let accounts = view.accounts.map { account -> AccountBlock in
            var stateParts = [account.state.label]
            if let until = account.state.until {
                stateParts.append("retry \(Formatting.formatReset(until, now: view.now))")
            }
            if let credential = account.credential { stateParts.append(credential.label) }
            if let notice = account.measurementNotice { stateParts.append(notice) }
            let windows = account.windows.map { window in
                WindowRow(
                    id: window.key,
                    label: window.label,
                    percent: window.percent,
                    severity: window.severity,
                    percentText: "\(window.percent)%",
                    forecastText: window.projectedAtReset.map { "→\(Int($0.rounded()))%" } ?? "",
                    resetText: Formatting.formatReset(window.resetsAt, now: view.now),
                    scoped: window.scoped
                )
            }
            return AccountBlock(
                id: account.id,
                name: account.name,
                isDefaultCandidate: account.defaultCandidate,
                provider: account.provider,
                stateText: stateParts.joined(separator: " · "),
                stateKey: account.stateClass,
                windows: windows,
                emptyText: windows.isEmpty ? "Usage data not available yet" : nil
            )
        }

        return DetailContent(
            placeholder: nil,
            header: InfoBlock(
                id: "header", title: "Clankermux usage", subtitle: subtitle, style: .normal),
            runway: InfoBlock(
                id: "runway",
                title: "Quota runway · \(view.runway.value)",
                subtitle: runwayDetails.joined(separator: "\n"),
                style: style(for: view.runway.severity)
            ),
            overloads: overloads,
            pools: pools,
            accounts: accounts,
            emptyAccountsNotice: accounts.isEmpty
                ? InfoBlock(
                    id: "no-accounts", title: "No accounts configured", subtitle: "", style: .normal)
                : nil,
            errorNotice: lastError.isEmpty
                ? nil
                : InfoBlock(
                    id: "refresh-failed", title: "Refresh failed", subtitle: lastError,
                    style: .error),
            lastRefreshText: lastRefreshText
        )
    }

    static func style(for severity: Severity) -> DetailStyle {
        switch severity {
        case .critical: return .error
        case .warning: return .warning
        case .normal: return .normal
        }
    }

    static func lastRefreshText(lastSuccess: Date?, now: Date) -> String {
        guard let lastSuccess else { return "Last refreshed: Never" }
        let timestamp = Formatting.formatTimestamp(lastSuccess)
        let age = Formatting.formatDuration(now.timeIntervalSince(lastSuccess) * 1000)
        return "Last refreshed: \(timestamp) (\(age) ago)"
    }
}
