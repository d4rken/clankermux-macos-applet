import Foundation
import Testing

@testable import ClankermuxCore

/// `workloadRow` and `forecastSummary` both qualify a limited weekly forecast, and the second
/// condition is a strict subset of the first, so the popover line can only say it once.
@Suite("Limited evidence qualification")
struct LimitedSummaryTests {
    @Test("a limited weekly forecast qualifies the summary line exactly once")
    func limitedIsQualifiedOnce() throws {
        var weekly = Fixtures.weekly()
        weekly.quality = "limited"
        let payload = WorkloadsResponse(
            schema: "clankermux.public.workloads.v1", generatedAt: Fixtures.timestamp(),
            workloads: [
                Workload(
                    id: "class:anthropic", label: "Claude",
                    availability: WorkloadAvailability(
                        computedAt: Fixtures.timestamp(), context: "fresh_unpinned_nominal",
                        availableAccounts: 2, constrainedAccounts: 1, unknownAccounts: 0),
                    weekly: weekly)
            ])

        let view = UsageModel.buildView(
            accounts: nil, workloads: payload, localNow: Fixtures.now)
        let row = try #require(view.workloads.first)

        // Guards against a vacuous test: the second qualification's condition really is met.
        #expect(row.limited)

        let occurrences = row.summaryLine.components(separatedBy: "limited").count - 1
        #expect(occurrences == 1, "qualified \(occurrences)x: \(row.summaryLine)")
    }
}
