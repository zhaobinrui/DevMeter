import Foundation

enum ProviderAuthorization {
    // 读取范围变化时提升版本，旧偏好、历史记录和 CLI 登录不能代替新范围的主动同意。
    static let version = 1

    static func key(for source: UsageSource) -> String { "provider.authorization.\(source.rawValue)" }

    static func isGranted(_ source: UsageSource, defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key(for: source)) == version
    }

    static func setGranted(_ granted: Bool, for source: UsageSource, defaults: UserDefaults = .standard) {
        if granted { defaults.set(version, forKey: key(for: source)) }
        else { defaults.removeObject(forKey: key(for: source)) }
        // Claude 接收器是另一个短生命周期进程，主动授权/撤销需要及时刷新到同一应用偏好域。
        defaults.synchronize()
    }
}

extension UsageSource {
    var authorizationExplanation: String {
        switch self {
        case .codex:
            "允许 DevMeter 启动本机 Codex CLI，以现有登录读取额度、重置时间和 Credits。邮箱与套餐仅在内存中生成本机加盐账户分组；按历史设置保存额度记录。CLI 可能连接 Codex 服务，不发起模型任务，不读取或保存登录令牌。"
        case .claudeCode:
            "允许 DevMeter 接收你主动配置的 Claude Code 状态行，并读取本地快照。只保存两个订阅额度窗口、重置时间和接收时间；原始输入仅在内存中过滤，不保存凭据、项目路径或会话内容，不额外请求模型。"
        }
    }
}
