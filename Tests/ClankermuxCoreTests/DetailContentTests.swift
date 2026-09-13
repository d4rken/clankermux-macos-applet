import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Detail content")
struct DetailContentTests {
    private func make(_ snapshot: RefreshSnapshot) -> DetailContent {
        DetailContent.make(
            snapshot: snapshot, view: snapshot.rendered(options: ViewOptions(), now: Fixtures.now),
            now: Fixtures.now)
    }

    @Test("workload and account details remain independent")
    func partialSuccess() {
        let accountsOnly = make(Fixtures.snapshot(workloads: nil, workloadsError: "HTTP 404"))
        #expect(accountsOnly.accounts.count == 3)
        #expect(accountsOnly.placeholder == nil)
        #expect(accountsOnly.notices.contains { $0.title == "Workloads unavailable" })
        let workloadsOnly = make(
            Fixtures.snapshot(accounts: nil, accountsError: "Connection failed"))
        #expect(workloadsOnly.workloads.count == 3)
        #expect(workloadsOnly.placeholder == nil)
        #expect(workloadsOnly.notices.contains { $0.title == "Accounts unavailable" })
    }

    @Test("a forecast fetch failure shows cache age and keeps the last reading")
    func cached() {
        let detail = make(Fixtures.snapshot(workloadsError: "HTTP 503"))
        #expect(detail.workloads[0].signal.value == "Stale")
        #expect(
            detail.notices.contains {
                $0.title == "Workloads cached" && $0.subtitle.contains("Last success:")
            })
    }

    @Test("the summary drops providers whose accounts are all paused")
    func pausedProvidersAreNotSummarized() {
        var accounts = Fixtures.accounts()
        for index in accounts.indices where accounts[index].provider == "anthropic" {
            accounts[index].availability?.state = "paused"
        }
        let paused = make(Fixtures.snapshot(accounts: accounts))
        #expect(!paused.workloads.contains { $0.label == "Claude" })
        // The account blocks are a different question: a paused account still has a heading and a
        // state to report, and hiding it there would look like the account had been removed.
        #expect(paused.accounts.count == make(Fixtures.snapshot()).accounts.count)

        // A stale or failed account list must not empty the summary.
        let unknown = make(Fixtures.snapshot(accounts: accounts, accountsError: "offline"))
        #expect(unknown.workloads.contains { $0.label == "Claude" })
    }

    @Test("successful empty accounts differ from loading")
    func emptyAccounts() {
        let loaded = make(Fixtures.snapshot(accounts: []))
        #expect(loaded.notices.contains { $0.title == "No accounts configured" })
        let loading = make(.loading(baseURL: "http://localhost:8080"))
        #expect(loading.placeholder?.title == "Loading usage…")
        #expect(!loading.notices.contains { $0.title == "No accounts configured" })
    }
}
