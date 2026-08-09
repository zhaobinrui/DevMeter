import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    let floatingPanelController: FloatingPanelController

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
                Text("局域网页面与安全配对将在后续阶段接入。")
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
        .frame(width: 460, height: 400)
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
