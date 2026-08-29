import AppKit
import SwiftUI

/// The settings form, in the same two groups as the Cinnamon `settings-schema.json`.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Clankermux API") {
                TextField(
                    "Server URL (hostname or IP address)",
                    text: Binding(
                        get: { preferences.apiURL }, set: { preferences.apiURL = $0 })
                )
                .help(
                    "Base URL of Clankermux's public widget API, for example http://127.0.0.1:8080 or http://clankermux.example.test:8080"
                )
                Text(
                    "The app reads Clankermux's unauthenticated, read-only /public/v1 status, accounts, and runway endpoints. Enter a complete HTTP or HTTPS URL above; hostnames and IP addresses are both supported."
                )
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Polling") {
                Stepper(
                    "Refresh every \(preferences.refreshInterval) seconds",
                    value: Binding(
                        get: { preferences.refreshInterval },
                        set: { preferences.refreshInterval = $0 }),
                    in: Preferences.refreshIntervalRange,
                    step: 10
                )
                Stepper(
                    "Request timeout \(preferences.requestTimeout) seconds",
                    value: Binding(
                        get: { preferences.requestTimeout },
                        set: { preferences.requestTimeout = $0 }),
                    in: Preferences.requestTimeoutRange,
                    step: 1
                )
            }

            Section("Panel") {
                Stepper(
                    "Width of each panel progress bar: \(preferences.panelBarWidth) points",
                    value: Binding(
                        get: { preferences.panelBarWidth },
                        set: { preferences.panelBarWidth = $0 }),
                    in: Preferences.panelBarWidthRange,
                    step: 2
                )
                Toggle(
                    "Show percentages beside panel bars",
                    isOn: Binding(
                        get: { preferences.showPanelPercentages },
                        set: { preferences.showPanelPercentages = $0 })
                )
                Stepper(
                    "Warn when quota runway falls below \(preferences.runwayWarningHours) hours",
                    value: Binding(
                        get: { preferences.runwayWarningHours },
                        set: { preferences.runwayWarningHours = $0 }),
                    in: Preferences.runwayWarningHoursRange,
                    step: 1
                )
                .help(
                    "The panel runway turns orange below this duration. It turns red when the pool is out of quota."
                )
            }

            Section("Popup") {
                Toggle(
                    "Show model-specific limits in the panel and popup",
                    isOn: Binding(
                        get: { preferences.showScopedLimits },
                        set: { preferences.showScopedLimits = $0 })
                )
                Toggle(
                    "Put the default routing candidate first",
                    isOn: Binding(
                        get: { preferences.defaultCandidateFirst },
                        set: { preferences.defaultCandidateFirst = $0 })
                )
                .help(
                    "This is the account selected for a fresh, unpinned, nominal-sized request; pinned and affinity-routed requests may choose differently."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 460)
    }
}

/// Hosts the settings form in a plain window.
///
/// An `.accessory` app has no application menu, so the SwiftUI `Settings` scene would have nothing
/// to open it from.
@MainActor
final class SettingsWindowController {
    private let preferences: Preferences
    private var window: NSWindow?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Clankermux Usage Settings"
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
