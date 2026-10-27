import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    let floatingPanelController: FloatingPanelController
    @ObservedObject var kindleServerController: KindleServerController
    @ObservedObject var loginItemController: LoginItemController
    @ObservedObject var updateController: UpdateController
    @ObservedObject var purchaseController: PurchaseController
    @State private var confirmsHistoryClear = false
    @State private var showsPrivacyNotice = false
    @State private var copiedSupportInfo = false
    @State private var confirmsClaudeClear = false
    @State private var claudeClearError: String?

    var body: some View {
        Form {
            Section("帮助与隐私") {
                LabeledContent("版本", value: SupportInformation.version)
                Button("阅读隐私说明") { showsPrivacyNotice = true }
                Link("联系与反馈（GitHub Issues）", destination: SupportInformation.feedbackURL)
                Button("复制支持信息") {
                    let state = SupportDataState.resolve(isEnabled: store.isEnabled, hasData: store.snapshot != nil,
                                                         isStale: store.isSnapshotStale, hasError: store.lastError != nil)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SupportInformation.diagnosticSummary(source: store.selectedProviderID, state: state), forType: .string)
                    copiedSupportInfo = true
                }
                if copiedSupportInfo {
                    Text("已复制。请自行检查后粘贴到反馈中；不会自动提交。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("反馈会打开 GitHub，由你自行提交。支持信息只包含版本、系统、来源和通用状态，不包含账户、额度数字、错误原文、路径或配对地址。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("显示") {
                Toggle("启用 DevMeter", isOn: $store.isEnabled)

                Toggle(
                    "显示置顶浮窗",
                    isOn: Binding(
                        get: { store.showsFloatingPanel },
                        set: { isVisible in
                            if isVisible {
                                floatingPanelController.show()
                            } else {
                                floatingPanelController.hide()
                            }
                        }
                    )
                )

                HStack {
                    Text("卡片透明度")
                    Slider(
                        value: floatingPanelTransparency,
                        in: 0...0.7,
                        step: 0.05
                    )
                    Text("\(floatingPanelTransparencyPercent)%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                Picker("刷新间隔", selection: $store.refreshIntervalSeconds) {
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                    Text("5 分钟").tag(300)
                }
                .disabled(!store.isEnabled)
            }

            Section("数据来源") {
                Picker("当前来源", selection: Binding(get: { store.selectedProviderID }, set: { store.selectProvider($0) })) {
                    ForEach(store.availableProviders) { source in
                        Text(source.title).tag(source).disabled(!store.hasProAccess && source != .codex)
                    }
                }
                LabeledContent("读取方式", value: store.sourceName)
                Text("各来源独立展示，不计算跨 Provider 总额度；只刷新所选来源。多来源切换属于 Pro，本地预览版可体验。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Claude Code 本地接入") {
                Text("在 Claude Code 中手动配置 statusLine，将订阅窗口发给 DevMeter。仅保留额度数字、重置时间和接收时间；不读取登录令牌、不上传数据。")
                    .font(.caption).foregroundStyle(.secondary)
                if let executable = Bundle.main.executableURL {
                    DisclosureGroup("查看状态行配置") {
                        Text(ClaudeStatusLineCommand.settingsJSON(executable: executable))
                            .font(.caption.monospaced()).textSelection(.enabled)
                        Button("复制状态行配置") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ClaudeStatusLineCommand.settingsJSON(executable: executable), forType: .string)
                        }
                    }
                }
                Text("请先将 DevMeter 放到固定安装位置，再合并配置到 Claude 设置；已有 statusLine 时先保留原配置。DevMeter 不自动改写 Claude 设置。收到新状态行事件后才能更新；缺少账户标识，暂不提供 Claude 历史、预测或账户额度提醒。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("清除 Claude 本地快照", role: .destructive) { confirmsClaudeClear = true }
                    .confirmationDialog("清除最近一次 Claude 额度快照？下次状态行事件会重新生成。停用接收还需移除 Claude 中的配置。",
                                        isPresented: $confirmsClaudeClear) {
                        Button("清除快照", role: .destructive) {
                            do { try store.clearClaudeCapture(); claudeClearError = nil }
                            catch { claudeClearError = "清除失败，请检查本地文件权限。" }
                        }
                    }
                if let error = claudeClearError { Text(error).font(.caption).foregroundStyle(.orange) }
            }

            Section("历史与预测") {
                Toggle("记录本地额度历史", isOn: $store.historyEnabled)
                    .disabled(!store.hasProAccess || !store.selectedProviderID.supportsAccountHistory)
                Picker("保留周期", selection: Binding(
                    get: { store.historyRetentionDays },
                    set: { days in Task { await store.setHistoryRetentionDays(days) } }
                )) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                .disabled(store.isRefreshing || store.isEditingHistory)
                Button("清除全部本地额度历史", role: .destructive) { confirmsHistoryClear = true }
                    .disabled(store.isRefreshing || store.isEditingHistory)
                    .confirmationDialog("清除所有账户的额度历史？此操作无法撤销，当前额度和其他偏好会保留。",
                                        isPresented: $confirmsHistoryClear) {
                        Button("清除历史", role: .destructive) { Task { await store.clearHistory() } }
                    }
                if let error = store.historyError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("只在本机保存额度数字、窗口时间及加盐账户分组，不保存邮箱、凭据或开发内容。组织账户或身份不完整时不记录；关闭后停止新增记录，已有记录可手动清除。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("提醒") {
                Toggle("启用系统通知", isOn: Binding(
                    get: { store.notificationsEnabled },
                    set: { enabled in Task { await store.setNotificationsEnabled(enabled) } }
                ))
                LabeledContent("系统权限", value: store.notificationPermission.rawValue)
                Toggle("低额度提醒", isOn: $store.lowQuotaAlerts)
                    .disabled(!store.notificationsEnabled)
                Picker("剩余阈值", selection: $store.lowQuotaThreshold) {
                    Text("5%").tag(5)
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                }.disabled(!store.notificationsEnabled || !store.lowQuotaAlerts)
                Toggle("可能提前耗尽时提醒", isOn: $store.predictionAlerts)
                    .disabled(!store.selectedProviderID.supportsAccountHistory || !store.hasProAccess || !store.notificationsEnabled || !store.historyEnabled)
                Toggle("持续刷新失败时提醒", isOn: $store.refreshFailureAlerts)
                    .disabled(!store.notificationsEnabled)
                if let error = store.notificationError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("默认关闭。低额度按窗口去重；刷新至少连续失败三次且持续两分钟才提醒。通知不包含账户或原始错误信息。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Kindle") {
                Toggle("发布到 Kindle", isOn: $store.publishToKindle)
                    .disabled(!store.isEnabled)

                LabeledContent("状态", value: kindleServerController.statusText)

                if let accessURL = kindleServerController.accessURL {
                    Text(accessURL.absoluteString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("复制 Kindle 访问地址") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(accessURL.absoluteString, forType: .string)
                    }
                }

                if case .failed = kindleServerController.state {
                    Button("重试启动局域网服务") {
                        kindleServerController.retry()
                    }
                }

                Text("Mac 与 Kindle 需连接同一局域网。访问地址包含随机配对令牌，请勿公开分享；页面仅展示额度，不能执行写操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("桌面小组件") {
                Text("主应用每次成功刷新后会同步所选来源的最新额度到 Widget。首次启动应用后，可在 macOS 桌面编辑小组件并添加“DevMeter 用量”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("系统") {
                Toggle(
                    "登录时自动启动",
                    isOn: Binding(
                        get: { loginItemController.isEnabled },
                        set: { loginItemController.setEnabled($0) }
                    )
                )

                if loginItemController.requiresApproval {
                    Text("需要在“系统设置 > 通用 > 登录项与扩展”中允许 DevMeter。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = loginItemController.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("软件更新") {
                LabeledContent("状态", value: updateController.statusText)
                Button("检查更新") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.isConfigured)

                Text(updateController.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pro 购买与恢复") {
                LabeledContent("权益", value: purchaseController.state.summary)
                if purchaseController.channel == .appStore {
                    Text("Pro 包含多来源切换，以及已支持来源的历史记录、基础预测与预测提醒。一次购买，无自动续费；已有历史始终可查看和清除。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !purchaseController.hasProAccess {
                        Button(purchaseController.product.map { "买断 Pro · \($0.displayPrice)" } ?? "Pro 商品暂不可用") {
                            Task { await purchaseController.purchase() }
                        }
                        .disabled(purchaseController.product == nil || purchaseController.isWorking || purchaseController.state == .pending)
                    }
                    Button("恢复购买") { Task { await purchaseController.restore() } }
                        .disabled(purchaseController.isWorking)
                    Button("刷新商品信息") { Task { await purchaseController.loadProduct() } }
                        .disabled(purchaseController.isWorking)
                    Text("付款由 Apple 处理，金额与可用付款方式以 Apple 确认页面为准。DevMeter 不接触支付账号，也不上传本地额度历史。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("当前为本地预览版，Pro 能力供体验，不提供真实收款。正式购买与恢复由 Mac App Store 版本提供。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = purchaseController.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            }

            Section("数据源") {
                LabeledContent("当前", value: store.sourceName)
                Text("Codex 使用本机只读 JSONL 协议；Claude Code 使用主动配置的本地状态行。接口不可用时明确报错，不抓取界面或登录凭据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("切换 Codex/CLI 当前账号后，下一次刷新会重新启动 app-server 并读取新账号额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500, height: 650)
        .sheet(isPresented: $showsPrivacyNotice) {
            VStack(spacing: 0) {
                PrivacyPolicyView(includesClaude: store.availableProviders.contains(.claudeCode))
                Divider()
                HStack {
                    Spacer()
                    Button("关闭") { showsPrivacyNotice = false }
                        .keyboardShortcut(.cancelAction)
                }.padding(14)
            }.frame(width: 480, height: 580)
        }
        .onAppear {
            loginItemController.refresh()
        }
        .task { await store.refreshNotificationPermission() }
        .task { await purchaseController.loadProduct() }
    }

    private var floatingPanelTransparency: Binding<Double> {
        Binding(
            get: { 1 - store.floatingPanelOpacity },
            set: { store.floatingPanelOpacity = 1 - $0 }
        )
    }

    private var floatingPanelTransparencyPercent: Int {
        Int(((1 - store.floatingPanelOpacity) * 100).rounded())
    }
}
