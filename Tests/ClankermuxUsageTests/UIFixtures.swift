import Foundation

@testable import ClankermuxCore

enum UIFixtures {
    static func snapshot(accounts count: Int = 3) -> RefreshSnapshot {
        let now = Date()
        let timestamp = FlexibleTimestamp(date: now)
        let reset = FlexibleTimestamp(date: now.addingTimeInterval(86400))
        let accounts = (0..<count).map { index in
            Account(
                id: "a\(index)", name: "Account \(index + 1)",
                provider: index > 1 ? "codex" : "anthropic",
                availability: Availability(state: index == 1 ? "paused" : "available"),
                credential: Credential(state: "valid"), measurementState: "fresh",
                usageObservedAt: timestamp,
                windows: [
                    UsageWindow(
                        kind: "five_hour", label: "5-hour", utilizationPct: 35,
                        observedAt: timestamp,
                        resetsAt: reset,
                        forecast: WindowForecast(outcome: "lasts_until_reset", quality: "supported")
                    ),
                    UsageWindow(
                        kind: "seven_day", label: "Weekly", utilizationPct: 62,
                        observedAt: timestamp,
                        resetsAt: reset,
                        forecast: WindowForecast(
                            outcome: "exhausts_before_reset", quality: "supported")),
                ])
        }
        let workloads = [
            ("class:anthropic", "Claude", -25.0), ("class:codex", "GPT", 15.0),
            ("family:fable", "Fable", -40.0),
        ].map { id, label, pace in
            Workload(
                id: id, label: label,
                parentWorkloadId: id.hasPrefix("family:") ? "class:anthropic" : nil,
                availability: WorkloadAvailability(
                    computedAt: timestamp, context: "fresh_unpinned_nominal",
                    availableAccounts: 2, constrainedAccounts: 1, unknownAccounts: 0),
                weekly: WeeklyBudget(
                    computedAt: timestamp, evidenceObservedAt: timestamp,
                    period: WeeklyPeriod(
                        startsAt: timestamp, endsAt: reset, endReason: "next_weekly_reset"),
                    outcome: pace < 0 ? "exhausts_before_end" : "lasts_until_end",
                    quality: "supported",
                    coverage: WeeklyCoverage(
                        eligibleAccounts: 2, modeledAccounts: 2, idleAccounts: 0,
                        learningAccounts: 0, unavailableAccounts: 0),
                    accountRisk: AccountRisk(
                        spentAccounts: 0, atRiskAccounts: 1, withinBudgetAccounts: 1,
                        unknownAccounts: 0),
                    pace: WeeklyPace(
                        state: "estimate", changePct: pace,
                        qualification: id.hasPrefix("family:") ? "conservative_bound" : "estimate"))
            )
        }
        return RefreshSnapshot(
            baseURL: "http://localhost:8080", accounts: accounts,
            status: StatusResponse(
                serviceState: "ready", accounts: AccountTotals(configured: Double(count), paused: 1)
            ),
            workloads: WorkloadsResponse(workloads: workloads), accountsReceivedAt: now,
            statusReceivedAt: now,
            workloadsReceivedAt: now, lastSuccess: now, lastAccountsError: "", lastStatusError: "",
            lastWorkloadsError: "", isRefreshing: false)
    }
}
