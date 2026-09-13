import Foundation

public enum PanelDisplay: String, Sendable, Equatable, CaseIterable {
    case icon, compact, full
}

public struct PanelMeter: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let signal: PaceSignal
    public let alwaysShowsValue: Bool
}

public struct PanelContent: Sendable, Equatable {
    public let headline: String
    public let severity: Severity
    public let iconOnly: Bool
    public let compact: Bool
    public let meters: [PanelMeter]
    public let tooltip: String

    public static func make(
        snapshot: RefreshSnapshot, view: UsageView, display: PanelDisplay, now: Date
    ) -> PanelContent {
        let accountsAreCurrent =
            snapshot.lastAccountsError.isEmpty
            && snapshot.accountsReceivedAt.map {
                now.timeIntervalSince($0) < UsageModel.staleInterval
            } == true
        let rows = view.workloads.filter { row in
            guard accountsAreCurrent, let accounts = snapshot.accounts else { return true }
            let classID =
                row.id.hasPrefix("class:")
                ? row.id
                : snapshot.workloads?.workloads?.first { $0.id == row.id }?.parentWorkloadId
            guard let classID, classID.hasPrefix("class:") else { return true }
            let provider = String(classID.dropFirst("class:".count))
            let matching = accounts.filter { $0.provider == provider }
            return matching.isEmpty || !matching.allSatisfy { $0.availability?.state == "paused" }
        }
        let severity: Severity
        if rows.contains(where: { $0.signal.severity == .critical }) {
            severity = .critical
        } else if rows.contains(where: { $0.signal.severity == .warning }) {
            severity = .warning
        } else if !rows.isEmpty && rows.allSatisfy({ $0.signal.severity == .normal }) {
            severity = .normal
        } else {
            severity = .unknown
        }
        let text: String
        if rows.isEmpty {
            text = snapshot.isRefreshing && snapshot.workloads == nil ? "Pace …" : "Pace –"
        } else {
            text = rows.map { "\($0.label) \($0.signal.value)" }.joined(separator: " · ")
        }
        var tooltip = view.workloads.flatMap {
            [
                "\($0.label): \($0.summary)", $0.coverageText, $0.detail, $0.availabilityText,
                $0.freshnessText,
            ]
        }
        if tooltip.isEmpty {
            tooltip.append(
                snapshot.isRefreshing && snapshot.workloads == nil
                    ? "Loading workload pace…" : "Pacing unavailable")
        }
        tooltip.append(DetailContent.lastRefreshText(lastSuccess: snapshot.lastSuccess, now: now))
        for (label, error) in [
            ("Accounts/status", snapshot.lastError), ("Workloads", snapshot.lastWorkloadsError),
        ] where !error.isEmpty {
            tooltip.append("\(label) refresh failed: \(error)")
        }
        return PanelContent(
            headline: display == .icon || !rows.isEmpty ? "" : text,
            severity: severity, iconOnly: display == .icon,
            compact: display == .compact,
            meters: display != .icon
                ? rows.map {
                    PanelMeter(
                        id: $0.id, label: $0.label, signal: $0.signal,
                        alwaysShowsValue: $0.stale || $0.expired
                            || (!$0.signal.numeric && $0.signal.severity != .unknown))
                } : [],
            tooltip: tooltip.joined(separator: "\n"))
    }
}
