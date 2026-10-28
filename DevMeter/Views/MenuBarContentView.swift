import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: UsageStore
    let floatingPanelController: FloatingPanelController
    let toggleHistory: () -> Void
    let showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.availableProviders.count > 1 {
                Picker("来源", selection: Binding(get: { store.selectedProviderID }, set: { store.selectProvider($0) })) {
                    ForEach(store.availableProviders) { source in
                        Text(source.title).tag(source).disabled(!store.hasProAccess && source != .codex)
                    }
                }
            }

            if !store.isEnabled {
                ContentUnavailableView(
                    "DevMeter 已关闭",
                    systemImage: "pause.circle",
                    description: Text("可在设置中重新启用本地额度展示。")
                )
            } else if !store.isProviderAuthorized {
                ProviderAuthorizationView(source: store.selectedProviderID) {
                    store.grantProviderAccess(store.selectedProviderID)
                }
            } else if let snapshot = store.snapshot {
                if store.isSnapshotStale {
                    Label("上次数据，当前额度可能已变化", systemImage: "clock.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(snapshot.limits) { limit in
                    UsageLimitRow(limit: limit)
                    if let forecast = store.forecasts.first(where: { $0.id == limit.id }) {
                        Text(forecast.summary)
                            .font(.caption)
                            .foregroundStyle(forecast.status == .atRisk ? .orange : .secondary)
                    }
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
                    Text("\(snapshot.sourceName) · \(snapshot.fetchedAt, style: .relative)\(store.selectedProviderID.timestampAction)")
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
                ProgressView("正在读取 \(store.selectedProviderID.title) 用量…")
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
                Text("DevMeter")
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
            .disabled(!store.isEnabled || !store.isProviderAuthorized || store.isRefreshing)
            .help("立即刷新")
        }
    }

    private var footer: some View {
        HStack {
            Button {
                toggleHistory()
            } label: {
                Label("历史与预测", systemImage: "chart.xyaxis.line")
            }
            .buttonStyle(.plain)
            .help("显示或隐藏历史与预测窗口")

            Button("浮窗") { floatingPanelController.toggle() }
                .buttonStyle(.plain)
                .help("显示或隐藏置顶浮窗")

            Button(action: showSettings) {
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
                Text("重置：\(resetsAt.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.abbreviation() ?? TimeZone.current.identifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("重置时间未知")
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
