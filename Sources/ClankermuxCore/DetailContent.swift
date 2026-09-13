import Foundation

public enum DetailStyle: String, Sendable, Equatable {
    case normal, warning, error
}

public struct InfoBlock: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let style: DetailStyle
}

public struct WindowRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let percent: Int?
    public let severity: Severity
    public let forecastText: String
    public let resetText: String
    public let scoped: Bool
}

public struct AccountBlock: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let provider: String
    public let stateText: String
    public let stateKey: StateKey
    public let windows: [WindowRow]
    public let emptyText: String?
}

public struct DetailContent: Sendable, Equatable {
    public let placeholder: InfoBlock?
    public let header: InfoBlock?
    public let workloads: [WorkloadRow]
    public let notices: [InfoBlock]
    public let accounts: [AccountBlock]

    public static func make(snapshot: RefreshSnapshot, view: UsageView, now: Date) -> DetailContent
    {
        let loaded = snapshot.accounts != nil || snapshot.workloads != nil
        let refresh = lastRefreshText(lastSuccess: snapshot.lastSuccess, now: now)
        let errors = [
            ("Accounts", snapshot.lastAccountsError, snapshot.accountsReceivedAt),
            ("Status", snapshot.lastStatusError, snapshot.statusReceivedAt),
            ("Workloads", snapshot.lastWorkloadsError, snapshot.workloadsReceivedAt),
        ]
        var notices = errors.compactMap { label, error, received -> InfoBlock? in
            guard !error.isEmpty else { return nil }
            return InfoBlock(
                id: label, title: "\(label) \(received == nil ? "unavailable" : "cached")",
                subtitle: error
                    + (received.map {
                        "\nLast success: \(Formatting.formatTimestamp($0)) (\(UsageModel.ageText($0, now: now)))"
                    } ?? "\nNo cached reading"),
                style: .warning)
        }
        if snapshot.workloads != nil && view.workloads.isEmpty {
            notices.insert(
                InfoBlock(
                    id: "no-workloads", title: "Pacing unavailable",
                    subtitle: "No visible workloads reported",
                    style: .normal), at: 0)
        }
        if snapshot.accounts?.isEmpty == true {
            notices.append(
                InfoBlock(
                    id: "no-accounts", title: "No accounts configured", subtitle: "", style: .normal
                ))
        }
        let status = snapshot.status
        let statusText =
            status.map {
                "\(UsageModel.countText($0.accounts?.configured)) configured · \(UsageModel.countText($0.accounts?.paused)) paused · Service \(Formatting.humanizeStatus($0.serviceState).lowercased())"
            } ?? "Service status unavailable"
        return DetailContent(
            placeholder: loaded
                ? nil
                : InfoBlock(
                    id: "placeholder",
                    title: snapshot.lastError.isEmpty && snapshot.lastWorkloadsError.isEmpty
                        ? "Loading usage…" : "Clankermux is unavailable",
                    subtitle: Formatting.normalizeBaseUrl(snapshot.baseURL),
                    style: snapshot.lastError.isEmpty && snapshot.lastWorkloadsError.isEmpty
                        ? .normal : .error),
            header: loaded
                ? InfoBlock(
                    id: "header", title: "Clankermux usage", subtitle: "\(statusText)\n\(refresh)",
                    style: .normal) : nil,
            workloads: view.workloads, notices: notices, accounts: view.accounts)
    }

    static func lastRefreshText(lastSuccess: Date?, now: Date) -> String {
        guard let lastSuccess else { return "Accounts/status refreshed: Never" }
        return
            "Accounts/status refreshed: \(Formatting.formatTimestamp(lastSuccess)) (\(UsageModel.ageText(lastSuccess, now: now)))"
    }
}
