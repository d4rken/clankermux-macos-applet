import AppKit
import ClankermuxCore
import SwiftUI

/// The live connection row: a severity dot, a status word, and what the last poll reported.
struct ConnectionStatusView: View {
    @ObservedObject var connection: ConnectionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(connection.state.severity.accent).frame(width: 7, height: 7)
                Text(connection.state.word).font(.system(size: 12, weight: .semibold))
            }
            if !connection.detail.isEmpty {
                Text(connection.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection \(connection.state.word). \(connection.detail)")
    }
}

/// The settings form, in the same groups as the Cinnamon `settings-schema.json`.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var connection: ConnectionStatus

    /// The URL is edited locally and committed on Return or on leaving the field. Writing it per
    /// keystroke would reconnect on every character, dropping the cached data and polling
    /// half-typed hostnames.
    @State private var apiURLDraft: String
    @FocusState private var apiURLFocused: Bool

    init(preferences: Preferences, connection: ConnectionStatus) {
        self.preferences = preferences
        self.connection = connection
        _apiURLDraft = State(initialValue: preferences.apiURL)
    }

    var body: some View {
        Form {
            Section("Clankermux API") {
                TextField("Server URL (hostname or IP address)", text: $apiURLDraft)
                    .focused($apiURLFocused)
                    .onSubmit { commitAPIURL() }
                    .onChange(of: apiURLFocused) { focused in
                        if !focused { commitAPIURL() }
                    }
                    .onChange(of: preferences.apiURL) { url in
                        if !apiURLFocused { apiURLDraft = url }
                    }
                    .help(
                        "Base URL of Clankermux's public widget API, for example http://127.0.0.1:8080 or http://clankermux.example.test:8080"
                    )
                if let problem = Formatting.baseUrlProblem(apiURLDraft) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ConnectionStatusView(connection: connection)
                Text(
                    "The app reads Clankermux's unauthenticated, read-only status, accounts and workloads endpoints. Hostnames and IP addresses are both accepted; a missing http:// is filled in. The address applies when you press Return or leave the field."
                )
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Polling") {
                Stepper(
                    "Refresh accounts and status every \(preferences.refreshInterval) seconds",
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

            Section("Menu bar") {
                Picker(
                    "Menu bar shows",
                    selection: Binding(
                        get: { preferences.menuBarContent },
                        set: { preferences.menuBarContent = $0 })
                ) {
                    Text("Stacked pace bars").tag(PanelDisplay.compact)
                    Text("Weekly usage").tag(PanelDisplay.usage)
                }
                .help(
                    "Stacked pace bars show the server's guidance until the next weekly reset in the narrowest form. Weekly usage averages each provider's weekly percentages with equal weight per account, and needs more room; macOS may hide a status item that does not fit. The popover always shows full detail."
                )
            }

            Section("Popup") {
                Toggle(
                    "Show model-family indicators and utilization bars",
                    isOn: Binding(
                        get: { preferences.showScopedLimits },
                        set: { preferences.showScopedLimits = $0 })
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 460)
    }

    private func commitAPIURL() {
        guard apiURLDraft != preferences.apiURL else { return }
        preferences.apiURL = apiURLDraft
    }
}

/// Hosts the settings form in a plain window.
///
/// An `.accessory` app has no application menu, so the SwiftUI `Settings` scene would have nothing
/// to open it from.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let connection: ConnectionStatus
    private var window: NSWindow?

    init(preferences: Preferences, connection: ConnectionStatus) {
        self.preferences = preferences
        self.connection = connection
        super.init()
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
            window.contentView = NSHostingView(
                rootView: SettingsView(preferences: preferences, connection: connection))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// AppKit keeps a text field's field editor as first responder across a close, so closing the
    /// window would otherwise produce no focus change and drop an uncommitted URL edit. Ending
    /// editing here runs the field's commit-on-focus-loss path while the window is still open.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        endEditing(in: sender)
        return true
    }

    /// The same problem as closing, reached a different way. Clicking the menu bar item or another
    /// application leaves the field focused, so without this a typed URL is silently discarded and
    /// the app keeps polling the previous server, which looks exactly like the new address being
    /// rejected.
    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        endEditing(in: window)
    }

    /// Drops first responder, which is what drives the form's commit-on-focus-loss path.
    func endEditing(in window: NSWindow) {
        window.makeFirstResponder(nil)
    }
}
