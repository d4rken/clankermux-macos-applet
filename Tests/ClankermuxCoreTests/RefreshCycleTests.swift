import Testing

@testable import ClankermuxCore

@Suite("Refresh cycle")
struct RefreshCycleTests {
    @Test("refresh cycles settle once after every request completes")
    func settlesOnce() {
        var cycle = RefreshCycle(requestCount: 3)
        #expect(cycle.completeOne() == false)
        #expect(cycle.completeOne() == false)
        #expect(cycle.completeOne() == true)
        #expect(cycle.completeOne() == false)
        #expect(cycle.expire() == false)
    }

    @Test("expired refresh cycles ignore late request completions")
    func expiryWins() {
        var cycle = RefreshCycle(requestCount: 3)
        #expect(cycle.completeOne() == false)
        #expect(cycle.expire() == true)
        #expect(cycle.completeOne() == false)
        #expect(cycle.expire() == false)
    }

    @Test("a non-positive request count still settles on the first completion")
    func degenerateCount() {
        var cycle = RefreshCycle(requestCount: 0)
        #expect(cycle.completeOne() == true)
        #expect(cycle.completeOne() == false)
    }
}
