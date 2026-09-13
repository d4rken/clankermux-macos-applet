import AppKit
import ClankermuxCore
import Testing

@testable import ClankermuxUsage

/// The settings URL commits when the field stops being first responder. Every way of leaving the
/// window therefore has to drop first responder, or the typed address is silently discarded and the
/// app keeps polling the previous server, which is indistinguishable from the new address being
/// rejected.
@MainActor
@Suite("Settings window")
struct SettingsWindowControllerTests {

    @Test("closing the window ends editing")
    func closingEndsEditing() {
        let (window, field) = windowWithFocusedField()
        let controller = SettingsWindowController(
            preferences: Preferences(store: .standard), connection: ConnectionStatus())

        // Guards against a vacuous test: the field must actually own editing beforehand.
        #expect(isEditing(window, field))
        _ = controller.windowShouldClose(window)

        #expect(!isEditing(window, field))
    }

    @Test("losing key status ends editing, so clicking away does not discard the edit")
    func resigningKeyEndsEditing() {
        let (window, field) = windowWithFocusedField()
        let controller = SettingsWindowController(
            preferences: Preferences(store: .standard), connection: ConnectionStatus())

        #expect(isEditing(window, field))
        controller.windowDidResignKey(
            Notification(name: NSWindow.didResignKeyNotification, object: window))

        #expect(!isEditing(window, field))
    }

    @Test("the address the app accepts is the address the field accepts")
    func validAddresses() {
        for draft in [
            "http://127.0.0.1:8080", "https://clankermux.example.test",
            "clankermux.example.test:8080", "127.0.0.1:8080", "  http://host:8080/  ",
            "HTTP://Host:8080", "http://host:8080/prefix",
        ] {
            #expect(Formatting.baseUrlProblem(draft) == nil, "rejected \(draft)")
        }
    }

    @Test("an empty, non-HTTP or unparseable address is rejected before it is saved")
    func rejectedAddresses() {
        #expect(Formatting.baseUrlProblem("") != nil)
        #expect(Formatting.baseUrlProblem("   ") != nil)
        #expect(Formatting.baseUrlProblem("ftp://host:8080") != nil)
        #expect(Formatting.baseUrlProblem("file:///tmp") != nil)
        #expect(Formatting.baseUrlProblem("ws://host") != nil)
        #expect(Formatting.baseUrlProblem("http://") != nil)
        #expect(Formatting.baseUrlProblem("http:// spaced host") != nil)
    }

    /// The endpoint path is concatenated onto the saved address, so a fragment swallows the whole
    /// request path rather than merely looking untidy.
    @Test("a query or fragment is rejected because the endpoint path is appended to the address")
    func rejectsQueryAndFragment() {
        #expect(Formatting.baseUrlProblem("https://server/#section") != nil)
        #expect(Formatting.baseUrlProblem("https://server/?token=abc") != nil)

        let base = Formatting.normalizeBaseUrl("https://server/#section")
        let request = URL(string: base + "/public/v1/accounts")
        #expect(request?.path == "/")
        #expect(request?.fragment == "section/public/v1/accounts")
    }

    // MARK: - Helpers

    /// True while the field still owns editing, whether directly or through its field editor.
    private func isEditing(_ window: NSWindow, _ field: NSTextField) -> Bool {
        let responder = window.firstResponder
        if responder === field { return true }
        if let text = responder as? NSTextView, text.delegate === field { return true }
        return false
    }

    private func windowWithFocusedField() -> (NSWindow, NSTextField) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let field = NSTextField(string: "http://example.test:8080")
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        return (window, field)
    }
}
