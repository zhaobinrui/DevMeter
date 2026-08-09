import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: UsageStore
    let floatingPanelController: FloatingPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !store.isEnabled {
                ContentUnavailableView(
                    "Codex Meter 已关闭",
                    systemImage: "pause.circle",
                    description: Text("可在设置中重新启用本地额度展示。")
                )
            } else if let snapshot = store.snapshot {
                ForEach(snapshot.limits) { limit in
                    UsageLimitRow(limit: limit)
                }

                if let lastError = store.lastError {
                    Label(
                        "刷新失败，正在显示上次数据：\(lastError)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let creditBalance = snapshot.creditBalance {
                    LabeledContent("Credits", value: creditBalance)
                        .font(.callout)
                }

                Divider()

                HStack {
                    Text("\(snapshot.sourceName) · \(snapshot.fetchedAt, style: .relative)更新")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.caption)
            } else if let lastError = store.lastError {
                ContentUnavailableView(
                    "无法读取用量",
                    systemImage: "exclamationmark.triangle",
                    description: Text(lastError)
                )
            } else {
                ProgressView("正在读取 Codex 用量…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Meter")
                    .font(.headline)
                Text("用量概览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(!store.isEnabled || store.isRefreshing)
            .help("立即刷新")
        }
    }

    private var footer: some View {
        HStack {
            Button {
                floatingPanelController.show()
            } label: {
                Label("置顶浮窗", systemImage: "macwindow.on.rectangle")
            }
            .buttonStyle(.plain)

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct UsageLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.name)
                    .font(.callout.weight(.medium))
                Spacer()
                Text("剩余 \(limit.remainingPercent)%")
                    .font(.callout.monospacedDigit())
            }

            ProgressView(value: Double(limit.remainingPercent), total: 100)
                .tint(tint)

            if let resetsAt = limit.resetsAt {
                Text("重置：\(resetsAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tint: Color {
        switch limit.remainingPercent {
        case 0..<10:
            return .red
        case 10..<40:
            return .orange
        default:
            return .green
        }
    }
}
