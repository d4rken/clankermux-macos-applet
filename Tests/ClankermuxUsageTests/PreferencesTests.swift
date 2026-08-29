import Combine
import Foundation
import Testing

@testable import ClankermuxUsage

@MainActor
@Suite("Preferences")
struct PreferencesTests {

    @Test("registered defaults match the applet's settings schema")
    func registeredDefaults() {
        let store = TemporaryDefaults()
        defer { store.remove() }
        let preferences = Preferences(store: store.defaults)

        #expect(preferences.apiURL == "http://127.0.0.1:8080")
        #expect(preferences.refreshInterval == 30)
        #expect(preferences.requestTimeout == 8)
        #expect(preferences.panelBarWidth == 52)
        #expect(preferences.showPanelPercentages)
        #expect(preferences.runwayWarningHours == 72)
        #expect(preferences.showScopedLimits)
        #expect(preferences.defaultCandidateFirst)
    }

    @Test("every schema key is registered")
    func everyKeyIsRegistered() {
        for key in PreferenceKey.allCases {
            #expect(
                Preferences.registrationDefaults[key.rawValue] != nil,
                "missing registered default for \(key.rawValue)")
        }
    }

    @Test("a hand-edited out-of-range value is clamped on read")
    func clampsOnRead() {
        let store = TemporaryDefaults()
        defer { store.remove() }
        store.defaults.set(0, forKey: PreferenceKey.refreshInterval.rawValue)
        store.defaults.set(9_000, forKey: PreferenceKey.requestTimeout.rawValue)
        store.defaults.set(1, forKey: PreferenceKey.panelBarWidth.rawValue)
        store.defaults.set(-4, forKey: PreferenceKey.runwayWarningHours.rawValue)
        let preferences = Preferences(store: store.defaults)

        #expect(preferences.refreshInterval == 10)
        #expect(preferences.requestTimeout == 60)
        #expect(preferences.panelBarWidth == 30)
        #expect(preferences.runwayWarningHours == 1)
    }

    @Test("writes are clamped before they are stored")
    func clampsOnWrite() {
        let store = TemporaryDefaults()
        defer { store.remove() }
        let preferences = Preferences(store: store.defaults)

        preferences.refreshInterval = 5
        preferences.requestTimeout = 900
        preferences.panelBarWidth = 400
        preferences.runwayWarningHours = 0

        #expect(store.defaults.integer(forKey: PreferenceKey.refreshInterval.rawValue) == 10)
        #expect(store.defaults.integer(forKey: PreferenceKey.requestTimeout.rawValue) == 60)
        #expect(store.defaults.integer(forKey: PreferenceKey.panelBarWidth.rawValue) == 100)
        #expect(store.defaults.integer(forKey: PreferenceKey.runwayWarningHours.rawValue) == 1)
    }

    @Test("values round-trip through the store")
    func roundTrip() {
        let store = TemporaryDefaults()
        defer { store.remove() }
        let preferences = Preferences(store: store.defaults)

        preferences.apiURL = "http://proxy.example.test:8080"
        preferences.showPanelPercentages = false
        preferences.showScopedLimits = false
        preferences.defaultCandidateFirst = false
        preferences.panelBarWidth = 64

        let reopened = Preferences(store: store.defaults)
        #expect(reopened.apiURL == "http://proxy.example.test:8080")
        #expect(!reopened.showPanelPercentages)
        #expect(!reopened.showScopedLimits)
        #expect(!reopened.defaultCandidateFirst)
        #expect(reopened.panelBarWidth == 64)
    }

    @Test("a change publishes the key that changed")
    func publishesChanges() {
        let store = TemporaryDefaults()
        defer { store.remove() }
        let preferences = Preferences(store: store.defaults)

        var observed: [PreferenceKey] = []
        let subscription = preferences.changes.sink { observed.append($0) }
        defer { subscription.cancel() }

        preferences.apiURL = "http://other.test"
        preferences.refreshInterval = 60
        preferences.showScopedLimits = false

        #expect(observed == [.apiURL, .refreshInterval, .showScopedLimits])
    }
}

/// A throwaway `UserDefaults` domain, so a test never touches the user's own settings.
@MainActor
final class TemporaryDefaults {
    let suiteName = "eu.darken.clankermux-usage.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create a temporary defaults suite")
        }
        self.defaults = defaults
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
