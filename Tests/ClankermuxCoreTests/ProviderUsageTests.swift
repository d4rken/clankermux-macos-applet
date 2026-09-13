import Foundation
import Testing

@testable import ClankermuxCore

/// The weekly usage panel averages percentages the server never averages for us, so the rules that
/// keep that average honest are pinned here: equal weight per account, no reading counted twice,
/// and nothing silently treated as zero.
@Suite("Provider usage")
struct ProviderUsageTests {
    private func rows(
        _ accounts: [Account]?, showScoped: Bool = true, now: Date = Fixtures.now,
        failed: Bool = false
    ) -> [ProviderUsageRow] {
        UsageModel.providerUsageRows(
            accounts: accounts, showScoped: showScoped, now: now, accountsFailed: failed)
    }

    private func account(
        _ provider: String, weekly: Double?, family: Double? = nil,
        measurement: String? = "fresh", observed: TimeInterval? = -60,
        resets: TimeInterval? = 86400
    ) -> Account {
        Account(
            provider: provider, measurementState: measurement,
            windows: [
                UsageWindow(kind: "five_hour", utilizationPct: 100),
                UsageWindow(
                    kind: "seven_day", utilizationPct: weekly,
                    observedAt: observed.map { Fixtures.timestamp($0) },
                    resetsAt: resets.map { Fixtures.timestamp($0) }),
                UsageWindow(
                    kind: "weekly_scoped", scopeId: "fable", utilizationPct: family,
                    observedAt: observed.map { Fixtures.timestamp($0) },
                    resetsAt: resets.map { Fixtures.timestamp($0) }),
            ])
    }

    @Test("usage averages accounts within each provider and keeps family usage separate")
    func averages() {
        let result = rows([
            account("codex", weekly: 25), account("codex", weekly: 75),
            account("anthropic", weekly: 20, family: 90),
            account("anthropic", weekly: 40, family: 100),
        ])
        #expect(result.map(\.id) == ["class:codex", "class:anthropic", "family:fable"])
        #expect(result.map(\.valueText) == ["50%", "30%", "95%"])
        #expect(result.map(\.accountCount) == [2, 2, 2])
        #expect(result[0].tooltip == "GPT: 50% weekly used · 2/2 accounts")
        #expect(result[0].severity == .normal)
        #expect(result[2].severity == .warning)
        #expect(rows([account("anthropic", weekly: 100)])[1].severity == .critical)
    }

    @Test("readings average before rounding, and an account counts once despite extra windows")
    func averagesBeforeRounding() {
        var doubled = account("codex", weekly: 10.4)
        doubled.windows?.append(UsageWindow(kind: "seven_day", utilizationPct: 99))
        // Rounding each reading first would report 11%.
        #expect(rows([doubled, account("codex", weekly: 10.5)], showScoped: false)[0].percent == 10)
        #expect(rows([doubled], showScoped: false)[0].valueText == "10%")
        #expect(rows([doubled], showScoped: false).count == 2)
    }

    @Test("the family row reads the scoped window, not the provider's weekly window")
    func scopedWindow() {
        let result = rows([account("anthropic", weekly: 20, family: 90)])
        #expect(result[1].percent == 20)
        #expect(result[2].percent == 90)
        #expect(result[2].mark == .fable)
    }

    @Test("only explicitly inapplicable accounts are excluded from coverage")
    func inapplicableAccounts() {
        var inapplicable = account("codex", weekly: nil)
        inapplicable.measurementState = "NOT_APPLICABLE"
        inapplicable.windows = []
        let row = rows([account("codex", weekly: 80), inapplicable], showScoped: false)[0]
        #expect(row.valueText == "80%")
        #expect(row.severity == .warning)
        #expect(row.tooltip.contains("1/1 accounts"))

        inapplicable.measurementState = "fresh"
        let counted = rows([account("codex", weekly: 80), inapplicable], showScoped: false)[0]
        #expect(counted.valueText == "80%*")
        #expect(counted.partial)
        #expect(counted.tooltip.contains("1/2 accounts · partial"))
        #expect(counted.severity == .unknown)
    }

    @Test("every staleness trigger marks the reading cached without suppressing it")
    func staleTriggers() {
        let triggers: [(String, Account)] = [
            ("measurement", account("codex", weekly: 83, measurement: "stale")),
            ("elapsed reset", account("codex", weekly: 83, resets: 0)),
            ("missing observation", account("codex", weekly: 83, observed: nil)),
            ("aged observation", account("codex", weekly: 83, observed: -180)),
            ("future observation", account("codex", weekly: 83, observed: 61)),
        ]
        for (trigger, account) in triggers {
            let row = rows([account], showScoped: false)[0]
            #expect(row.valueText == "83%*", "\(trigger) should mark the reading")
            #expect(row.stale, "\(trigger) should mark the reading")
            #expect(row.severity == .unknown)
            #expect(row.tooltip.hasSuffix(" · cached"))
        }
        // Skew inside the allowance, and an observation one second short of the cutoff, stay fresh.
        #expect(!rows([account("codex", weekly: 83, observed: 60)], showScoped: false)[0].stale)
        #expect(!rows([account("codex", weekly: 83, observed: -179)], showScoped: false)[0].stale)
        #expect(rows([account("codex", weekly: 83)], failed: true)[0].valueText == "83%*")
    }

    @Test("missing readings never count as zero, and no accounts is not an unreadable account")
    func missingReadings() {
        let partial = rows([account("codex", weekly: 80), account("codex", weekly: nil)])[0]
        #expect(partial.valueText == "80%*")
        #expect(partial.tooltip.contains("1/2 accounts · partial"))

        let unreadable = rows([account("codex", weekly: nil)])[0]
        #expect(unreadable.valueText == "?")
        #expect(unreadable.percent == nil)
        #expect(unreadable.tooltip == "GPT: usage unavailable · 0/1 accounts · partial")

        #expect(rows([])[0].valueText == "None")
        #expect(rows(nil)[0].valueText == "None")
        #expect(rows([account("codex", weekly: 0)])[0].valueText == "0%")
    }

    @Test("hidden scoped limits drop the family row entirely")
    func scopedVisibility() {
        #expect(
            rows([account("anthropic", weekly: 20, family: 90)], showScoped: false).map(\.id)
                == ["class:codex", "class:anthropic"])
    }
}
