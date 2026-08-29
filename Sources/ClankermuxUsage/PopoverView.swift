import ClankermuxCore
import SwiftUI

@MainActor
final class PopoverModel: ObservableObject {
    @Published var content: DetailContent
    @Published var isRefreshing: Bool
    @Published var canOpenDashboard: Bool

    init(content: DetailContent, isRefreshing: Bool, canOpenDashboard: Bool) {
        self.content = content
        self.isRefreshing = isRefreshing
        self.canOpenDashboard = canOpenDashboard
    }
}

struct UsageBar: View {
    let percent: Int
    let severity: Severity

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .tertiaryLabelColor))
                RoundedRectangle(cornerRadius: 4)
                    .fill(severity.accent)
                    .frame(
                        width: percent <= 0
                            ? 0 : max(2, geometry.size.width * CGFloat(percent) / 100))
            }
        }
    }
}

struct InfoBlockView: View {
    let block: InfoBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(block.style.titleColor)
            if !block.subtitle.isEmpty {
                Text(block.subtitle)
                    .font(.system(size: 11))
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
            Text(block.title).font(.system(size: 13, weight: .bold))
            Text(block.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                ForEach(block.rows) { row in
                    GridRow {
                        Text(row.label)
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 66, alignment: .leading)
                        UsageBar(percent: row.usedPercent, severity: row.severity)
                            .frame(width: 170, height: 7)
                        Text("\(row.usedPercent)%")
                            .font(.system(size: 12))
                            .frame(width: 40, alignment: .trailing)
                        Text(row.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AccountBlockView: View {
    let block: AccountBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(block.name).font(.system(size: 13, weight: .bold))
                if block.isDefaultCandidate {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(nsColor: .systemGreen).opacity(0.55))
                        )
                }
                Spacer()
                Text(block.provider)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            Text(block.stateText)
                .font(.system(size: 11))
                .foregroundStyle(block.stateKey.accent)
            if let emptyText = block.emptyText {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(block.windows) { window in
                        GridRow {
                            Text(window.label)
                                .font(.system(size: 12))
                                .italic(window.scoped)
                                .frame(width: 66, alignment: .leading)
                            UsageBar(percent: window.percent, severity: window.severity)
                                .frame(width: 116, height: 7)
                            Text(window.percentText)
                                .font(.system(size: 12))
                                .frame(width: 40, alignment: .trailing)
                            Text(window.forecastText)
                                .font(.system(size: 11))
                                .foregroundStyle(window.severity.accent)
                                .frame(width: 52, alignment: .leading)
                            Text(window.resetText)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .frame(width: 80, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let placeholder = model.content.placeholder {
                        InfoBlockView(block: placeholder)
                    }
                    if let header = model.content.header {
                        InfoBlockView(block: header)
                    }
                    if let runway = model.content.runway {
                        InfoBlockView(block: runway)
                    }
                    ForEach(model.content.overloads) { overload in
                        InfoBlockView(block: overload)
                    }
                    if let pools = model.content.pools {
                        PoolSummaryView(block: pools)
                    }
                    if !model.content.accounts.isEmpty {
                        Divider()
                    }
                    ForEach(model.content.accounts) { account in
                        AccountBlockView(block: account)
                    }
                    if let notice = model.content.emptyAccountsNotice {
                        InfoBlockView(block: notice)
                    }
                    if let error = model.content.errorNotice {
                        InfoBlockView(block: error)
                    }
                }
                .padding(12)
            }
            Divider()
            HStack(spacing: 8) {
                Button(model.isRefreshing ? "Refreshing…" : "Refresh now", action: onRefresh)
                    .disabled(model.isRefreshing)
                Button("Open dashboard", action: onOpenDashboard)
                    .disabled(!model.canOpenDashboard)
                Spacer()
                Button("Settings…", action: onOpenSettings)
                // An agent app has no Dock icon and no application menu, so quitting needs an
                // explicit control.
                Button("Quit", action: onQuit)
            }
            .padding(10)
        }
        .frame(width: 580)
        .frame(maxHeight: 620)
    }
}
