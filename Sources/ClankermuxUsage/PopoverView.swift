import ClankermuxCore
import SwiftUI

@MainActor
final class PopoverModel: ObservableObject {
    @Published var content: DetailContent
    @Published var isRefreshing: Bool
    @Published var canOpenDashboard: Bool
    /// Set from the screen the status item sits on, so scrolling begins only when the content
    /// genuinely exceeds the display.
    @Published var maxContentHeight: CGFloat

    init(
        content: DetailContent,
        isRefreshing: Bool,
        canOpenDashboard: Bool,
        maxContentHeight: CGFloat = PopoverMetrics.maxHeight(screenVisibleHeight: 900)
    ) {
        self.content = content
        self.isRefreshing = isRefreshing
        self.canOpenDashboard = canOpenDashboard
        self.maxContentHeight = maxContentHeight
    }
}

// MARK: - Pieces

struct UsageBar: View {
    let percent: Int
    let severity: Severity

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(severity.accent)
                    .frame(
                        width: percent <= 0
                            ? 0 : max(3, geometry.size.width * CGFloat(percent) / 100))
            }
        }
    }
}

/// The rounded container the popover's sections sit in, so the eye groups them without needing a
/// divider between every block.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.35)))
    }
}

struct InfoBlockView: View {
    let block: InfoBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(block.style.titleColor)
            if !block.subtitle.isEmpty {
                Text(block.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(block.style.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A provider mark, or the workload's initial where the running system cannot decode the mark.
struct ProviderMarkView: View {
    let mark: ProviderMark?
    let fallback: String

    var body: some View {
        Group {
            if let mark, let image = ProviderMarks.image(for: mark) {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Text(fallback).font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(width: ProviderMarks.side, height: ProviderMarks.side)
    }
}

/// Every workload on one line: what the weekly budget is doing on the left, how many accounts can
/// serve a request right now on the right.
struct WorkloadSummaryView: View {
    let rows: [WorkloadRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Weekly until next reset").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text("Available now").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    ProviderMarkView(
                        mark: WorkloadRegistry.mark(forKey: row.id),
                        fallback: String(row.label.prefix(1)).uppercased()
                    )
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }
                    Text(row.summaryLine).font(.system(size: 10.5, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // Deliberately uncoloured: this counts accounts that can serve a request now,
                    // which the weekly pace severity beside it says nothing about.
                    Text(row.availabilityCount)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.summaryLine). Available now \(row.availabilityCount)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AccountBlockView: View {
    let block: AccountBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(block.name).font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).help(block.name)
                Circle().fill(block.stateKey.accent).frame(width: 5, height: 5)
                Text(block.stateText).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(block.provider).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if block.stateKey != .paused {
                if let emptyText = block.emptyText {
                    Text(emptyText).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                ForEach(block.windows) { window in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(window.label).font(.system(size: 10.5)).italic(window.scoped)
                            .frame(width: 52, alignment: .leading)
                        UsageBar(percent: window.percent ?? 0, severity: window.severity)
                            .frame(width: 84, height: 5)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center]
                            }
                        Text(window.percent.map { "\($0)%" } ?? "–")
                            .font(.system(size: 10.5).monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                        Text(window.forecastText).font(.system(size: 10)).foregroundStyle(
                            .secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(window.resetText).font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(width: 75, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Popover

/// Carries the measured height of the popover's sections up to the container.
private struct ContentHeightKey: SwiftUI.PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    /// Measured height of the sections, used to decide whether a scroll view is needed at all.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only wrap in a ScrollView when the content genuinely will not fit. macOS shows a
            // persistent scroller whenever a mouse is attached, so a ScrollView that is never
            // scrolled still draws a bar, which is the thing this is meant to avoid.
            if contentHeight > model.maxContentHeight {
                ScrollView { sections }
                    .frame(height: model.maxContentHeight)
            } else {
                sections
            }

            Divider()

            footer
        }
        .frame(width: PopoverMetrics.width)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let placeholder = model.content.placeholder {
                InfoBlockView(block: placeholder)
            }
            if let header = model.content.header {
                InfoBlockView(block: header).padding(.horizontal, 2)
            }
            if !model.content.workloads.isEmpty {
                Card { WorkloadSummaryView(rows: model.content.workloads) }
            }
            ForEach(model.content.notices) { notice in
                Card { InfoBlockView(block: notice) }
            }
            ForEach(model.content.accounts) { account in
                Card { AccountBlockView(block: account) }
            }
        }
        .padding(10)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            // The measurement is of the sections themselves, identical in both branches, so
            // switching between them cannot feed back into the measurement and oscillate.
            if height != contentHeight { contentHeight = height }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button(action: onRefresh) {
                Label(
                    model.isRefreshing ? "Refreshing…" : "Refresh",
                    systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)

            Spacer(minLength: 8)

            iconButton("safari", help: "Open dashboard", action: onOpenDashboard)
                .disabled(!model.canOpenDashboard)
            iconButton("gearshape", help: "Settings", action: onOpenSettings)
            // An agent app has no Dock icon and no application menu, so quitting needs an
            // explicit control.
            iconButton("power", help: "Quit Clankermux Usage", action: onQuit)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 18, height: 16)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
