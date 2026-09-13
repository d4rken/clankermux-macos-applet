import Foundation

public enum PanelDisplay: String, Sendable, Equatable, CaseIterable {
    case compact, usage
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
    public let display: PanelDisplay
    public let meters: [PanelMeter]
    public let usageRows: [ProviderUsageRow]
    public let tooltip: String

    /// Caveats that belong to every reading the app shows, wherever it shows it.
    private static let caveats = [
        "Pace estimates assume the current distribution of consumption across accounts.",
        "Availability is for fresh, unpinned, nominal-sized requests; 5-hour limits can interrupt separately.",
    ]

    public static func make(
        snapshot: RefreshSnapshot, view: UsageView, display: PanelDisplay, showScoped: Bool,
        now: Date
    ) -> PanelContent {
        var tooltip: [String] = []
        var headline = ""
        var severity = Severity.unknown
        var meters: [PanelMeter] = []
        var usageRows: [ProviderUsageRow] = []

        switch display {
        case .compact:
            let rows = pacedRows(snapshot: snapshot, view: view, now: now)
            severity = aggregate(rows.map { $0.signal.severity })
            let loading = snapshot.isRefreshing && snapshot.workloads == nil
            headline = rows.isEmpty ? (loading ? "Pace …" : "Pace –") : ""
            meters = rows.map {
                PanelMeter(
                    id: $0.id, label: $0.label, signal: $0.signal,
                    alwaysShowsValue: $0.stale || $0.expired
                        || (!$0.signal.numeric && $0.signal.severity != .unknown))
            }
            if view.workloads.isEmpty {
                tooltip.append(
                    snapshot.isRefreshing && snapshot.workloads == nil
                        ? "Loading workload pace…" : "Pacing unavailable")
            }
        case .usage:
            // No account list yet is loading or failure, never "no accounts configured".
            if snapshot.accounts == nil {
                let loading = snapshot.isRefreshing && snapshot.lastError.isEmpty
                headline = loading ? "Usage …" : "Usage !"
            } else {
                usageRows = providerUsage(
                    snapshot: snapshot, view: view, showScoped: showScoped, now: now)
                severity = aggregate(usageRows.map { $0.severity })
            }
            tooltip.append("Weekly usage · equal account average")
            tooltip.append(contentsOf: usageRows.map { $0.tooltip })
            if usageRows.contains(where: { $0.valueText.contains("*") }) {
                tooltip.append("* Partial or cached readings")
            }
        }

        tooltip.append(
            contentsOf: view.workloads.flatMap {
                [
                    "\($0.label): \($0.summary)", $0.coverageText, $0.detail, $0.availabilityText,
                    $0.freshnessText,
                ]
            })
        if !view.workloads.isEmpty { tooltip.append(contentsOf: caveats) }
        tooltip.append(DetailContent.lastRefreshText(lastSuccess: snapshot.lastSuccess, now: now))
        for (label, error) in [
            ("Accounts/status", snapshot.lastError), ("Workloads", snapshot.lastWorkloadsError),
        ] where !error.isEmpty {
            tooltip.append("\(label) refresh failed: \(error)")
        }

        return PanelContent(
            headline: headline, severity: severity, display: display, meters: meters,
            usageRows: usageRows, tooltip: tooltip.joined(separator: "\n"))
    }

    /// Workload rows minus the providers whose accounts are all paused.
    private static func pacedRows(snapshot: RefreshSnapshot, view: UsageView, now: Date)
        -> [WorkloadRow]
    {
        let accountsAreCurrent =
            snapshot.lastAccountsError.isEmpty
            && snapshot.accountsReceivedAt.map {
                now.timeIntervalSince($0) < UsageModel.staleInterval
            } == true
        return view.workloads.filter { row in
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
    }

    private static func providerUsage(
        snapshot: RefreshSnapshot, view: UsageView, showScoped: Bool, now: Date
    ) -> [ProviderUsageRow] {
        UsageModel.providerUsageRows(
            accounts: snapshot.accounts, showScoped: showScoped,
            now: snapshot.accountsNow(localNow: now),
            accountsFailed: !snapshot.lastAccountsError.isEmpty
        )
        // A server without a fable family would otherwise carry a permanent third "Fable None".
        .filter {
            $0.id != WorkloadRegistry.fableKey || view.workloads.contains { row in
                row.id == WorkloadRegistry.fableKey
            }
        }
    }

    private static func aggregate(_ severities: [Severity]) -> Severity {
        if severities.contains(.critical) { return .critical }
        if severities.contains(.warning) { return .warning }
        if !severities.isEmpty && severities.allSatisfy({ $0 == .normal }) { return .normal }
        return .unknown
    }
}
