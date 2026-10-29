import Charts
import SwiftUI

struct UsageHistoryView: View {
    @ObservedObject var store: UsageStore
    @State private var rangeDays = 1
    @State private var selectedHistoryAccountKey: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("历史与预测").font(.title2.bold())
                        Text("仅记录本机观察到的额度快照，不是完整账单或逐模型 Token 用量。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("时间范围", selection: $rangeDays) {
                        Text("24 小时").tag(1)
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                    }.frame(width: 140)
                }

                if !store.isProviderAuthorized {
                    Label("尚未授权读取 \(store.selectedProviderID.title)，请在设置中查看读取范围并决定是否允许。", systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                }
                if let message = store.historyScopeMessage {
                    Label(message, systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
                if let error = store.historyError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                HStack {
                    if store.isLoadingHistory {
                        ProgressView("正在加载本地历史…").controlSize(.small)
                    }
                    Spacer()
                    Button("重新加载本地历史") { Task { await store.loadHistory() } }
                        .disabled(store.isLoadingHistory || store.isEditingHistory)
                        .accessibilityIdentifier("usageHistory.reload")
                }
                if !store.savedHistoryGroups.isEmpty {
                    Picker("查看记录", selection: $selectedHistoryAccountKey) {
                        Text("自动选择当前账户或最近记录").tag(String?.none)
                        ForEach(Array(store.savedHistoryGroups.enumerated()), id: \.element.id) { index, group in
                            Text("本地分组 \(index + 1) · \(group.sampleCount) 次采样")
                                .tag(Optional(group.id))
                        }
                    }
                    .accessibilityIdentifier("usageHistory.group")
                    Text("分组只用于区分本机保存的 Codex 记录，不显示邮箱，也不推断它属于当前登录账户；编号随现有记录排序。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !store.historyEnabled {
                    Label("历史记录已暂停，可在设置中重新开启；已有记录仍可查看。", systemImage: "pause.circle")
                }
                if !store.hasProAccess {
                    Label("尚未解锁 Pro，暂停新增记录和预测；已有历史仍可查看、调整保留周期或清除。", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
                if let display = store.historyDisplay(accountKey: selectedHistoryAccountKey) {
                    Text("Codex · \(display.isCurrentSnapshot ? "数据时间" : "记录时间") \(display.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    if !display.isCurrentSnapshot {
                        Label("仅展示已保存历史，不代表当前账户或当前额度；历史记录不用于实时预测。", systemImage: "archivebox")
                            .foregroundStyle(.secondary)
                    } else if !store.isEnabled {
                        Label("额度读取已关闭，当前数字为关闭前的上次结果；历史记录仍可查看。", systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                    } else if store.isSnapshotStale {
                        Label("正在展示上次可信数据，当前额度可能已变化。", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    ForEach(display.limits) { limit in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(limit.name).font(.headline)
                                    Spacer()
                                    Text("\(display.isCurrentSnapshot ? "剩余" : "记录时剩余") \(limit.remainingPercent)%").monospacedDigit()
                                }
                                let points = chartPoints(for: limit, samples: display.samples)
                                if points.isEmpty {
                                    Text("此时间范围内没有已保存的历史采样。")
                                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
                                } else {
                                    Chart(points) { point in
                                        LineMark(x: .value("时间", point.date), y: .value("已用 %", point.used),
                                                 series: .value("连续窗口", point.segment))
                                        PointMark(x: .value("时间", point.date), y: .value("已用 %", point.used))
                                            .symbolSize(8)
                                    }
                                    .chartYScale(domain: 0...100)
                                    .chartYAxisLabel("已用百分比")
                                    .frame(height: 150)
                                    .accessibilityLabel("\(limit.name)，已用百分比随时间变化，\(display.isCurrentSnapshot ? "当前" : "记录时")剩余 \(limit.remainingPercent)%")
                                }
                                if display.isCurrentSnapshot, let forecast = store.forecasts.first(where: { $0.id == limit.id }) {
                                    Text(forecast.summary)
                                        .foregroundStyle(forecast.status == .atRisk ? .orange : .secondary)
                                    if forecast.status == .atRisk, let date = forecast.exhaustionDate {
                                        Text("估计耗尽：\(date.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let reset = limit.resetsAt {
                                    Text("\(display.isCurrentSnapshot ? "下次重置" : "记录中的重置时间")：\(reset.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.abbreviation() ?? TimeZone.current.identifier)")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("重置时间未知").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(8)
                        }
                    }
                } else {
                    if !store.isLoadingHistory {
                        ContentUnavailableView("暂无本地额度历史", systemImage: "chart.xyaxis.line",
                                           description: Text("已有记录无需重新授权或解锁 Pro 即可查看；新记录需完成授权并启用记录。"))
                    }
                }
                Text("五分钟内合并采样；重置、用量回退和超过 15 分钟的断采会切断趋势。预测基于近两小时连续样本，至少覆盖十分钟，仅供参考。保留周期与清除入口位于设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(minWidth: 620, minHeight: 480)
        .task { await store.loadHistory() }
        .onChange(of: store.savedHistoryGroups.map(\.id)) { _, keys in
            if let selectedHistoryAccountKey, !keys.contains(selectedHistoryAccountKey) {
                self.selectedHistoryAccountKey = nil
            }
        }
    }

    private func chartPoints(for limit: UsageLimit, samples: [UsageHistorySample]) -> [HistoryChartPoint] {
        let cutoff = Date.now.addingTimeInterval(-Double(rangeDays) * 86_400)
        var result: [HistoryChartPoint] = []
        var segment = 0
        var previous: (Date, UsageLimit)?
        for sample in samples where sample.fetchedAt >= cutoff {
            guard let value = sample.limits.first(where: { $0.id == limit.id }) else { continue }
            if let previous, value.resetsAt != previous.1.resetsAt
                || value.windowDurationMinutes != previous.1.windowDurationMinutes
                || value.usedPercent < previous.1.usedPercent
                || sample.fetchedAt.timeIntervalSince(previous.0) > 900 {
                segment += 1
            }
            result.append(HistoryChartPoint(id: result.count, date: sample.fetchedAt,
                                            used: value.usedPercent, segment: segment))
            previous = (sample.fetchedAt, value)
        }
        // 长时间范围只下采样显示，原始记录仍按保留周期保存；系列 ID 保留窗口断点。
        let step = max(1, Int(ceil(Double(result.count) / 500)))
        return result.enumerated().compactMap { index, point in
            index.isMultiple(of: step) || index == result.count - 1 ? point : nil
        }
    }
}

private struct HistoryChartPoint: Identifiable {
    let id: Int
    let date: Date
    let used: Int
    let segment: Int
}
