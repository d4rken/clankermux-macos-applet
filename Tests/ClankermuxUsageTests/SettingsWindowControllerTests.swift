import AppKit
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
        let controller = SettingsWindowController(preferences: Preferences(store: .standard))

        // Guards against a vacuous test: the field must actually own editing beforehand.
        #expect(isEditing(window, field))
        _ = controller.windowShouldClose(window)

        #expect(!isEditing(window, field))
    }

    @Test("losing key status ends editing, so clicking away does not discard the edit")
    func resigningKeyEndsEditing() {
        let (window, field) = windowWithFocusedField()
        let controller = SettingsWindowController(preferences: Preferences(store: .standard))

        #expect(isEditing(window, field))
        controller.windowDidResignKey(
            Notification(name: NSWindow.didResignKeyNotification, object: window))

        #expect(!isEditing(window, field))
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
