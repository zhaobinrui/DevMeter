import Charts
import SwiftUI

struct UsageHistoryView: View {
    @ObservedObject var store: UsageStore
    @State private var rangeDays = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(store.selectedProviderID.title) 历史与预测").font(.title2.bold())
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
                if !store.historyEnabled {
                    Label("历史记录已暂停，可在设置中重新开启；已有记录仍可查看。", systemImage: "pause.circle")
                }
                if !store.hasProAccess {
                    Label("尚未解锁 Pro，暂停新增记录和预测；已有历史仍可查看、调整保留周期或清除。", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
                if let snapshot = store.snapshot {
                    Text("\(snapshot.sourceName) · 数据时间 \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.isSnapshotStale {
                        Label("正在展示上次可信数据，当前额度可能已变化。", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    ForEach(snapshot.limits) { limit in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(limit.name).font(.headline)
                                    Spacer()
                                    Text("剩余 \(limit.remainingPercent)%").monospacedDigit()
                                }
                                let points = chartPoints(for: limit)
                                if points.isEmpty {
                                    Text(store.selectedProviderID.supportsAccountHistory
                                         ? "暂无此时间范围内的历史。开启记录后，样本会逐步积累。"
                                         : "此来源暂不支持可靠的账户历史与预测。")
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
                                    .accessibilityLabel("\(limit.name)，已用百分比随时间变化，当前剩余 \(limit.remainingPercent)%")
                                }
                                if let forecast = store.forecasts.first(where: { $0.id == limit.id }) {
                                    Text(forecast.summary)
                                        .foregroundStyle(forecast.status == .atRisk ? .orange : .secondary)
                                    if forecast.status == .atRisk, let date = forecast.exhaustionDate {
                                        Text("估计耗尽：\(date.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let reset = limit.resetsAt {
                                    Text("下次重置：\(reset.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.abbreviation() ?? TimeZone.current.identifier)")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("重置时间未知").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(8)
                        }
                    }
                } else {
                    ContentUnavailableView("等待首次额度读取", systemImage: "chart.xyaxis.line",
                                           description: Text("完成一次成功刷新后，显示当前账户的历史与预测。"))
                }
                Text("五分钟内合并采样；重置、用量回退和超过 15 分钟的断采会切断趋势。预测基于近两小时连续样本，至少覆盖十分钟，仅供参考。保留周期与清除入口位于设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    private func chartPoints(for limit: UsageLimit) -> [HistoryChartPoint] {
        let cutoff = Date.now.addingTimeInterval(-Double(rangeDays) * 86_400)
        var result: [HistoryChartPoint] = []
        var segment = 0
        var previous: (Date, UsageLimit)?
        for sample in store.currentAccountHistory where sample.fetchedAt >= cutoff {
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
