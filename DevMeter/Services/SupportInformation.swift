import Foundation

enum SupportDataState: String, Sendable {
    case paused, waiting, current, stale, failed

    static func resolve(isEnabled: Bool, hasData: Bool, isStale: Bool, hasError: Bool) -> Self {
        if !isEnabled { return .paused }
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
            PrivacyNoticeSection(id: "local-data", title: "本机数据", body: "DevMeter 在本机读取额度窗口、重置时间和可用 Credits。Codex 账户邮箱与套餐只在内存中用于生成本机加盐分组，不保存邮箱、登录令牌、提示词、代码或完整会话。"),
            PrivacyNoticeSection(id: "retention", title: "历史与保留", body: "Codex 历史仅保存额度数字、窗口时间和本机账户分组。默认保留 30 天，可选 7/90 天，可暂停新增记录或清除全部历史。最多 30,000 条、16 MiB。未解锁或失去 Pro 不会锁住已有历史与清除入口。"),
            PrivacyNoticeSection(id: "sharing", title: "Widget 与 Kindle", body: "Widget 通过本应用的 App Group 读取最近额度、Credits、来源和时间，不读取账户凭据或历史。主动启用 Kindle 后，同一局域网中持有配对地址的人可查看这些只读数据；请勿公开配对地址。停用 DevMeter 会停止采集与 Kindle 服务。"),
            PrivacyNoticeSection(id: "network", title: "联网与第三方", body: "DevMeter 不设额度上传服务器，不包含行为追踪或自动诊断上传。Codex CLI 可能连接其服务，Apple 处理商店购买；直接分发预览仅在配置更新源后由 Sparkle 请求更新。主动打开反馈页面时由浏览器访问 GitHub，各服务适用其各自政策。"),
            PrivacyNoticeSection(id: "control", title: "权限与清除", body: "系统通知默认关闭，仅在主动开启时申请权限。可在设置中停用采集、暂停历史、清除全部历史或关闭 Kindle；系统通知权限也可在 macOS 设置中撤回。退出应用会停止本应用的采集与局域网服务。最近的 Widget 快照保留在本应用的 App Group 中，不包含历史或账户标识。"),
            PrivacyNoticeSection(id: "feedback", title: "反馈与联系", body: "通过 GitHub Issues 联系项目维护者。反馈内容由你选择并提交，公开 Issue 对其他人可见。请不要粘贴令牌、邮箱、私密代码或含配对令牌的地址。复制支持信息只写入剪贴板，不会自动上传。")
        ]
        if includesClaude {
            result.insert(PrivacyNoticeSection(id: "claude", title: "Claude 本地状态行", body: "仅接收用户主动配置的状态行，在内存中提取两个订阅窗口及接收时间。原始 JSON、登录凭据、项目路径和会话文件不落盘；不额外请求模型。最新快照可单独清除，要停用接收还需移除 Claude 中的状态行配置。"), at: 2)
        }
        return result
    }
}
