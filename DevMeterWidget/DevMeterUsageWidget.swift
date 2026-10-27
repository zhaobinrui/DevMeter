import SwiftUI
import WidgetKit

struct DevMeterWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedUsageSnapshot?
}

struct DevMeterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevMeterWidgetEntry {
        DevMeterWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DevMeterWidgetEntry) -> Void) {
        completion(DevMeterWidgetEntry(date: .now, snapshot: loadSnapshot(context: context)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DevMeterWidgetEntry>) -> Void) {
        let entry = DevMeterWidgetEntry(date: .now, snapshot: loadSnapshot(context: context))
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func loadSnapshot(context: Context) -> SharedUsageSnapshot? {
        context.isPreview ? .preview : SharedUsageSnapshotStorage.load()
    }
}

struct DevMeterUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedUsageSnapshotStorage.widgetKind,
            provider: DevMeterWidgetProvider()
        ) { entry in
            DevMeterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("DevMeter 用量")
        .description("显示 DevMeter 所选来源最近一次收到的额度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct DevMeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DevMeterWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot,
           let constrained = snapshot.mostConstrainedLimit {
            switch family {
            case .systemMedium:
                mediumView(snapshot: snapshot, constrained: constrained)
            default:
                smallView(snapshot: snapshot, constrained: constrained)
            }
        } else {
            ContentUnavailableView(
                "等待额度",
                systemImage: "gauge.with.dots.needle.0percent",
                description: Text("\(entry.snapshot?.sourceName ?? "当前来源") · 请在 DevMeter 完成接入或刷新")
            )
        }
    }

    private func smallView(
        snapshot: SharedUsageSnapshot,
        constrained: SharedUsageLimit
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(snapshot.sourceName ?? "Codex", systemImage: "gauge.with.dots.needle.50percent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(constrained.remainingPercent)%")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color(for: constrained.remainingPercent))
            Text(constrained.name)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
            updatedText(snapshot.fetchedAt)
        }
    }

    private func mediumView(
        snapshot: SharedUsageSnapshot,
        constrained: SharedUsageLimit
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.sourceName ?? "Codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(constrained.remainingPercent)%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color(for: constrained.remainingPercent))
                Spacer(minLength: 4)
                updatedText(snapshot.fetchedAt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(Array(snapshot.limits.prefix(3))) { limit in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(limit.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(limit.remainingPercent)%")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        ProgressView(value: Double(limit.remainingPercent), total: 100)
                            .tint(color(for: limit.remainingPercent))
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func updatedText(_ date: Date) -> some View {
        Text(date, style: .relative)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func color(for remaining: Int) -> Color {
        switch remaining {
        case 0..<10:
            return .red
        case 10..<40:
            return .orange
        default:
            return .green
        }
    }
}

private extension SharedUsageSnapshot {
    static let preview = SharedUsageSnapshot(
        limits: [
            SharedUsageLimit(
                id: "codex.primary",
                name: "5 小时额度",
                remainingPercent: 68,
                resetsAt: .now.addingTimeInterval(3_600)
            ),
            SharedUsageLimit(
                id: "codex.secondary",
                name: "周额度",
                remainingPercent: 42,
                resetsAt: .now.addingTimeInterval(86_400)
            )
        ],
        creditBalance: nil,
        fetchedAt: .now
    )
}
