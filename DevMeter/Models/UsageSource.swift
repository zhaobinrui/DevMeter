import Foundation

enum UsageSource: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode

    var id: String { rawValue }
    var title: String {
        switch self { case .codex: "Codex"; case .claudeCode: "Claude Code" }
    }
    var supportsAccountHistory: Bool {
        switch self { case .codex: true; case .claudeCode: false }
    }
    var timestampAction: String {
        switch self { case .codex: "更新"; case .claudeCode: "收到" }
    }
}
