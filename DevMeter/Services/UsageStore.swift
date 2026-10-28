import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasProAccess: Bool
    @Published private(set) var selectedProviderID: UsageSource
    @Published private(set) var authorizedProviders: Set<UsageSource>
    @Published private(set) var historySamples: [UsageHistorySample] = []
    @Published private(set) var historyError: String?
    @Published private(set) var isEditingHistory = false
    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var notificationPermission: UsageNotificationPermission = .notDetermined
    @Published private(set) var notificationError: String?

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            isEnabled ? start() : stop()
        }
    }
    @Published var publishToKindle: Bool {
        didSet { defaults.set(publishToKindle, forKey: Keys.publishToKindle) }
    }
    @Published var showsFloatingPanel: Bool {
        didSet { defaults.set(showsFloatingPanel, forKey: Keys.showsFloatingPanel) }
    }
    @Published var floatingPanelOpacity: Double {
        didSet { defaults.set(floatingPanelOpacity, forKey: Keys.floatingPanelOpacity) }
    }
    @Published var refreshIntervalSeconds: Int {
        didSet {
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
            restartIfNeeded()
        }
    }
    @Published var historyEnabled: Bool {
        didSet {
            historyGeneration &+= 1
            defaults.set(historyEnabled, forKey: Keys.historyEnabled)
        }
    }
    @Published private(set) var historyRetentionDays: Int
    @Published var lowQuotaThreshold: Int {
        didSet { defaults.set(lowQuotaThreshold, forKey: Keys.lowQuotaThreshold) }
    }
    @Published var lowQuotaAlerts: Bool {
        didSet { defaults.set(lowQuotaAlerts, forKey: Keys.lowQuotaAlerts) }
    }
    @Published var predictionAlerts: Bool {
        didSet { defaults.set(predictionAlerts, forKey: Keys.predictionAlerts) }
    }
    @Published var refreshFailureAlerts: Bool {
        didSet { defaults.set(refreshFailureAlerts, forKey: Keys.refreshFailureAlerts) }
    }

    private var provider: any UsageProvider
    private let providers: [UsageSource: any UsageProvider]
    private var sourceSnapshots: [UsageSource: UsageSnapshot] = [:]
    private var sourceErrors: [UsageSource: String] = [:]
    private let defaults: UserDefaults
    private let historyRepository: (any UsageHistoryPersisting)?
    private let notificationSender: (any UsageNotificationSending)?
    private let didUpdateSnapshot: @MainActor (UsageSnapshot) -> Void
    private let didSelectProvider: @MainActor (UsageSource) -> Void
    private let now: @MainActor () -> Date
    private var refreshTask: Task<Void, Never>?
    private var fetchTask: Task<UsageSnapshot, Error>?
    private var shutdownTask: Task<Void, Never>?
    private var generation: UInt = 0
    private var historyGeneration: UInt = 0
    private var notificationSettingsGeneration: UInt = 0
    private var consecutiveFailures = 0
    private var wantsPolling = false
    private var alertPolicy: UsageAlertPolicy

    init(
        provider: any UsageProvider,
        additionalProviders: [UsageSource: any UsageProvider] = [:],
        defaults: UserDefaults = .standard,
        historyRepository: (any UsageHistoryPersisting)? = nil,
        notificationSender: (any UsageNotificationSending)? = nil,
        hasProAccess: Bool = true,
        now: @escaping @MainActor () -> Date = { .now },
        didUpdateSnapshot: @escaping @MainActor (UsageSnapshot) -> Void = { _ in },
        didSelectProvider: @escaping @MainActor (UsageSource) -> Void = { _ in }
    ) {
        var providers = additionalProviders
        providers[.codex] = provider
        self.providers = providers
        authorizedProviders = Set(providers.keys.filter { ProviderAuthorization.isGranted($0, defaults: defaults) })
        let saved = defaults.string(forKey: Keys.selectedProvider).flatMap(UsageSource.init(rawValue:)) ?? .codex
        let selected = providers[saved] != nil && (hasProAccess || saved == .codex) ? saved : .codex
        selectedProviderID = selected
        self.provider = providers[selected] ?? provider
        self.defaults = defaults
        self.historyRepository = historyRepository
        self.notificationSender = notificationSender
        self.hasProAccess = hasProAccess
        self.now = now
        self.didUpdateSnapshot = didUpdateSnapshot
        self.didSelectProvider = didSelectProvider
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        publishToKindle = defaults.object(forKey: Keys.publishToKindle) as? Bool ?? false
        showsFloatingPanel = defaults.object(forKey: Keys.showsFloatingPanel) as? Bool ?? true
        floatingPanelOpacity = min(1, max(0.3, defaults.object(forKey: Keys.floatingPanelOpacity) as? Double ?? 1))
        refreshIntervalSeconds = min(300, max(30, defaults.object(forKey: Keys.refreshIntervalSeconds) as? Int ?? 60))
        historyEnabled = defaults.object(forKey: Keys.historyEnabled) as? Bool ?? true
        let retention = defaults.integer(forKey: Keys.historyRetentionDays)
        historyRetentionDays = [7, 30, 90].contains(retention) ? retention : 30
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? false
        lowQuotaThreshold = min(50, max(1, defaults.object(forKey: Keys.lowQuotaThreshold) as? Int ?? 10))
        lowQuotaAlerts = defaults.object(forKey: Keys.lowQuotaAlerts) as? Bool ?? true
        predictionAlerts = defaults.object(forKey: Keys.predictionAlerts) as? Bool ?? false
        refreshFailureAlerts = defaults.object(forKey: Keys.refreshFailureAlerts) as? Bool ?? true
        alertPolicy = defaults.data(forKey: Self.alertPolicyKey(selected)).flatMap {
            $0.count <= 100_000 ? try? JSONDecoder().decode(UsageAlertPolicy.self, from: $0) : nil
        } ?? UsageAlertPolicy()
    }

    var isSnapshotStale: Bool {
        guard let snapshot else { return false }
        return lastError != nil || now().timeIntervalSince(snapshot.fetchedAt) > max(300, Double(refreshIntervalSeconds) * 2)
            || snapshot.limits.contains { $0.resetsAt.map { $0 <= now() } ?? false }
    }

    var menuTitle: String {
        guard isEnabled else { return "DM —" }
        let prefix = selectedProviderID == .codex ? "DM" : "DM Claude"
        guard isProviderAuthorized else { return "\(prefix) · 待授权" }
        guard let remaining = snapshot?.mostConstrainedLimit?.remainingPercent else { return "\(prefix) …" }
        return "\(prefix) \(remaining)%" + (isSnapshotStale ? " · 旧" : "")
    }

    var sourceName: String { provider.sourceName }
    var availableProviders: [UsageSource] { UsageSource.allCases.filter { providers[$0] != nil } }
    var isProviderAuthorized: Bool { authorizedProviders.contains(selectedProviderID) }

    func grantProviderAccess(_ source: UsageSource) {
        guard providers[source] != nil else { return }
        ProviderAuthorization.setGranted(true, for: source, defaults: defaults)
        authorizedProviders.insert(source)
        if source == selectedProviderID, wantsPolling { start() }
    }

    func revokeProviderAccess(_ source: UsageSource) {
        ProviderAuthorization.setGranted(false, for: source, defaults: defaults)
        authorizedProviders.remove(source)
        sourceSnapshots[source] = nil
        sourceErrors[source] = nil
        guard source == selectedProviderID else { return }
        let resumeAfterAuthorization = wantsPolling
        stop()
        wantsPolling = resumeAfterAuthorization
        historyGeneration &+= 1
        snapshot = nil
        lastError = nil
        notificationError = nil
        consecutiveFailures = 0
        // 撤销后立即清除各展示端的当前值；历史保留供用户另行清除，迟到回调由 generation 拒绝。
        didSelectProvider(source)
    }

    var symbolName: String {
        if isEnabled, isSnapshotStale { return "exclamationmark.triangle" }
        guard isEnabled, let remaining = snapshot?.mostConstrainedLimit?.remainingPercent else {
            return "gauge.with.dots.needle.0percent"
        }
        switch remaining {
        case 0..<10: return "gauge.with.dots.needle.100percent"
        case 10..<40: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.33percent"
        }
    }

    var currentAccountHistory: [UsageHistorySample] {
        guard selectedProviderID.supportsAccountHistory, let account = snapshot?.accountKey else { return [] }
        return historySamples.filter { $0.accountKey == account }
    }

    var forecasts: [UsageForecast] {
        guard selectedProviderID.supportsAccountHistory, hasProAccess, historyEnabled, historyError == nil, let snapshot else { return [] }
        if lastError != nil { return snapshot.limits.map { UsageForecast(id: $0.id, status: .stale) } }
        return UsageForecastEngine.forecasts(snapshot: snapshot, samples: currentAccountHistory, now: now())
    }

    var historyScopeMessage: String? {
        if !selectedProviderID.supportsAccountHistory {
            return "Claude 状态行没有稳定账户标识，仅展示最近事件中的订阅窗口；不记录历史、不预测，也不发送账户额度提醒。"
        }
        guard snapshot != nil, snapshot?.accountKey == nil else { return nil }
        return "当前协议无法可靠区分此账户的历史归属。仅展示当前额度；组织账户、未知套餐或缺少身份时不记录历史、不预测。"
    }

    func start() {
        wantsPolling = true
        guard isEnabled, isProviderAuthorized, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay = min(900, max(30, self.refreshIntervalSeconds) * (1 << min(self.consecutiveFailures, 4)))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func stop() {
        wantsPolling = false
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        isRefreshing = false
        // 等旧请求退出后再允许新采集，防止迟到结果或异步 shutdown 影响新会话。
        let previousShutdown = shutdownTask
        let previousProvider = provider
        shutdownTask = Task { await previousShutdown?.value; await previousProvider.shutdown() }
    }

    func selectProvider(_ id: UsageSource) {
        guard let next = providers[id], hasProAccess || id == .codex else { return }
        defaults.set(id.rawValue, forKey: Keys.selectedProvider)
        guard id != selectedProviderID else { return }
        let wasRunning = wantsPolling
        stop()
        persistAlertPolicy()
        historyGeneration &+= 1
        selectedProviderID = id
        notificationError = nil
        alertPolicy = defaults.data(forKey: Self.alertPolicyKey(id)).flatMap {
            $0.count <= 100_000 ? try? JSONDecoder().decode(UsageAlertPolicy.self, from: $0) : nil
        } ?? UsageAlertPolicy()
        provider = next
        snapshot = isProviderAuthorized ? sourceSnapshots[id] : nil
        lastError = isProviderAuthorized ? sourceErrors[id] : nil
        consecutiveFailures = 0
        // 切换瞬间先清除其他来源的 Widget 数据；Kindle 从 snapshot 发布同步获得 nil/本来源缓存。
        didSelectProvider(id)
        if let snapshot { didUpdateSnapshot(snapshot) }
        if wasRunning { start() }
    }

    func clearClaudeCapture() throws {
        try ClaudeStatusLineFile.applicationFile.clear()
        sourceSnapshots[.claudeCode] = nil
        sourceErrors[.claudeCode] = nil
        if selectedProviderID == .claudeCode {
            stop()
            snapshot = nil
            lastError = ClaudeStatusLineError.notConnected.localizedDescription
            didSelectProvider(.claudeCode)
            start()
        }
    }

    func refresh() async {
        // 自动轮询、手动刷新、重试与恢复都经过同一个授权门，不能只禁用界面按钮。
        guard isEnabled, isProviderAuthorized, !isRefreshing, !isEditingHistory else { return }
        isRefreshing = true
        let operation = generation
        // 旧来源请求的 defer 不能清掉新来源正在执行的刷新状态。
        defer { if operation == generation { isRefreshing = false; fetchTask = nil } }
        await shutdownTask?.value
        guard isEnabled, isProviderAuthorized, operation == generation, !Task.isCancelled else { return }
        let activeProvider = provider
        let task = Task { try await activeProvider.fetchSnapshot() }
        fetchTask = task
        do {
            let updated = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            guard isEnabled, operation == generation, !Task.isCancelled else { return }
            snapshot = updated
            lastError = nil
            sourceSnapshots[selectedProviderID] = updated
            sourceErrors[selectedProviderID] = nil
            consecutiveFailures = 0
            didUpdateSnapshot(updated)
            await updateHistory(with: updated)
            guard isEnabled, operation == generation, !Task.isCancelled else { return }
            let alerts = alertPolicy.success(snapshot: updated, forecasts: forecasts,
                                             threshold: lowQuotaThreshold, lowEnabled: lowQuotaAlerts,
                                             predictionEnabled: predictionAlerts && historyEnabled && hasProAccess)
            await deliver(alerts, operation: operation)
        } catch {
            guard isEnabled, operation == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            lastError = error.localizedDescription
            sourceErrors[selectedProviderID] = lastError
            consecutiveFailures = min(4, consecutiveFailures + 1)
            let alert = alertPolicy.failure(now: now())
            if refreshFailureAlerts, let alert { await deliver([alert], operation: operation) }
        }
        persistAlertPolicy()
    }

    private func updateHistory(with snapshot: UsageSnapshot) async {
        guard let repository = historyRepository else { return }
        let operation = historyGeneration
        do {
            let samples: [UsageHistorySample]
            if selectedProviderID.supportsAccountHistory, hasProAccess, historyEnabled, let account = snapshot.accountKey {
                samples = try await repository.record(UsageHistorySample(snapshot: snapshot, accountKey: account),
                                                       retentionDays: historyRetentionDays, now: now())
            } else {
                samples = try await repository.load(retentionDays: historyRetentionDays, now: now())
            }
            guard operation == historyGeneration else { return }
            historySamples = samples
            historyError = nil
        } catch {
            guard operation == historyGeneration else { return }
            historyError = "本地历史读取或保存失败；已保留上次可信记录。可在设置中清除后重试。"
        }
    }

    func setHistoryRetentionDays(_ days: Int) async {
        guard [7, 30, 90].contains(days), !isRefreshing, !isEditingHistory else { return }
        historyRetentionDays = days
        defaults.set(days, forKey: Keys.historyRetentionDays)
        guard let repository = historyRepository else { return }
        isEditingHistory = true
        defer { isEditingHistory = false }
        do {
            historySamples = try await repository.load(retentionDays: days, now: now())
            historyError = nil
        } catch { historyError = "历史保留周期已保存，但清理失败；原记录已保留。" }
    }

    func clearHistory() async {
        guard !isRefreshing, !isEditingHistory else { return }
        isEditingHistory = true
        historyGeneration &+= 1
        defer { isEditingHistory = false }
        do {
            try await historyRepository?.clear()
            historySamples = []
            historyError = nil
        } catch { historyError = "无法清除本地历史，请检查本机文件权限后重试。" }
    }

    func refreshNotificationPermission() async {
        notificationPermission = await notificationSender?.permission() ?? .notDetermined
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationSettingsGeneration &+= 1
        let operation = notificationSettingsGeneration
        if !enabled {
            notificationsEnabled = false
            defaults.set(false, forKey: Keys.notificationsEnabled)
            return
        }
        guard let sender = notificationSender else { return }
        notificationError = nil
        do {
            var permission = await sender.permission()
            if permission == .notDetermined {
                _ = try await sender.requestPermission()
                permission = await sender.permission()
            }
            guard operation == notificationSettingsGeneration else { return }
            notificationPermission = permission
            notificationsEnabled = permission == .authorized
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        } catch {
            notificationError = "无法申请通知权限，请稍后重试。"
        }
    }

    private func deliver(_ alerts: [UsageAlert], operation: UInt) async {
        guard notificationsEnabled, let sender = notificationSender else { return }
        notificationPermission = await sender.permission()
        guard notificationPermission == .authorized else { return }
        for alert in alerts {
            guard notificationsEnabled, isEnabled, operation == generation, !Task.isCancelled else { return }
            switch alert.kind {
            case .lowQuota where !lowQuotaAlerts: continue
            case .forecastRisk where !predictionAlerts || !historyEnabled || !hasProAccess: continue
            case .refreshFailed where !refreshFailureAlerts: continue
            default: break
            }
            do {
                try await sender.send(alert)
                // 通知提交可能跨越来源切换；迟到回调不能修改新来源的去重或错误状态。
                guard operation == generation else { return }
                alertPolicy.markDelivered(alert)
                notificationError = nil
                persistAlertPolicy()
            } catch {
                guard operation == generation else { return }
                notificationError = "提醒发送失败，将在下一次有效刷新后重试。"
            }
        }
    }

    private func persistAlertPolicy() {
        if let data = try? JSONEncoder().encode(alertPolicy) { defaults.set(data, forKey: Self.alertPolicyKey(selectedProviderID)) }
    }

    private static func alertPolicyKey(_ source: UsageSource) -> String {
        source == .codex ? Keys.alertPolicy : "notifications.policy-\(source.rawValue)-v1"
    }

    func setProAccess(_ allowed: Bool) {
        guard hasProAccess != allowed else { return }
        hasProAccess = allowed
        historyGeneration &+= 1
        // 撤权只停止新增 Pro 工作，不删除或锁住已采集的本地记录。
        if !allowed, selectedProviderID != .codex { selectProvider(.codex) }
        if allowed, let saved = defaults.string(forKey: Keys.selectedProvider).flatMap(UsageSource.init(rawValue:)),
           saved != selectedProviderID {
            // 商店启动时先按 Free 运行；只有 Apple 验证 Pro 后才恢复上次的扩展来源。
            selectProvider(saved)
        }
    }

    private func restartIfNeeded() {
        guard isEnabled, refreshTask != nil else { return }
        stop()
        start()
    }

    private enum Keys {
        static let isEnabled = "meter.isEnabled"
        static let selectedProvider = "meter.selectedProvider"
        static let publishToKindle = "kindle.isEnabled"
        static let showsFloatingPanel = "floatingPanel.isEnabled"
        static let floatingPanelOpacity = "floatingPanel.opacity"
        static let refreshIntervalSeconds = "meter.refreshIntervalSeconds"
        static let historyEnabled = "history.isEnabled"
        static let historyRetentionDays = "history.retentionDays"
        static let notificationsEnabled = "notifications.isEnabled"
        static let lowQuotaThreshold = "notifications.lowQuotaThreshold"
        static let lowQuotaAlerts = "notifications.lowQuota"
        static let predictionAlerts = "notifications.prediction"
        static let refreshFailureAlerts = "notifications.refreshFailure"
        static let alertPolicy = "notifications.policy-v1"
    }
}
