import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    let floatingPanelController: FloatingPanelController
    @ObservedObject var kindleServerController: KindleServerController
    @ObservedObject var loginItemController: LoginItemController
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Form {
            Section("显示") {
                Toggle("启用 Codex Meter", isOn: $store.isEnabled)

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
                Text("主应用每次成功刷新后会同步最新额度到 Widget。首次启动应用后，可在 macOS 桌面编辑小组件并添加“Codex 剩余额度”。")
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
                    Text("需要在“系统设置 > 通用 > 登录项与扩展”中允许 CodexMeter。")
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

                Text("自动更新使用 Sparkle 2。正式打包前需要配置可公开访问的 HTTPS appcast 和 EdDSA 公钥；私有 GitHub 仓库地址不能直接作为匿名客户端的更新源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据源") {
                LabeledContent("当前", value: store.sourceName)
                Text("通过本机只读 JSONL 协议读取。协议不可用时会明确报错，不会抓取 Codex 界面或登录信息。")
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
        .onAppear {
            loginItemController.refresh()
        }
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
