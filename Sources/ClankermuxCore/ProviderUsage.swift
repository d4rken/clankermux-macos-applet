import Foundation

/// One provider's weekly utilization, averaged with equal weight per account.
public struct ProviderUsageRow: Sendable, Equatable, Identifiable {
    /// The workload key from `WorkloadRegistry`.
    public let id: String
    public let label: String
    public let mark: ProviderMark
    public let percent: Int?
    public let valueText: String
    public let tooltip: String
    public let severity: Severity
    public let stale: Bool
    public let partial: Bool
    public let accountCount: Int
    public let totalAccounts: Int
}

extension UsageModel {
    /// A reading observed this far ahead of `now` is clock skew rather than a future measurement.
    static let readingSkewAllowance: TimeInterval = 60

    /// Weekly utilization per workload target.
    ///
    /// Equal weight per account, averaged before rounding: two accounts at 10.4% and 10.5% report
    /// 10%, not 11%. Accounts without a readable percentage are excluded from the average rather
    /// than counted as zero, and the surviving count is reported against the member count so a
    /// partial average is never mistaken for a complete one.
    public static func providerUsageRows(
        accounts: [Account]?, showScoped: Bool, now: Date, accountsFailed: Bool
    ) -> [ProviderUsageRow] {
        WorkloadRegistry.targets
            .filter { showScoped || $0.key != WorkloadRegistry.fableKey }
            .map { target in
                let family = target.key == WorkloadRegistry.fableKey
                let members = (accounts ?? []).filter {
                    $0.provider == target.provider
                        && ($0.measurementState ?? "").lowercased() != "not_applicable"
                }
                // The first matching window only: a repeated window must not count its account
                // twice.
                let readings = members.compactMap { account -> (percent: Double, stale: Bool)? in
                    let window = (account.windows ?? []).first {
                        family
                            ? $0.kind == "weekly_scoped" && $0.scopeId == "fable"
                            : $0.kind == "seven_day" && $0.scopeId == nil
                    }
                    guard let percent = Percent.clampNumber(window?.utilizationPct) else {
                        return nil
                    }
                    let reset = window?.resetsAt.instant
                    let stale =
                        account.measurementState != "fresh"
                        || isStaleReading(window?.observedAt.instant, now: now)
                        || reset.map { $0 <= now } ?? false
                    return (percent, stale)
                }

                let count = readings.count
                let total = members.count
                let percent =
                    count > 0
                    ? Int((readings.reduce(0) { $0 + $1.percent } / Double(count)).rounded()) : nil
                let stale = accountsFailed || readings.contains { $0.stale }
                let partial = count < total
                let marker = stale || partial ? "*" : ""
                return ProviderUsageRow(
                    id: target.key, label: target.label, mark: target.mark, percent: percent,
                    valueText: percent.map { "\($0)%\(marker)" } ?? (total > 0 ? "?" : "None"),
                    tooltip: "\(target.label): "
                        + (percent.map { "\($0)% weekly used" } ?? "usage unavailable")
                        + " · \(count)/\(total) accounts"
                        + (partial ? " · partial" : "") + (stale ? " · cached" : ""),
                    severity: stale || partial || percent == nil
                        ? .unknown : .utilization(percent!),
                    stale: stale, partial: partial, accountCount: count, totalAccounts: total)
            }
    }

    /// Whether an observation timestamp is too old, too far ahead, or missing to be trusted.
    static func isStaleReading(_ observedAt: Date?, now: Date) -> Bool {
        guard let observedAt else { return true }
        return observedAt.timeIntervalSince(now) > readingSkewAllowance
            || now.timeIntervalSince(observedAt) >= staleInterval
    }
}
