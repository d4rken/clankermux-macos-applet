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
            .padding(.vertical, 7)
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

/// The runway headline, given the visual weight it has in the menu bar.
struct RunwayHeadlineView: View {
    let block: InfoBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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

struct PoolSummaryView: View {
    let block: PoolSummaryBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(block.title).font(.system(size: 11, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 7, verticalSpacing: 4) {
                ForEach(block.rows) { row in
                    GridRow {
                        Text(row.label)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 52, alignment: .leading)
                        UsageBar(percent: row.usedPercent, severity: row.severity)
                            .frame(width: 116, height: 5)
                        Text("\(row.usedPercent)%")
                            .font(.system(size: 11).monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                        Text(row.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Text(block.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AccountBlockView: View {
    let block: AccountBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(block.name).font(.system(size: 12, weight: .semibold))
                if block.isDefaultCandidate {
                    Text("DEFAULT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(nsColor: .systemGreen).opacity(0.15))
                        )
                }
                Spacer(minLength: 4)
                Text(block.provider)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Circle().fill(block.stateKey.accent).frame(width: 5, height: 5)
                Text(block.stateText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let emptyText = block.emptyText {
                Text(emptyText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 7, verticalSpacing: 3) {
                    ForEach(block.windows) { window in
                        GridRow {
                            Text(window.label)
                                .font(.system(size: 10.5))
                                .italic(window.scoped)
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                            UsageBar(percent: window.percent, severity: window.severity)
                                .frame(width: 84, height: 5)
                            Text(window.percentText)
                                .font(.system(size: 10.5).monospacedDigit())
                                .frame(width: 32, alignment: .trailing)
                            Text(window.forecastText)
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(window.severity.accent)
                                .frame(width: 38, alignment: .leading)
                            Text(window.resetText)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    if let placeholder = model.content.placeholder {
                        InfoBlockView(block: placeholder)
                    }
                    if let runway = model.content.runway {
                        Card { RunwayHeadlineView(block: runway) }
                    }
                    if let header = model.content.header {
                        InfoBlockView(block: header)
                            .padding(.horizontal, 2)
                    }
                    ForEach(model.content.overloads) { overload in
                        Card { InfoBlockView(block: overload) }
                    }
                    if let pools = model.content.pools {
                        Card { PoolSummaryView(block: pools) }
                    }
                    ForEach(model.content.accounts) { account in
                        Card { AccountBlockView(block: account) }
                    }
                    if let notice = model.content.emptyAccountsNotice {
                        InfoBlockView(block: notice)
                    }
                    if let error = model.content.errorNotice {
                        Card { InfoBlockView(block: error) }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: model.maxContentHeight)

            Divider()

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
        .frame(width: PopoverMetrics.width)
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
