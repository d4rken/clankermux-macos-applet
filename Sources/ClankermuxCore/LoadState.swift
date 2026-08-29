import Foundation

/// Whether an accounts payload has ever been read successfully.
///
/// The distinction is user-visible and must not be flattened to an empty array: `notLoaded` shows
/// the loading or error placeholder, while `loaded([])` shows the normal header plus
/// "No accounts configured".
public enum LoadState: Sendable, Equatable {
    case notLoaded
    case loaded([AccountView])

    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    public var accounts: [AccountView] {
        if case .loaded(let accounts) = self { return accounts }
        return []
    }
}
