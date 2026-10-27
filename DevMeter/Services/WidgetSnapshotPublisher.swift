import WidgetKit

@MainActor
final class WidgetSnapshotPublisher {
    func publish(_ snapshot: UsageSnapshot) {
        let sharedSnapshot = SharedUsageSnapshot(
            limits: snapshot.limits.map {
                SharedUsageLimit(
                    id: $0.id,
                    name: $0.name,
                    remainingPercent: $0.remainingPercent,
                    resetsAt: $0.resetsAt
                )
            },
            creditBalance: snapshot.creditBalance,
            fetchedAt: snapshot.fetchedAt,
            sourceName: snapshot.sourceName
        )

        guard SharedUsageSnapshotStorage.save(sharedSnapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedUsageSnapshotStorage.widgetKind)
    }

    func selectProvider(_ source: UsageSource) {
        _ = SharedUsageSnapshotStorage.save(SharedUsageSnapshot(limits: [], creditBalance: nil,
                                                               fetchedAt: .now, sourceName: source.title))
        WidgetCenter.shared.reloadTimelines(ofKind: SharedUsageSnapshotStorage.widgetKind)
    }
}
