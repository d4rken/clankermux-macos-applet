import ClankermuxCore
import Combine
import Foundation

/// The settings keys, matching the Cinnamon applet's `settings-schema.json` one for one.
enum PreferenceKey: String, Sendable, CaseIterable {
    case apiURL = "api-url"
    case refreshInterval = "refresh-interval"
    case requestTimeout = "request-timeout"
    case panelBarWidth = "panel-bar-width"
    case showPanelPercentages = "show-panel-percentages"
    case menuBarContent = "menu-bar-content"
    case runwayWarningHours = "runway-warning-hours"
    case showScopedLimits = "show-scoped-limits"
    case defaultCandidateFirst = "default-candidate-first"
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
    static let panelBarWidthRange = 30...100
    static let runwayWarningHoursRange = 1...336

    static let registrationDefaults: [String: Any] = [
        PreferenceKey.apiURL.rawValue: defaultAPIURL,
        PreferenceKey.refreshInterval.rawValue: 30,
        PreferenceKey.requestTimeout.rawValue: 8,
        PreferenceKey.panelBarWidth.rawValue: 52,
        PreferenceKey.showPanelPercentages.rawValue: true,
        PreferenceKey.menuBarContent.rawValue: PanelDisplay.icon.rawValue,
        PreferenceKey.runwayWarningHours.rawValue: 72,
        PreferenceKey.showScopedLimits.rawValue: true,
        PreferenceKey.defaultCandidateFirst.rawValue: true,
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

    var panelBarWidth: Int {
        get { clamped(.panelBarWidth, to: Self.panelBarWidthRange) }
        set { write(.panelBarWidth, newValue.clamped(to: Self.panelBarWidthRange)) }
    }

    var showPanelPercentages: Bool {
        get { store.bool(forKey: PreferenceKey.showPanelPercentages.rawValue) }
        set { write(.showPanelPercentages, newValue) }
    }

    /// Defaults to the icon. The wider forms need menu bar room that a populated bar may not have,
    /// and macOS draws nothing at all rather than truncating an item that does not fit.
    var menuBarContent: PanelDisplay {
        get {
            PanelDisplay(rawValue: store.string(forKey: PreferenceKey.menuBarContent.rawValue) ?? "")
                ?? .icon
        }
        set { write(.menuBarContent, newValue.rawValue) }
    }

    var runwayWarningHours: Int {
        get { clamped(.runwayWarningHours, to: Self.runwayWarningHoursRange) }
        set { write(.runwayWarningHours, newValue.clamped(to: Self.runwayWarningHoursRange)) }
    }

    var showScopedLimits: Bool {
        get { store.bool(forKey: PreferenceKey.showScopedLimits.rawValue) }
        set { write(.showScopedLimits, newValue) }
    }

    var defaultCandidateFirst: Bool {
        get { store.bool(forKey: PreferenceKey.defaultCandidateFirst.rawValue) }
        set { write(.defaultCandidateFirst, newValue) }
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
