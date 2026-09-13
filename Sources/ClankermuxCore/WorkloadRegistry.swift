import Foundation

/// The provider mark drawn beside a workload.
public enum ProviderMark: String, Sendable, Equatable, CaseIterable {
    case anthropic, openai, fable
}

public struct WorkloadTarget: Sendable, Equatable {
    /// The workload id the server uses, `class:codex` or `family:fable`.
    public let key: String
    public let label: String
    public let mark: ProviderMark
    /// The `Account.provider` whose accounts make up this workload.
    public let provider: String

    public init(key: String, label: String, mark: ProviderMark, provider: String) {
        self.key = key
        self.label = label
        self.mark = mark
        self.provider = provider
    }
}

/// Which workloads the menu bar shows, in which order, with which label and mark.
public enum WorkloadRegistry {
    public static let fableKey = "family:fable"

    public static let targets: [WorkloadTarget] = [
        WorkloadTarget(key: "class:codex", label: "GPT", mark: .openai, provider: "codex"),
        WorkloadTarget(
            key: "class:anthropic", label: "Claude", mark: .anthropic, provider: "anthropic"),
        WorkloadTarget(key: fableKey, label: "Fable", mark: .fable, provider: "anthropic"),
    ]

    public static func mark(forKey key: String) -> ProviderMark? {
        targets.first { $0.key == key }?.mark
    }
}
