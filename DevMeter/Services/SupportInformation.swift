import Foundation

enum SupportDataState: String, Sendable {
    case paused, awaitingAuthorization, waiting, current, stale, failed

    static func resolve(isEnabled: Bool, hasData: Bool, isStale: Bool, hasError: Bool, isAuthorized: Bool = true) -> Self {
        if !isEnabled { return .paused }
        if !isAuthorized { return .awaitingAuthorization }
        if hasError { return .failed }
        if !hasData { return .waiting }
        return isStale ? .stale : .current
    }
}

enum SupportInformation {
    static let feedbackURL = URL(string: "https://github.com/zhaobinrui/DevMeter/issues")!
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static func diagnosticSummary(source: UsageSource, state: SupportDataState,
                                  version: String = version, systemVersion: String = systemVersion) -> String {
        // 白名单参数不接收快照、错误原文或任意用户内容；复制不会提交 Issue 或发起网络请求。
        "DevMeter \(version)\nmacOS \(systemVersion)\nSource: \(source.title)\nState: \(state.rawValue)"
    }
}

struct PrivacyNoticeSection: Identifiable {
    let id: String
    let title: String
    let body: String
}

enum PrivacyNotice {
    static func sections(includesClaude: Bool) -> [PrivacyNoticeSection] {
        var result = [
            PrivacyNoticeSection(id: "local-data", title: "本机数据", body: "DevMeter 在你对每个 Provider 单独授权后，才读取额度窗口、重置时间和可用 Credits。首次安装与升级前没有授权记录时均不自动采集。Codex 账户邮箱与套餐只在内存中用于生成本机加盐分组，不保存邮箱、登录令牌、提示词、代码或完整会话。"),
            PrivacyNoticeSection(id: "retention", title: "历史与保留", body: "Codex 历史仅保存额度数字、窗口时间和本机账户分组。默认保留 30 天，可选 7/90 天，可暂停新增记录或清除全部历史。最多 30,000 条、16 MiB。未解锁或失去 Pro 不会锁住已有历史与清除入口。"),
            PrivacyNoticeSection(id: "sharing", title: "Widget 与 Kindle", body: "Widget 通过本应用的 App Group 读取最近额度、Credits、来源、原始数据时间与通用读取状态，不读取账户凭据、历史或原始错误。过期数据保留原时间并标记旧值，关闭或撤销授权后不再展示额度。主动启用 Kindle 后，同一局域网中持有配对地址的人可查看这些只读数据；请勿公开配对地址。停用 DevMeter 会停止采集与 Kindle 服务。"),
            PrivacyNoticeSection(id: "network", title: "联网与第三方", body: "DevMeter 不设额度上传服务器，不包含行为追踪或自动诊断上传。Codex CLI 可能连接其服务，Apple 处理商店购买；直接分发预览仅在配置更新源后由 Sparkle 请求更新。主动打开反馈页面时由浏览器访问 GitHub，各服务适用其各自政策。"),
            PrivacyNoticeSection(id: "control", title: "权限与清除", body: "可在设置中单独撤销各 Provider 授权，停止其采集并清除当前展示与 Widget 快照；已保存历史及 Claude 快照保留，可另行清除。系统通知默认关闭，仅在主动开启时申请权限。还可停用采集、暂停历史或关闭 Kindle。退出应用会停止本应用的采集与局域网服务；Provider 自身登录不受影响。"),
            PrivacyNoticeSection(id: "feedback", title: "反馈与联系", body: "通过 GitHub Issues 联系项目维护者。反馈内容由你选择并提交，公开 Issue 对其他人可见。请不要粘贴令牌、邮箱、私密代码或含配对令牌的地址。复制支持信息只写入剪贴板，不会自动上传。")
        ]
        if includesClaude {
            result.insert(PrivacyNoticeSection(id: "claude", title: "Claude 本地状态行", body: "先在应用中授权，再手动配置状态行；接收器在读取事件前检查授权。仅在内存中提取两个订阅窗口及接收时间。原始 JSON、登录凭据、项目路径和会话文件不落盘；不额外请求模型。可撤销授权停止接收、单独清除快照，并移除 Claude 中的配置。仅校验模式不读取 Provider 或写入快照。"), at: 2)
        }
        return result
    }
}
