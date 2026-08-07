import Foundation

protocol UsageProvider: Sendable {
    var sourceName: String { get }

    func fetchSnapshot() async throws -> UsageSnapshot
    func shutdown() async
}

extension UsageProvider {
    func shutdown() async {}
}

enum UsageProviderError: LocalizedError {
    case unavailable
    case executableNotFound
    case launchFailed
    case timedOut
    case processExited(Int32)
    case protocolFailure(String)
    case invalidResponse
    case noUsageLimits

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前用量数据源不可用"
        case .executableNotFound:
            return "未找到 codex 命令，请先安装 Codex CLI"
        case .launchFailed:
            return "无法启动 Codex app-server"
        case .timedOut:
            return "读取 Codex 用量超时"
        case let .processExited(status):
            return "Codex app-server 已退出（状态 \(status)）"
        case let .protocolFailure(message):
            return "Codex app-server 返回错误：\(message)"
        case .invalidResponse:
            return "Codex app-server 返回了无法识别的数据"
        case .noUsageLimits:
            return "当前账户没有可展示的 Codex 额度"
        }
    }
}
