import AppKit
import ClankermuxCore
import Combine
import SwiftUI

/// Owns the status item, the popover, the single refresh coordinator and the poll timer.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences: Preferences
    private let scheduler: any PollScheduling
    private let coordinator: RefreshCoordinator
    private let connection: ConnectionStatus
    private let settingsWindow: SettingsWindowController

    private var statusItem: NSStatusItem?
    private var panelView: PanelItemView?
    private let popover = NSPopover()
    private var popoverModel: PopoverModel?
    private var cancellables = Set<AnyCancellable>()
    private var latestSnapshot: RefreshSnapshot?
    private let displayScheduler = PollScheduler()
    private var connectionChange: Task<Void, Never>?

    /// Set only when the popover closes because of a mouse-down on the status button, and consumed
    /// by the mouse-up that follows it, so that one click does not close and reopen the popover.
    /// Any other dismissal, such as Escape or a click elsewhere, leaves it false and the next click
    /// on the button opens the popover again.
    private var suppressNextStatusOpen = false

    /// A click that opens the popover refreshes only if the data is older than this.
    private static let openRefreshThreshold: TimeInterval = 15

    override init() {
        let preferences = Preferences()
        let connection = ConnectionStatus()
        let timeout = TimeInterval(preferences.requestTimeout)
        self.preferences = preferences
        self.connection = connection
        self.scheduler = PollScheduler()
        self.settingsWindow = SettingsWindowController(
            preferences: preferences, connection: connection)
        self.coordinator = RefreshCoordinator(
            client: URLSessionApiClient(requestTimeout: timeout),
            baseURL: preferences.apiURL,
            requestTimeout: timeout
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let now = Date()
        let snapshot = RefreshSnapshot.loading(baseURL: preferences.apiURL)
        let view = snapshot.rendered(options: viewOptions(), now: now)
        let panel = PanelContent.make(
            snapshot: snapshot, view: view, display: preferences.menuBarContent,
            showScoped: preferences.showScopedLimits, now: now)
        let detail = DetailContent.make(snapshot: snapshot, view: view, now: now)

        let panelView = PanelItemView(content: panel)
        self.panelView = panelView

        let statusItem = NSStatusBar.system.statusItem(withLength: panelView.fittingWidth)
        if let button = statusItem.button {
            panelView.frame = button.bounds
            panelView.autoresizingMask = [.width, .height]
            button.addSubview(panelView)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.toolTip = panel.tooltip
        }
        self.statusItem = statusItem

        let popoverModel = PopoverModel(
            content: detail,
            isRefreshing: false,
            canOpenDashboard: !Formatting.normalizeBaseUrl(preferences.apiURL).isEmpty
        )
        self.popoverModel = popoverModel
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: popoverModel,
                onRefresh: { [weak self] in self?.refreshNow() },
                onOpenDashboard: { [weak self] in self?.openDashboard() },
                onOpenSettings: { [weak self] in self?.settingsWindow.show() },
                onQuit: { NSApp.terminate(nil) }
            )
        )

        preferences.changes
            .sink { key in
                Task { @MainActor [weak self] in self?.handle(key) }
            }
            .store(in: &cancellables)

        scheduler.schedule(intervalSeconds: TimeInterval(preferences.refreshInterval)) {
            [weak self] in
            guard let self else { return }
            Task { await self.coordinator.refresh() }
        }

        displayScheduler.schedule(intervalSeconds: 1) { [weak self] in
            guard let self else { return }
            if let latestSnapshot = self.latestSnapshot { self.render(latestSnapshot) }
            Task { await self.coordinator.refresh(workloadsOnly: true) }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.setHandlers(
                started: { [weak self] snapshot in await self?.render(snapshot) },
                finished: { [weak self] snapshot in await self?.render(snapshot) }
            )
            await self.coordinator.refresh(forceWorkloads: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler.cancel()
        displayScheduler.cancel()
    }

    // MARK: - Rendering

    private func viewOptions() -> ViewOptions {
        ViewOptions(showScoped: preferences.showScopedLimits)
    }

    private func render(_ snapshot: RefreshSnapshot) {
        latestSnapshot = snapshot
        let now = Date()
        let rendered = snapshot.rendered(options: viewOptions(), now: now)

        let panel = PanelContent.make(
            snapshot: snapshot, view: rendered, display: preferences.menuBarContent,
            showScoped: preferences.showScopedLimits, now: now)
        panelView?.update(content: panel)
        if let panelView {
            statusItem?.length = panelView.fittingWidth
        }
        statusItem?.button?.toolTip = panel.tooltip
        statusItem?.button?.setAccessibilityLabel(Self.accessibilityLabel(panel))

        let detail = DetailContent.make(snapshot: snapshot, view: rendered, now: now)
        if popoverModel?.content != detail { popoverModel?.content = detail }
        if popoverModel?.isRefreshing != snapshot.isRefreshing {
            popoverModel?.isRefreshing = snapshot.isRefreshing
        }
        popoverModel?.canOpenDashboard = !Formatting.normalizeBaseUrl(preferences.apiURL).isEmpty
        connection.update(snapshot, now: now)
    }

    private static func accessibilityLabel(_ content: PanelContent) -> String {
        "Clankermux usage, \(content.severity.rawValue). Open workload details."
    }

    // MARK: - Settings

    private func handle(_ key: PreferenceKey) {
        switch key {
        case .apiURL, .requestTimeout:
            // Reconfigured rather than rebuilt, so a slow reply from the previous server URL
            // cannot outlive the change and be applied afterwards.
            let baseURL = preferences.apiURL
            let timeout = TimeInterval(preferences.requestTimeout)
            // The reconfigurations are chained, because separately created tasks reach the
            // coordinator in arrival order, so an older URL could be applied after a newer one and
            // leave the app polling the wrong server.
            let previous = connectionChange
            let change = Task { [coordinator] in
                await previous?.value
                await coordinator.reconfigure(baseURL: baseURL, timeout: timeout)
            }
            connectionChange = change
            // The refresh runs outside that chain, so a change made while an earlier refresh is
            // still waiting on a slow server applies immediately instead of after that timeout.
            // The coordinator discards the older refresh once the newer reconfiguration lands.
            Task { [coordinator] in
                await change.value
                await coordinator.refresh(forceWorkloads: true)
            }
        case .refreshInterval:
            scheduler.reschedule(intervalSeconds: TimeInterval(preferences.refreshInterval))
        case .menuBarContent, .showScopedLimits:
            if let latestSnapshot { render(latestSnapshot) }
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if suppressNextStatusOpen {
            suppressNextStatusOpen = false
            return
        }
        guard let button = statusItem?.button else { return }
        // Cap the popover to the screen it will actually appear on, so it scrolls only when the
        // content will not fit that display rather than at a fixed threshold.
        popoverModel?.maxContentHeight = PopoverMetrics.maxHeight(
            screenVisibleHeight: (button.window?.screen ?? NSScreen.main)?.visibleFrame.height
                ?? PopoverMetrics.minimumHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)

        let lastSuccess = latestSnapshot?.lastSuccess
        let stale =
            lastSuccess.map { Date().timeIntervalSince($0) > Self.openRefreshThreshold } ?? true
        if stale {
            Task { [coordinator] in await coordinator.refresh() }
        }
    }

    /// Runs before the close animation, unlike `popoverDidClose`, so the flag is already set when
    /// the button's action fires on the mouse-up of the very click that dismissed the popover.
    func popoverWillClose(_ notification: Notification) {
        suppressNextStatusOpen = Self.isStatusButtonMouseDown(
            NSApp.currentEvent, button: statusItem?.button)
    }

    private static func isStatusButtonMouseDown(_ event: NSEvent?, button: NSStatusBarButton?)
        -> Bool
    {
        guard let event, let button, event.type == .leftMouseDown, event.window === button.window
        else { return false }
        return button.bounds.contains(button.convert(event.locationInWindow, from: nil))
    }

    private func refreshNow() {
        Task { [coordinator] in await coordinator.refresh(forceWorkloads: true) }
    }

    private func openDashboard() {
        let url = Formatting.normalizeBaseUrl(preferences.apiURL)
        guard !url.isEmpty, let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }
}

enum ConnectionState: String, Sendable, Equatable {
    case connecting, connected, degraded, failed

    var word: String {
        switch self {
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .degraded: return "Degraded"
        case .failed: return "Unavailable"
        }
    }

    var severity: Severity {
        switch self {
        case .connecting: return .unknown
        case .connected: return .normal
        case .degraded: return .warning
        case .failed: return .critical
        }
    }
}

/// What the settings window reports about the server it is pointed at.
///
/// Derived from the ordinary poll results, so the settings window needs no request path of its own
/// and cannot disagree with what the menu bar is showing.
@MainActor
final class ConnectionStatus: ObservableObject {
    @Published private(set) var state: ConnectionState = .connecting
    @Published private(set) var detail: String = ""

    func update(_ snapshot: RefreshSnapshot, now: Date) {
        let errors = [
            snapshot.lastAccountsError, snapshot.lastStatusError, snapshot.lastWorkloadsError,
        ].filter { !$0.isEmpty }
        let read = snapshot.lastSuccess != nil
        let state: ConnectionState =
            errors.isEmpty ? (read ? .connected : .connecting) : (read ? .degraded : .failed)

        var lines: [String] = []
        if state == .connected {
            var service =
                "Service \(Formatting.humanizeStatus(snapshot.status?.serviceState).lowercased())"
            let version = (snapshot.status?.version ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines)
            if !version.isEmpty { service += " · version \(version)" }
            lines.append(service)
        } else if !errors.isEmpty {
            lines.append(errors.joined(separator: " · "))
        }
        lines.append(DetailContent.lastRefreshText(lastSuccess: snapshot.lastSuccess, now: now))

        let detail = lines.joined(separator: "\n")
        if self.state != state { self.state = state }
        if self.detail != detail { self.detail = detail }
    }
}
