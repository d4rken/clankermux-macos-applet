import Foundation

@testable import ClankermuxCore

enum Fixtures {
    static let now = date("2026-08-24T12:00:00.000Z")
    static func date(_ text: String) -> Date { FlexibleTimestamp.parse(text)! }
    static func timestamp(_ offset: TimeInterval = 0) -> FlexibleTimestamp {
        FlexibleTimestamp(date: now.addingTimeInterval(offset))
    }

    static func status() -> StatusResponse {
        StatusResponse(
            schema: "clankermux.public.status.v1", generatedAt: timestamp(),
            serviceState: "ready", version: "2026.9.53",
            accounts: AccountTotals(configured: 3, paused: 1))
    }

    static func accounts() -> [Account] {
        (0..<3).map { index in
            Account(
                id: "account-\(index)", name: "Account \(index + 1)",
                provider: index == 2 ? "codex" : "anthropic",
                availability: Availability(state: index == 1 ? "paused" : "available"),
                credential: Credential(state: "valid"), measurementState: "fresh",
                usageObservedAt: timestamp(),
                windows: [
                    UsageWindow(
                        kind: "five_hour", utilizationPct: index == 2 ? nil : 35,
                        observedAt: timestamp(), resetsAt: timestamp(3600),
                        forecast: WindowForecast(outcome: "lasts_until_reset", quality: "supported")
                    ),
                    UsageWindow(
                        kind: "seven_day", utilizationPct: 62,
                        observedAt: timestamp(), resetsAt: timestamp(86400),
                        forecast: WindowForecast(
                            outcome: "exhausts_before_reset", quality: "supported",
                            exhaustsAt: timestamp(7200))),
                    UsageWindow(
                        kind: "weekly_scoped", scopeId: "fable", label: "Fable", utilizationPct: 0,
                        observedAt: timestamp(), resetsAt: timestamp(86400),
                        forecast: WindowForecast(
                            outcome: "unknown", quality: "unavailable", reason: "no_usage")
                    ),
                ])
        }
    }

    static func weekly() -> WeeklyBudget {
        WeeklyBudget(
            computedAt: timestamp(), evidenceObservedAt: timestamp(),
            period: WeeklyPeriod(
                startsAt: timestamp(), endsAt: timestamp(86400), endReason: "next_weekly_reset"),
            outcome: "exhausts_before_end", quality: "supported",
            coverage: WeeklyCoverage(
                eligibleAccounts: 2, modeledAccounts: 2, idleAccounts: 0,
                learningAccounts: 0, unavailableAccounts: 0),
            accountRisk: AccountRisk(
                spentAccounts: 0, atRiskAccounts: 1, withinBudgetAccounts: 1, unknownAccounts: 0),
            exhaustsAt: timestamp(7200),
            pace: WeeklyPace(state: "estimate", changePct: -25, qualification: "estimate"))
    }

    static func workloads() -> WorkloadsResponse {
        let availability = WorkloadAvailability(
            computedAt: timestamp(), context: "fresh_unpinned_nominal",
            availableAccounts: 2, constrainedAccounts: 1, unknownAccounts: 0)
        var family = weekly()
        family.pace?.qualification = "conservative_bound"
        return WorkloadsResponse(
            schema: "clankermux.public.workloads.v1", generatedAt: timestamp(),
            workloads: [
                Workload(
                    id: "class:anthropic", label: "Claude", availability: availability,
                    weekly: weekly()),
                Workload(
                    id: "class:codex", label: "GPT", availability: availability, weekly: weekly()),
                Workload(
                    id: "family:fable", label: "Fable", parentWorkloadId: "class:anthropic",
                    availability: availability, weekly: family),
            ])
    }

    static func snapshot(
        workloads: WorkloadsResponse? = workloads(), accounts: [Account]? = accounts(),
        workloadsError: String = "", accountsError: String = ""
    ) -> RefreshSnapshot {
        RefreshSnapshot(
            baseURL: "http://clankermux.test:8080", accounts: accounts,
            status: status(), workloads: workloads, accountsReceivedAt: accounts == nil ? nil : now,
            statusReceivedAt: now, workloadsReceivedAt: workloads == nil ? nil : now,
            lastSuccess: now, lastAccountsError: accountsError, lastStatusError: "",
            lastWorkloadsError: workloadsError, isRefreshing: false)
    }

    static func json<T: Encodable>(_ value: T) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }
    static var statusJSON: String { json(status()) }
    static var accountsJSON: String {
        json(AccountsResponse(schema: "clankermux.public.accounts.v1", accounts: accounts()))
    }
    static var workloadsJSON: String { json(workloads()) }
}
