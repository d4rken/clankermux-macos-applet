import Foundation

@testable import ClankermuxCore

/// The `/public/v1` payloads from the Cinnamon applet's `test/publicV1Fixtures.js`, as Swift values
/// and as the raw JSON the server would send, so the same data drives the view-model and the
/// decoding tests.
enum Fixtures {
    static let nowISO = "2026-08-24T12:00:00.000Z"
    static var now: Date { date(nowISO) }

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let parsed = formatter.date(from: iso) else {
            fatalError("fixture timestamp is not ISO-8601: \(iso)")
        }
        return parsed
    }

    static func stamp(_ iso: String) -> FlexibleTimestamp { FlexibleTimestamp(date: date(iso)) }

    // MARK: - Status

    static let defaultPool = PoolInfo(
        configured: 3,
        configuredPresence: .present,
        defaultRoutable: 2,
        defaultRoutablePresence: .present,
        paused: 0,
        rateLimited: 1,
        usageExhausted: 0,
        nextAvailableAt: stamp("2026-08-24T12:30:00.000Z")
    )

    static let defaultUsage = UsageSection(
        fiveHour: UsageAggregate(
            meanUtilizationPct: 37.5,
            contributingAccountCount: 2,
            unknownAccountCount: 1,
            earliestResetsAt: stamp("2026-08-24T13:00:00.000Z")
        ),
        sevenDay: UsageAggregate(
            meanUtilizationPct: 50,
            contributingAccountCount: 3,
            unknownAccountCount: 0,
            earliestResetsAt: stamp("2026-08-25T03:00:00.000Z")
        )
    )

    static let closedBreaker = BreakerState(state: "closed", until: nil, probeActive: false)

    static let defaultProviders = [
        ProviderStatus(
            provider: "anthropic",
            anyOverload: closedBreaker,
            providerWideOverload: closedBreaker,
            scopedLimits: [
                UsageAggregate(
                    scopeId: "fable",
                    label: "Fable",
                    meanUtilizationPct: 70.3,
                    contributingAccountCount: 2,
                    unknownAccountCount: 0,
                    earliestResetsAt: stamp("2026-08-25T03:00:00.000Z")
                )
            ]
        ),
        ProviderStatus(
            provider: "codex",
            anyOverload: closedBreaker,
            providerWideOverload: closedBreaker,
            scopedLimits: []
        ),
    ]

    static func status(
        schema: String? = "clankermux.public.status.v1",
        statusValue: String? = "ok",
        pool: PoolInfo? = nil,
        usage: UsageSection? = nil,
        providers: [ProviderStatus]? = nil
    ) -> StatusResponse {
        StatusResponse(
            schema: schema,
            generatedAt: stamp(nowISO),
            status: statusValue,
            pool: pool ?? defaultPool,
            usage: usage ?? defaultUsage,
            providers: providers ?? defaultProviders
        )
    }

    // MARK: - Accounts

    static func accounts() -> [Account] {
        [
            Account(
                id: "account-a",
                name: "Account A",
                provider: "anthropic",
                isDefaultCandidate: true,
                availability: Availability(state: "available", reason: nil, availableAt: nil),
                credential: Credential(
                    state: "valid", expiresAt: stamp("2026-08-24T17:00:00.000Z")),
                measurementState: "fresh",
                windows: [
                    UsageWindow(
                        kind: "five_hour", scopeId: nil, label: "5-hour",
                        utilizationPct: 90,
                        observedAt: stamp("2026-08-24T11:59:00.000Z"),
                        resetsAt: stamp("2026-08-24T13:00:00.000Z"),
                        prediction: Prediction(
                            predictedUtilizationAtResetPct: 95,
                            exhaustsAt: stamp("2026-08-24T13:15:00.000Z"),
                            willExhaustBeforeReset: false,
                            lowConfidence: false,
                            state: "rising"
                        )
                    ),
                    UsageWindow(
                        kind: "seven_day", scopeId: nil, label: "Weekly",
                        utilizationPct: 60,
                        observedAt: stamp("2026-08-24T11:59:00.000Z"),
                        resetsAt: stamp("2026-08-30T07:00:00.000Z"),
                        prediction: nil
                    ),
                    UsageWindow(
                        kind: "weekly_scoped", scopeId: "fable", label: "Fable",
                        utilizationPct: 40,
                        observedAt: stamp("2026-08-24T11:59:00.000Z"),
                        resetsAt: stamp("2026-08-30T07:00:00.000Z"),
                        prediction: nil
                    ),
                ]
            ),
            Account(
                id: "account-b",
                name: "Account B",
                provider: "anthropic",
                isDefaultCandidate: false,
                availability: Availability(
                    state: "rate_limited", reason: "queueing",
                    availableAt: stamp("2026-08-24T12:30:00.000Z")),
                credential: Credential(state: "refreshable", expiresAt: nil),
                measurementState: "stale",
                windows: [
                    UsageWindow(
                        kind: "five_hour", scopeId: nil, label: "5-hour",
                        utilizationPct: 10,
                        observedAt: stamp("2026-08-24T11:20:00.000Z"),
                        resetsAt: stamp("2026-08-24T14:00:00.000Z"),
                        prediction: Prediction(
                            predictedUtilizationAtResetPct: 100,
                            exhaustsAt: stamp("2026-08-24T13:45:00.000Z"),
                            willExhaustBeforeReset: true,
                            lowConfidence: true,
                            state: "rising"
                        )
                    ),
                    UsageWindow(
                        kind: "seven_day", scopeId: nil, label: "Weekly",
                        utilizationPct: 80,
                        observedAt: stamp("2026-08-24T11:20:00.000Z"),
                        resetsAt: stamp("2026-08-25T03:00:00.000Z"),
                        prediction: nil
                    ),
                    UsageWindow(
                        kind: "weekly_scoped", scopeId: "fable", label: "Fable",
                        utilizationPct: 100,
                        observedAt: stamp("2026-08-24T11:20:00.000Z"),
                        resetsAt: stamp("2026-08-25T03:00:00.000Z"),
                        prediction: nil
                    ),
                ]
            ),
            Account(
                id: "account-c",
                name: "Account C",
                provider: "codex",
                isDefaultCandidate: false,
                availability: Availability(state: "available", reason: nil, availableAt: nil),
                credential: Credential(state: "not_applicable", expiresAt: nil),
                measurementState: "fresh",
                windows: [
                    UsageWindow(
                        kind: "five_hour", scopeId: nil, label: "5-hour",
                        utilizationPct: nil,
                        observedAt: stamp("2026-08-24T11:58:00.000Z"),
                        resetsAt: nil,
                        prediction: nil
                    ),
                    UsageWindow(
                        kind: "seven_day", scopeId: nil, label: "Weekly",
                        utilizationPct: 10,
                        observedAt: stamp("2026-08-24T11:58:00.000Z"),
                        resetsAt: stamp("2026-08-31T06:00:00.000Z"),
                        prediction: nil
                    ),
                ]
            ),
        ]
    }

    static func account(_ base: Account, windows: [UsageWindow]) -> Account {
        Account(
            id: base.id,
            name: base.name,
            provider: base.provider,
            isDefaultCandidate: base.isDefaultCandidate,
            availability: base.availability,
            credential: base.credential,
            measurementState: base.measurementState,
            windows: windows
        )
    }

    // MARK: - Runway

    static let defaultCoverage = Coverage(
        activeKeyCount: 2, statedKeyCount: 2, unobservedKeyCount: 0)

    static var defaultOutcome: StatedOutcome {
        StatedOutcome(
            kind: "runway",
            exhaustsAt: FlexibleTimestamp(date: now.addingTimeInterval(4 * 24 * 60 * 60)),
            causes: [OutcomeCause(accountId: "account-c", windowKind: "seven_day")]
        )
    }

    static func runway(
        schema: String? = "clankermux.public.runway.v1",
        coverage: Coverage? = nil,
        outcome: StatedOutcome? = nil,
        omitOutcome: Bool = false
    ) -> RunwayResponse {
        RunwayResponse(
            schema: schema,
            generatedAt: stamp(nowISO),
            horizonMs: 14 * 24 * 60 * 60 * 1000,
            coverage: coverage ?? defaultCoverage,
            worstStatedOutcome: omitOutcome ? nil : (outcome ?? defaultOutcome)
        )
    }

    static func outcome(kind: String) -> StatedOutcome {
        StatedOutcome(kind: kind, exhaustsAt: nil, causes: [])
    }

    // MARK: - Wire payloads

    static let statusJSON = """
        {
          "schema": "clankermux.public.status.v1",
          "generatedAt": "2026-08-24T12:00:00.000Z",
          "status": "ok",
          "uptimeS": 120,
          "version": "2026.8.83",
          "pool": {
            "configured": 3,
            "defaultRoutable": 2,
            "paused": 0,
            "rateLimited": 1,
            "usageExhausted": 0,
            "nextAvailableAt": "2026-08-24T12:30:00.000Z"
          },
          "routing": {
            "context": "fresh_unpinned_nominal",
            "defaultCandidateAccountId": "account-a"
          },
          "usage": {
            "fiveHour": {
              "meanUtilizationPct": 37.5,
              "contributingAccountCount": 2,
              "unknownAccountCount": 1,
              "earliestResetsAt": "2026-08-24T13:00:00.000Z"
            },
            "sevenDay": {
              "meanUtilizationPct": 50,
              "contributingAccountCount": 3,
              "unknownAccountCount": 0,
              "earliestResetsAt": "2026-08-25T03:00:00.000Z"
            },
            "worstAccountUtilizationPct": 100
          },
          "providers": [
            {
              "provider": "anthropic",
              "anyOverload": { "state": "closed", "until": null, "probeActive": false },
              "providerWideOverload": { "state": "closed", "until": null, "probeActive": false },
              "scopedLimits": [
                {
                  "scopeId": "fable",
                  "label": "Fable",
                  "meanUtilizationPct": 70.3,
                  "contributingAccountCount": 2,
                  "unknownAccountCount": 0,
                  "earliestResetsAt": "2026-08-25T03:00:00.000Z"
                }
              ]
            },
            {
              "provider": "codex",
              "anyOverload": { "state": "closed", "until": null, "probeActive": false },
              "providerWideOverload": { "state": "closed", "until": null, "probeActive": false },
              "scopedLimits": []
            }
          ]
        }
        """

    static let accountsJSON = """
        {
          "schema": "clankermux.public.accounts.v1",
          "accounts": [
            {
              "id": "account-a",
              "name": "Account A",
              "provider": "anthropic",
              "isDefaultCandidate": true,
              "availability": { "state": "available", "reason": null, "availableAt": null },
              "credential": { "state": "valid", "expiresAt": "2026-08-24T17:00:00.000Z" },
              "measurementState": "fresh",
              "usageObservedAt": "2026-08-24T11:59:00.000Z",
              "utilizationPct": 90,
              "windows": [
                {
                  "kind": "five_hour", "scopeId": null, "label": "5-hour",
                  "utilizationPct": 90, "observedAt": "2026-08-24T11:59:00.000Z",
                  "resetsAt": "2026-08-24T13:00:00.000Z",
                  "prediction": {
                    "predictedUtilizationAtResetPct": 95,
                    "exhaustsAt": "2026-08-24T13:15:00.000Z",
                    "willExhaustBeforeReset": false,
                    "lowConfidence": false,
                    "state": "rising"
                  }
                },
                {
                  "kind": "seven_day", "scopeId": null, "label": "Weekly",
                  "utilizationPct": 60, "observedAt": "2026-08-24T11:59:00.000Z",
                  "resetsAt": "2026-08-30T07:00:00.000Z", "prediction": null
                },
                {
                  "kind": "weekly_scoped", "scopeId": "fable", "label": "Fable",
                  "utilizationPct": 40, "observedAt": "2026-08-24T11:59:00.000Z",
                  "resetsAt": "2026-08-30T07:00:00.000Z", "prediction": null
                }
              ]
            },
            {
              "id": "account-b",
              "name": "Account B",
              "provider": "anthropic",
              "isDefaultCandidate": false,
              "availability": {
                "state": "rate_limited", "reason": "queueing",
                "availableAt": "2026-08-24T12:30:00.000Z"
              },
              "credential": { "state": "refreshable", "expiresAt": null },
              "measurementState": "stale",
              "usageObservedAt": "2026-08-24T11:20:00.000Z",
              "utilizationPct": 100,
              "windows": [
                {
                  "kind": "five_hour", "scopeId": null, "label": "5-hour",
                  "utilizationPct": 10, "observedAt": "2026-08-24T11:20:00.000Z",
                  "resetsAt": "2026-08-24T14:00:00.000Z",
                  "prediction": {
                    "predictedUtilizationAtResetPct": 100,
                    "exhaustsAt": "2026-08-24T13:45:00.000Z",
                    "willExhaustBeforeReset": true,
                    "lowConfidence": true,
                    "state": "rising"
                  }
                },
                {
                  "kind": "seven_day", "scopeId": null, "label": "Weekly",
                  "utilizationPct": 80, "observedAt": "2026-08-24T11:20:00.000Z",
                  "resetsAt": "2026-08-25T03:00:00.000Z", "prediction": null
                },
                {
                  "kind": "weekly_scoped", "scopeId": "fable", "label": "Fable",
                  "utilizationPct": 100, "observedAt": "2026-08-24T11:20:00.000Z",
                  "resetsAt": "2026-08-25T03:00:00.000Z", "prediction": null
                }
              ]
            },
            {
              "id": "account-c",
              "name": "Account C",
              "provider": "codex",
              "isDefaultCandidate": false,
              "availability": { "state": "available", "reason": null, "availableAt": null },
              "credential": { "state": "not_applicable", "expiresAt": null },
              "measurementState": "fresh",
              "windows": [
                {
                  "kind": "five_hour", "scopeId": null, "label": "5-hour",
                  "utilizationPct": null, "observedAt": "2026-08-24T11:58:00.000Z",
                  "resetsAt": null, "prediction": null
                }
              ]
            }
          ]
        }
        """

    static let runwayJSON = """
        {
          "schema": "clankermux.public.runway.v1",
          "generatedAt": "2026-08-24T12:00:00.000Z",
          "horizonMs": 1209600000,
          "coverage": { "activeKeyCount": 2, "statedKeyCount": 2, "unobservedKeyCount": 0 },
          "worstStatedOutcome": {
            "kind": "runway",
            "exhaustsAt": "2026-08-28T12:00:00.000Z",
            "causes": [{ "accountId": "account-c", "windowKind": "seven_day" }]
          }
        }
        """
}
