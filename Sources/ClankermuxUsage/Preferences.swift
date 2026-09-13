import ClankermuxCore
import Combine
import Foundation

/// Persisted settings keys, including display preferences specific to macOS.
enum PreferenceKey: String, Sendable, CaseIterable {
    case apiURL = "api-url"
    case refreshInterval = "refresh-interval"
    case requestTimeout = "request-timeout"
    case menuBarContent = "menu-bar-content"
    case showScopedLimits = "show-scoped-limits"
}

/// `UserDefaults`-backed settings.
///
/// Defaults are registered rather than applied as read-time fallbacks, so a never-launched app and
/// a reset app behave identically. Numbers are clamped on read, so a hand-edited `defaults` entry
/// cannot push the poll interval to zero.
@MainActor
final class Preferences: ObservableObject {
    static let defaultAPIURL = "http://127.0.0.1:8080"
    static let refreshIntervalRange = 10...900
    static let requestTimeoutRange = 2...60

    static let defaultMenuBarContent = PanelDisplay.usage

    static let registrationDefaults: [String: Any] = [
        PreferenceKey.apiURL.rawValue: defaultAPIURL,
        PreferenceKey.refreshInterval.rawValue: 30,
        PreferenceKey.requestTimeout.rawValue: 8,
        PreferenceKey.menuBarContent.rawValue: defaultMenuBarContent.rawValue,
        PreferenceKey.showScopedLimits.rawValue: true,
    ]

    /// Emits the key that changed, so the app delegate can tell a reconnect from a redraw.
    let changes = PassthroughSubject<PreferenceKey, Never>()

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        store.register(defaults: Self.registrationDefaults)
    }

    var apiURL: String {
        get { store.string(forKey: PreferenceKey.apiURL.rawValue) ?? Self.defaultAPIURL }
        set { write(.apiURL, newValue) }
    }

    var refreshInterval: Int {
        get { clamped(.refreshInterval, to: Self.refreshIntervalRange) }
        set { write(.refreshInterval, newValue.clamped(to: Self.refreshIntervalRange)) }
    }

    var requestTimeout: Int {
        get { clamped(.requestTimeout, to: Self.requestTimeoutRange) }
        set { write(.requestTimeout, newValue.clamped(to: Self.requestTimeoutRange)) }
    }

    /// Retired values, including the saved "runway" mode, land on whatever the current default is
    /// rather than on a mode of their own, so a removed form never survives as a special case.
    var menuBarContent: PanelDisplay {
        get {
            let saved = store.string(forKey: PreferenceKey.menuBarContent.rawValue) ?? ""
            return PanelDisplay(rawValue: saved) ?? Self.defaultMenuBarContent
        }
        set { write(.menuBarContent, newValue.rawValue) }
    }

    var showScopedLimits: Bool {
        get { store.bool(forKey: PreferenceKey.showScopedLimits.rawValue) }
        set { write(.showScopedLimits, newValue) }
    }

    private func clamped(_ key: PreferenceKey, to range: ClosedRange<Int>) -> Int {
        store.integer(forKey: key.rawValue).clamped(to: range)
    }

    private func write(_ key: PreferenceKey, _ value: Any) {
        objectWillChange.send()
        store.set(value, forKey: key.rawValue)
        changes.send(key)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
