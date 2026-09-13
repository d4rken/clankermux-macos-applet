import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Workload model")
struct ViewModelTests {
    private func view(
        _ payload: WorkloadsResponse, now: Date = Fixtures.now, failed: Bool = false,
        showScoped: Bool = true
    ) -> UsageView {
        UsageModel.buildView(
            accounts: Fixtures.accounts(), workloads: payload, workloadsFailed: failed,
            options: ViewOptions(showScoped: showScoped), localNow: now)
    }

    @Test("positive and negative estimates use a centered 50-percent scale")
    func estimates() {
        var weekly = Fixtures.weekly()
        #expect(UsageModel.paceSignal(weekly).fill == -50)
        #expect(UsageModel.paceSignal(weekly).value == "−25%")
        weekly.pace?.changePct = 10
        weekly.outcome = "lasts_until_end"
        #expect(UsageModel.paceSignal(weekly).fill == 20)
        #expect(UsageModel.paceSignal(weekly).value == "+10%")
        weekly.pace?.changePct = 0
        #expect(UsageModel.paceSignal(weekly).value == "±0%")
        #expect(UsageModel.paceSignal(weekly).fill == 0)
    }

    @Test("tested limits are distinguished from recommended estimates")
    func limits() {
        var weekly = Fixtures.weekly()
        weekly.pace = WeeklyPace(state: "increase_limit", changePct: 50, qualification: "estimate")
        weekly.outcome = "lasts_until_end"
        #expect(UsageModel.paceSignal(weekly).value == "≥+50%")
        weekly.pace = WeeklyPace(
            state: "reduction_limit", changePct: -50, qualification: "estimate")
        weekly.outcome = "exhausts_before_end"
        #expect(UsageModel.paceSignal(weekly).value == "−50% insufficient")
        weekly.pace?.changePct = 50
        #expect(!UsageModel.paceSignal(weekly).numeric)
    }

    @Test("weak, partial, missing and unknown evidence withholds numeric advice")
    func unavailableAdvice() {
        var base = Fixtures.weekly()
        var cases: [WeeklyBudget] = []
        base.quality = "limited"
        cases.append(base)
        base = Fixtures.weekly()
        base.coverage?.idleAccounts = 1
        cases.append(base)
        base = Fixtures.weekly()
        base.coverage?.modeledAccounts = 1
        cases.append(base)
        base = Fixtures.weekly()
        base.coverage = nil
        cases.append(base)
        base = Fixtures.weekly()
        base.pace?.state = "future_state"
        cases.append(base)
        base = Fixtures.weekly()
        base.pace?.qualification = "future_basis"
        cases.append(base)
        base = Fixtures.weekly()
        base.pace?.changePct = nil
        cases.append(base)
        base = Fixtures.weekly()
        base.pace?.changePct = 1e300
        cases.append(base)
        base = Fixtures.weekly()
        base.outcome = "future_outcome"
        cases.append(base)
        for weekly in cases {
            let signal = UsageModel.paceSignal(weekly)
            #expect(signal.severity == .unknown)
            #expect(signal.fill == 0)
            #expect(!signal.numeric)
        }
    }

    @Test("computation time, not envelope or fetch time, determines freshness")
    func freshness() {
        var payload = Fixtures.workloads()
        payload.generatedAt = Fixtures.timestamp(1000)
        #expect(!view(payload, now: Fixtures.now.addingTimeInterval(179)).workloads[0].stale)
        let stale = view(payload, now: Fixtures.now.addingTimeInterval(180)).workloads[0]
        #expect(stale.stale)
        #expect(stale.signal.value == "Stale")
        #expect(stale.signal.fill == 0)
        #expect(stale.detail.contains("Last reading · Estimated pace: −25%"))
        payload.workloads?[0].weekly?.computedAt = nil
        #expect(view(payload).workloads[0].stale)
        #expect(view(Fixtures.workloads(), failed: true).workloads.allSatisfy { $0.stale })
    }

    @Test("expired and absent reset checkpoints never produce current advice")
    func deadlines() {
        var payload = Fixtures.workloads()
        payload.workloads?[0].weekly?.period?.endsAt = Fixtures.timestamp()
        let expired = view(payload).workloads[0]
        #expect(expired.expired)
        #expect(expired.signal.value == "Expired")
        #expect(expired.signal.fill == 0)
        payload.workloads?[0].weekly?.period = nil
        #expect(view(payload).workloads[0].signal.value == "No reading")
        payload.workloads?[0].weekly?.period = WeeklyPeriod(endsAt: FlexibleTimestamp(date: nil))
        #expect(view(payload).workloads[0].signal.fill == 0)
    }

