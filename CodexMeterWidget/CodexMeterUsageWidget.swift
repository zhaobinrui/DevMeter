import SwiftUI
import WidgetKit

struct CodexMeterWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedUsageSnapshot?
}

struct CodexMeterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexMeterWidgetEntry {
        CodexMeterWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexMeterWidgetEntry) -> Void) {
        completion(CodexMeterWidgetEntry(date: .now, snapshot: loadSnapshot(context: context)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexMeterWidgetEntry>) -> Void) {
        let entry = CodexMeterWidgetEntry(date: .now, snapshot: loadSnapshot(context: context))
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func loadSnapshot(context: Context) -> SharedUsageSnapshot? {
        context.isPreview ? .preview : SharedUsageSnapshotStorage.load()
    }
}

struct CodexMeterUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedUsageSnapshotStorage.widgetKind,
            provider: CodexMeterWidgetProvider()
        ) { entry in
            CodexMeterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Codex 剩余额度")
        .description("显示本机 Codex 当前账户最近一次获取到的额度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CodexMeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexMeterWidgetEntry

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
                description: Text("请先启动 CodexMeter")
            )
        }
    }

    private func smallView(
        snapshot: SharedUsageSnapshot,
        constrained: SharedUsageLimit
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CodexMeter", systemImage: "gauge.with.dots.needle.50percent")
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
                Text("最低剩余")
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
