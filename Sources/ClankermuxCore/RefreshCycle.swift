import Foundation

/// Tracks the requests of one refresh so the cycle settles exactly once.
///
/// `completeOne()` returns true only on the call that drops the outstanding count to zero, and
/// `expire()` returns true only if it settles the cycle first. Every later call returns false, so a
/// late reply cannot re-run the work an expiry already did.
public struct RefreshCycle: Sendable, Equatable {
    private var remaining: Int
    private var settled = false

    public init(requestCount: Int = 1) {
        remaining = requestCount > 0 ? requestCount : 1
    }

    public mutating func completeOne() -> Bool {
        if settled { return false }
        remaining -= 1
        if remaining > 0 { return false }
        settled = true
        return true
    }

    public mutating func expire() -> Bool {
        if settled { return false }
        settled = true
        return true
    }
}