    @Test("weekly and availability freshness are independent")
    func separateAvailability() {
        var payload = Fixtures.workloads()
        payload.workloads?[0].weekly?.computedAt = Fixtures.timestamp(-181)
        #expect(view(payload).workloads[0].availabilityText.hasPrefix("2 available now"))
        payload = Fixtures.workloads()
        payload.workloads?[0].availability?.computedAt = Fixtures.timestamp(-181)
        let row = view(payload).workloads[0]
        #expect(row.signal.numeric)
        #expect(row.availabilityText.hasPrefix("Stale availability"))
    }

    @Test("the popover summary line carries pace, exhaustion and coverage on one row")
    func summaryLine() {
        let rows = view(Fixtures.workloads()).workloads
        #expect(
            rows[0].summaryLine == "Claude: Weekly risk · −25% ~2h · 2/2 modeled")
        // A conservative bound is named once, in the parenthetical, not twice.
        #expect(rows[2].summaryLine.contains("−25% (bound)"))
        #expect(!rows[2].summaryLine.contains("bound bound"))
        #expect(rows[2].availabilityCount == "2")

        // A stale reading withholds the pace clause and the exhaustion estimate.
        let stale = view(Fixtures.workloads(), now: Fixtures.now.addingTimeInterval(180)).workloads
        #expect(stale[0].summaryLine == "Claude: Stale · Last reading: Weekly risk · 2/2 modeled")
        #expect(stale[0].availabilityCount == "stale")

        // Counts that do not add up describe no real split, so the coverage text is withheld.
        var payload = Fixtures.workloads()
        payload.workloads?[0].weekly?.coverage?.idleAccounts = 3
        let broken = view(payload).workloads[0]
        #expect(!broken.coverageValid)
        #expect(!broken.summaryLine.contains("/2 modeled"))
    }

    @Test("partial forecasts describe the modeled subset and retain disjoint coverage")
    func partialCoverage() {
        var payload = Fixtures.workloads()
        payload.workloads?[0].weekly?.coverage = WeeklyCoverage(
            eligibleAccounts: 5, modeledAccounts: 2, idleAccounts: 1, learningAccounts: 1,
            unavailableAccounts: 1)
        let row = view(payload).workloads[0]
        #expect(row.summary.contains("modeled subset"))
        #expect(row.coverageText.contains("2/5 modeled · 1 idle · 1 learning · 1 unreadable"))
        #expect(!row.signal.numeric)
    }

    @Test("family rows retain stable identity and overlap and respect visibility")
    func families() {
        var payload = Fixtures.workloads()
        payload.workloads?[0].label = "Renamed class"
        let family = view(payload).workloads[2]
        #expect(family.id == "family:fable")
        #expect(family.signal.value == "−25% bound")
        #expect(family.detail.contains("Overlaps Renamed class"))
        #expect(
            view(payload, showScoped: false).workloads.map(\.id) == [
                "class:anthropic", "class:codex",
            ])
        let duplicate = payload.workloads![0]
        payload.workloads?.append(duplicate)
        #expect(view(payload).workloads.count == 3)
    }

    @Test("missing measurements remain unknown and paused accounts remain visible")
    func accountDetails() {
        let accounts = view(Fixtures.workloads()).accounts
        #expect(accounts.count == 3)
        #expect(accounts[1].stateKey == .paused)
        #expect(accounts[2].windows[0].percent == nil)
        #expect(accounts[0].windows[1].forecastText.contains("Risk before reset"))
        #expect(accounts[0].windows[1].severity == .warning)
        #expect(accounts[0].windows[2].forecastText.contains("No usage"))
        let hidden = view(Fixtures.workloads(), showScoped: false)
        #expect(hidden.accounts[0].windows.count == 2)
    }

    @Test(
        "account measurement state determines staleness independently of forecast computation age")
    func accountStaleness() {
        let fresh = view(Fixtures.workloads(), now: Fixtures.now.addingTimeInterval(181))
        #expect(fresh.accounts[0].windows[0].severity == .normal)
        var accounts = Fixtures.accounts()
        accounts[0].measurementState = "stale"
        let stale = UsageModel.buildView(
            accounts: accounts, workloads: Fixtures.workloads(), localNow: Fixtures.now)
        #expect(stale.accounts[0].windows.allSatisfy { $0.severity == .unknown })
        #expect(stale.accounts[0].windows[0].forecastText.hasPrefix("Stale"))
    }

    @Test("partial exhaustion is qualified and contradictory pace advice is withheld")
    func exhaustion() {
        var weekly = Fixtures.weekly()
        weekly.outcome = "exhausted"
        #expect(UsageModel.paceSignal(weekly).value == "Out")
        weekly.coverage?.modeledAccounts = 1
        weekly.coverage?.idleAccounts = 1
        let partial = UsageModel.paceSignal(weekly)
        #expect(partial.value == "Subset out")
        #expect(partial.severity == .warning)
        #expect(!partial.numeric)
        weekly = Fixtures.weekly()
        weekly.pace?.changePct = 25
        #expect(UsageModel.paceSignal(weekly).severity == .unknown)
    }
}
