import WidgetKit

@MainActor
final class WidgetSnapshotPublisher {
    func publish(_ display: SharedUsageSnapshot) {
        guard SharedUsageSnapshotStorage.save(display) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedUsageSnapshotStorage.widgetKind)
    }
}
