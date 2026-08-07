import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("显示") {
                Toggle("启用 Codex Meter", isOn: $store.isEnabled)

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
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 360)
    }
}
