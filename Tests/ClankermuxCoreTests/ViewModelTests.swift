import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Usage model")
struct ViewModelTests {

    // MARK: - Windows

    @Test("extracts public-v1 windows and their server predictions")
    func extractsWindows() {
        let windows = UsageModel.accountWindows(account: Fixtures.accounts()[0])

        #expect(
            windows.map { [$0.key, $0.label, String($0.percent)] } == [
                ["five_hour", "5-hour", "90"],
                ["seven_day", "Weekly", "60"],
                ["scope:fable", "Fable", "40"],
            ])
        #expect(windows[0].projectedAtReset == 95)
        #expect(windows[0].forecastConfidence == .high)
        #expect(windows[0].severity == .warning)
        #expect(windows[2].scoped)
    }

    @Test("omits unreadable windows instead of presenting them as zero")
    func omitsUnreadableWindows() {
        let windows = UsageModel.accountWindows(account: Fixtures.accounts()[2])
        #expect(windows.map(\.key) == ["seven_day"])
    }

    @Test("hides scoped and otherwise-scoped windows when configured")
    func hidesScopedWindows() {
        let base = Fixtures.accounts()[0]
        let extended = Fixtures.account(
            base,
            windows: (base.windows ?? [])
                + [
                    UsageWindow(
                        kind: "other", scopeId: "seven_day_oauth_apps", label: "Claude Code weekly",
                        utilizationPct: 25, observedAt: nil, resetsAt: nil, prediction: nil)
                ]
        )

        #expect(
            UsageModel.accountWindows(account: extended, showScoped: false).map(\.key)
                == ["five_hour", "seven_day"])
        #expect(
            UsageModel.accountWindows(account: extended).map(\.key)
                == ["five_hour", "seven_day", "scope:fable", "scope:seven_day_oauth_apps"])
    }

    @Test("low-confidence exhaustion is warning rather than critical")
    func lowConfidenceStaysWarning() {
        let window = UsageModel.accountWindows(account: Fixtures.accounts()[1])[0]
        #expect(window.willExhaust == true)
        #expect(window.forecastConfidence == .low)
        #expect(window.severity == .warning)
    }

    @Test("a full window is critical regardless of any forecast")
    func fullWindowIsCritical() {
        let window = UsageModel.accountWindows(account: Fixtures.accounts()[1])[2]
        #expect(window.percent == 100)
        #expect(window.severity == .critical)
    }

    @Test("a projection at reset above the threshold raises a comfortable window to warning")
    func projectionRaisesSeverity() {
        let account = Account(
            measurementState: "fresh",
            windows: [
                UsageWindow(
                    kind: "five_hour", utilizationPct: 20,
                    prediction: Prediction(
                        predictedUtilizationAtResetPct: 85, willExhaustBeforeReset: false,
                        lowConfidence: false))
            ])
        #expect(UsageModel.accountWindows(account: account)[0].severity == .warning)
    }

    // MARK: - Account state

    @Test("maps availability, reasons, and recovery instants")
    func mapsAvailability() {
        let state = UsageModel.accountState(account: Fixtures.accounts()[1])
        #expect(state.key == .limited)
        #expect(state.label == "Rate limited · Queueing")
        #expect(state.until == Fixtures.date("2026-08-24T12:30:00.000Z"))
        #expect(UsageModel.accountState(account: Fixtures.accounts()[0]).key == .available)
        #expect(UsageModel.accountState(account: Account()).key == .error)
        #expect(UsageModel.accountState(account: Account()).label == "Unknown availability")
    }

    @Test("keeps credential health separate from account availability")
    func credentialHealth() {
        #expect(UsageModel.credentialNotice(account: Fixtures.accounts()[0]) == nil)
        let refreshable = UsageModel.credentialNotice(account: Fixtures.accounts()[1])
        #expect(refreshable?.key == .available)
        #expect(refreshable?.label == "Credential refreshable")

        let invalid = UsageModel.credentialNotice(
            account: Account(credential: Credential(state: "invalid")))
        #expect(invalid?.key == .error)
        #expect(invalid?.label == "Credential invalid")
        #expect(
            UsageModel.credentialNotice(account: Account(credential: Credential(state: "not_applicable")))
                == nil)
        #expect(
            UsageModel.credentialNotice(account: Account())?.label == "Credential state unknown")
    }

    @Test("renders explicit measurement states")
    func explicitMeasurementStates() {
        #expect(UsageModel.measurementNotice(account: Fixtures.accounts()[0]) == nil)
        #expect(UsageModel.measurementNotice(account: Fixtures.accounts()[1]) == "cached usage")
        #expect(
            UsageModel.measurementNotice(account: Account(measurementState: "missing"))
                == "usage missing")
        #expect(
            UsageModel.measurementNotice(account: Account(measurementState: "not_applicable"))
                == nil)
    }

    /// The Cinnamon suite leaves these three fallbacks unpinned, so they are pinned here.
    @Test("renders the measurement fallbacks the source leaves unpinned")
    func measurementFallbacks() {
        #expect(
            UsageModel.measurementNotice(account: Account(measurementState: "other"))
                == "usage state unknown")
        #expect(UsageModel.measurementNotice(account: Account()) == "usage state unknown")
        #expect(
            UsageModel.measurementNotice(account: Account(measurementState: "probe_failed"))
                == "usage probe failed")
    }

    // MARK: - Pools

    @Test("uses server-provided pool aggregates without recomputing account means")
    func usesServerAggregates() {
        let pools = UsageModel.usagePools(status: Fixtures.status())
        #expect(
            pools.map { [$0.label, String($0.usedPercent), String($0.accountCount), String($0.unknownCount)] }
                == [
                    ["5h", "38", "2", "1"],
                    ["7d", "50", "3", "0"],
                    ["Fable", "70", "2", "0"],
                ])

        // Account A and B's 5-hour values average to 50, proving 38 came from status.
        let accountMean =
            (Fixtures.accounts()[0].windows![0].utilizationPct!
                + Fixtures.accounts()[1].windows![0].utilizationPct!) / 2
        #expect(accountMean == 50)
        #expect(pools[0].usedPercent == 38)
    }

    @Test("can suppress provider-scoped pool aggregates")
    func suppressesScopedPools() {
        #expect(
            UsageModel.usagePools(status: Fixtures.status(), showScoped: false).map(\.label)
                == ["5h", "7d"])
    }

    @Test("hides unused scoped families only in the compact panel")
    func panelHidesUnusedScopedFamilies() {
        let pools = [
            pool(key: "five_hour", scoped: false, usedPercent: 0),
            pool(key: "scope:anthropic:spark", scoped: true, usedPercent: 0),
            pool(key: "scope:anthropic:fable", scoped: true, usedPercent: 1),
        ]
        #expect(
            UsageModel.panelUsagePools(pools).map(\.key)
                == ["five_hour", "scope:anthropic:fable"])
    }

    @Test("pool severity follows the usage thresholds")
    func poolSeverities() {
        #expect(UsageModel.poolSeverity(79, warningThreshold: 80) == .normal)
        #expect(UsageModel.poolSeverity(80, warningThreshold: 80) == .warning)
        #expect(UsageModel.poolSeverity(100, warningThreshold: 80) == .critical)
        #expect(UsageModel.poolSeverity(nil, warningThreshold: 80) == .normal)
    }

    // MARK: - Overloads

    @Test("recognizes open and half-open provider overload breakers")
    func recognizesBreakers() {
        var providers = Fixtures.defaultProviders
        providers[0] = ProviderStatus(
            provider: "anthropic",
            anyOverload: BreakerState(state: "half_open", until: nil, probeActive: true),
            providerWideOverload: BreakerState(
                state: "open", until: Fixtures.stamp("2026-08-24T12:20:00.000Z"),
                probeActive: false),
            scopedLimits: providers[0].scopedLimits
        )

        let overloads = UsageModel.providerOverloads(
            status: Fixtures.status(providers: providers), accounts: Fixtures.accounts())
        #expect(overloads.count == 1)
        #expect(overloads[0].key == "anthropic")
        #expect(overloads[0].provider == "Anthropic")
        #expect(overloads[0].state == "half_open")
        #expect(overloads[0].until == nil)
        #expect(overloads[0].probeActive)
        #expect(overloads[0].providerWide)
        #expect(overloads[0].accountCount == 2)
    }

    // MARK: - Runway

    @Test("finite runway becomes the compact panel headline and resolves its cause")
    func finiteRunwayHeadline() {
        let view = UsageModel.runwayView(
            runway: Fixtures.runway(),
            accounts: [RunwayAccount(id: "account-c", name: "Account C")],
            warningHours: 72,
            localNow: Fixtures.now,
            receivedAt: Fixtures.now
        )
        #expect(view.panelText == "R 4d")
        #expect(view.value == "4d")
        #expect(view.severity == .normal)
        #expect(view.coverageText == "2 of 2 active keys observed")
        #expect(view.causes == ["Account C · weekly"])
        #expect(view.available)
    }

    @Test("runway warning threshold is expressed in hours")
    func warningThresholdInHours() {
        let response = Fixtures.runway(
            outcome: StatedOutcome(
                kind: "runway",
                exhaustsAt: FlexibleTimestamp(
                    date: Fixtures.now.addingTimeInterval(48 * 60 * 60)),
                causes: []
            ))
        #expect(
            UsageModel.runwayView(
                runway: response, warningHours: 72, localNow: Fixtures.now,
                receivedAt: Fixtures.now
            ).severity == .warning)
        #expect(
            UsageModel.runwayView(
                runway: response, warningHours: 24, localNow: Fixtures.now,
                receivedAt: Fixtures.now
            ).severity == .normal)
    }

    @Test("incomplete runway coverage is visibly qualified")
    func incompleteCoverage() {
        let response = Fixtures.runway(
            coverage: Coverage(activeKeyCount: 3, statedKeyCount: 2, unobservedKeyCount: 1),
            outcome: Fixtures.outcome(kind: "beyond_horizon")
        )
        let view = UsageModel.runwayView(
            runway: response, warningHours: 72, localNow: Fixtures.now, receivedAt: Fixtures.now)

        #expect(view.panelText == "R >14d*")
        #expect(view.severity == .warning)
        #expect(view.coverageText.contains("1 unobserved"))
        #expect(!view.complete)
    }

    @Test("renders every non-finite runway outcome honestly")
    func nonFiniteOutcomes() {
        let cases: [(String, String, Severity)] = [
            ("out_now", "R OUT", .critical),
            ("beyond_horizon", "R >14d", .normal),
            ("unknown", "R –", .warning),
            ("no_accounts", "R –", .critical),
            ("other", "R ?", .warning),
        ]
        for (kind, panelText, severity) in cases {
            let view = UsageModel.runwayView(
                runway: Fixtures.runway(outcome: Fixtures.outcome(kind: kind)),
                warningHours: 72,
                localNow: Fixtures.now,
                receivedAt: Fixtures.now
            )
            #expect(view.panelText == panelText, "kind: \(kind)")
            #expect(view.severity == severity, "kind: \(kind)")
        }
    }

    /// The `unknown` row above shares its rendering with any kind the server may add later.
    @Test("an unrecognized outcome kind reads as unknown, not as 'not recognized'")
    func unrecognizedOutcomeKind() {
        let view = UsageModel.runwayView(
            runway: Fixtures.runway(outcome: Fixtures.outcome(kind: "quantum_flux")),
            warningHours: 72,
            localNow: Fixtures.now,
            receivedAt: Fixtures.now
        )
        #expect(view.kind == "quantum_flux")
        #expect(view.value == "–")
        #expect(view.summary == "Quota runway is unknown because no readable window was available")
        #expect(view.severity == .warning)
    }

    @Test("an absent outcome states that there is no runway rather than guessing one")
    func absentOutcome() {
        let view = UsageModel.runwayView(
            runway: Fixtures.runway(omitOutcome: true),
            warningHours: 72,
            localNow: Fixtures.now,
            receivedAt: Fixtures.now
        )
        #expect(view.value == "–")
        #expect(view.summary == "No stateable quota runway")
        #expect(view.severity == .warning)
        #expect(view.available)
    }

    @Test("no runway payload at all is unavailable and warning")
    func nilRunway() {
        let view = UsageModel.runwayView(runway: nil, localNow: Fixtures.now)
        #expect(view.value == "–")
        #expect(view.panelText == "R –")
        #expect(view.summary == "No stateable quota runway")
        #expect(view.severity == .warning)
        #expect(!view.available)
        #expect(view.coverageText == "No active API keys")
        #expect(view.horizonText == "unknown")
        #expect(view.ageMs == nil)
    }

    @Test("a run-out already in the past is critical")
    func pastRunOutIsCritical() {
        let response = Fixtures.runway(
            outcome: StatedOutcome(
                kind: "runway",
                exhaustsAt: FlexibleTimestamp(date: Fixtures.now.addingTimeInterval(-60)),
                causes: []
            ))
        let view = UsageModel.runwayView(
            runway: response, warningHours: 72, localNow: Fixtures.now, receivedAt: Fixtures.now)
        #expect(view.value == "<1m")
        #expect(view.severity == .critical)
    }

    @Test("an unknown cause account is named as unknown rather than dropped")
    func unknownCauseAccount() {
        let response = Fixtures.runway(
            outcome: StatedOutcome(
                kind: "out_now",
                exhaustsAt: nil,
                causes: [OutcomeCause(accountId: "missing", windowKind: "weekly_scoped")]
            ))
        let view = UsageModel.runwayView(
            runway: response, warningHours: 72, localNow: Fixtures.now, receivedAt: Fixtures.now)
        #expect(view.causes == ["Unknown account · scoped weekly"])
    }

    // MARK: - Composition

    @Test("builds the public-v1 view and prioritizes the default candidate")
    func buildsView() {
        let view = UsageModel.buildView(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            options: ViewOptions(statusReceivedAt: Fixtures.now, runwayReceivedAt: Fixtures.now),
            localNow: Fixtures.now
        )

        #expect(view.accounts[0].name == "Account A")
        #expect(view.accounts[0].defaultCandidate)
        #expect(view.pool.defaultRoutable == 2)
        #expect(view.pool.configured == 3)
        #expect(view.usagePools.map(\.usedPercent) == [38, 50, 70])
        #expect(view.status == "ok")
        #expect(view.healthy)
    }

    @Test("unavailable accounts sort ahead of available ones")
    func unavailableSortsFirst() {
        let view = UsageModel.buildView(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            options: ViewOptions(),
            localNow: Fixtures.now
        )
        #expect(view.accounts.map(\.id) == ["account-a", "account-b", "account-c"])
    }

    @Test("the original order is kept when the sort is disabled")
    func keepsOriginalOrder() {
        let reversed = Array(Fixtures.accounts().reversed())
        let view = UsageModel.buildView(
            accounts: reversed,
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            options: ViewOptions(defaultCandidateFirst: false),
            localNow: Fixtures.now
        )
        #expect(view.accounts.map(\.id) == ["account-c", "account-b", "account-a"])
    }

    @Test("a credential error outranks an otherwise available state class")
    func credentialErrorOutranksState() {
        let account = Account(
            id: "a", name: "A", provider: "anthropic",
            availability: Availability(state: "available"),
            credential: Credential(state: "invalid"),
            measurementState: "fresh"
        )
        let view = UsageModel.buildView(
            accounts: [account], status: nil, runway: nil, options: ViewOptions(),
            localNow: Fixtures.now)
        #expect(view.accounts[0].state.key == .available)
        #expect(view.accounts[0].stateClass == .error)
    }

    @Test("missing pool counts fall back to the derived account counts")
    func derivedPoolCounts() {
        let view = UsageModel.buildView(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(pool: PoolInfo()),
            runway: nil,
            options: ViewOptions(),
            localNow: Fixtures.now
        )
        #expect(view.pool.configured == 3)
        #expect(view.pool.defaultRoutable == 2)
        #expect(view.healthy)
    }

    @Test("health falls back to routability when the server states no status")
    func healthFallback() {
        let view = UsageModel.buildView(
            accounts: [], status: Fixtures.status(statusValue: nil, pool: PoolInfo()), runway: nil,
            options: ViewOptions(), localNow: Fixtures.now)
        #expect(view.status == "other")
        #expect(!view.healthy)
    }

    // MARK: - Helpers

    private func pool(key: String, scoped: Bool, usedPercent: Int) -> UsagePool {
        UsagePool(
            key: key, label: key, scoped: scoped, provider: nil, usedPercent: usedPercent,
            remainingPercent: 100 - usedPercent, accountCount: 0, unknownCount: 0,
            nextResetAt: nil, severity: .normal)
    }
}
