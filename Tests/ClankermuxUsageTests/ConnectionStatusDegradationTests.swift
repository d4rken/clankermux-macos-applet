import Foundation
import Testing

@testable import ClankermuxCore
@testable import ClankermuxUsage

/// A cycle where `/accounts` and `/workloads` answered but `/status` failed still has readings on
/// screen, so the settings window has to call that degraded rather than unavailable.
@MainActor
@Suite("Connection status degradation")
struct ConnectionStatusDegradationTests {
    @Test("a status-only failure alongside usable readings is degraded, not failed")
    func statusFailureWithReadingsIsDegraded() {
        let base = UIFixtures.snapshot()
        let snapshot = RefreshSnapshot(
            baseURL: base.baseURL, accounts: base.accounts, status: nil,
            workloads: base.workloads,
            accountsReceivedAt: base.accountsReceivedAt, statusReceivedAt: nil,
            workloadsReceivedAt: base.workloadsReceivedAt,
            lastSuccess: nil,
            lastAccountsError: "", lastStatusError: "status: request timed out",
            lastWorkloadsError: "", isRefreshing: false)

        // Guards against a vacuous test: the readings the popover draws are present.
        #expect(snapshot.accounts?.isEmpty == false)
        #expect(snapshot.workloads?.workloads?.isEmpty == false)

        let connection = ConnectionStatus()
        connection.update(snapshot, now: Date())

        #expect(
            connection.state == .degraded,
            "status-only failure reported as \(connection.state.rawValue)")
    }
}
