import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            isEnabled ? start() : stop()
        }
    }

    @Published var publishToKindle: Bool {
        didSet {
            defaults.set(publishToKindle, forKey: Keys.publishToKindle)
        }
    }

    @Published var showsFloatingPanel: Bool {
        didSet {
            defaults.set(showsFloatingPanel, forKey: Keys.showsFloatingPanel)
        }
    }

    @Published var floatingPanelOpacity: Double {
        didSet {
            defaults.set(floatingPanelOpacity, forKey: Keys.floatingPanelOpacity)
        }
    }

    @Published var refreshIntervalSeconds: Int {
        didSet {
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
            restartIfNeeded()
        }
    }

    private let provider: any UsageProvider
    private let defaults: UserDefaults
    private let didUpdateSnapshot: @MainActor (UsageSnapshot) -> Void
    private var refreshTask: Task<Void, Never>?

    init(
        provider: any UsageProvider,
        defaults: UserDefaults = .standard,
        didUpdateSnapshot: @escaping @MainActor (UsageSnapshot) -> Void = { _ in }
    ) {
        self.provider = provider
        self.defaults = defaults
        self.didUpdateSnapshot = didUpdateSnapshot
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        publishToKindle = defaults.object(forKey: Keys.publishToKindle) as? Bool ?? false
        showsFloatingPanel = defaults.object(forKey: Keys.showsFloatingPanel) as? Bool ?? true
        let storedPanelOpacity = defaults.object(forKey: Keys.floatingPanelOpacity) as? Double ?? 1
        floatingPanelOpacity = min(1, max(0.3, storedPanelOpacity))
        refreshIntervalSeconds = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Int ?? 60
    }

    var menuTitle: String {
        guard isEnabled else { return "CX —" }
        guard let remaining = snapshot?.mostConstrainedLimit?.remainingPercent else { return "CX …" }
        return "CX \(remaining)%"
    }

    var sourceName: String {
        provider.sourceName
    }

    var symbolName: String {
        guard isEnabled, let remaining = snapshot?.mostConstrainedLimit?.remainingPercent else {
            return "gauge.with.dots.needle.0percent"
        }

        switch remaining {
        case 0..<10:
            return "gauge.with.dots.needle.100percent"
        case 10..<40:
            return "gauge.with.dots.needle.67percent"
        default:
            return "gauge.with.dots.needle.33percent"
        }
    }

    func start() {
        guard isEnabled, refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                let interval = self.refreshIntervalSeconds

                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false

        Task {
            await provider.shutdown()
        }
    }

    func refresh() async {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updatedSnapshot = try await provider.fetchSnapshot()
            snapshot = updatedSnapshot
            didUpdateSnapshot(updatedSnapshot)
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }

    private func restartIfNeeded() {
        guard isEnabled, refreshTask != nil else { return }
        stop()
        start()
    }

    private enum Keys {
        static let isEnabled = "meter.isEnabled"
        static let publishToKindle = "kindle.isEnabled"
        static let showsFloatingPanel = "floatingPanel.isEnabled"
        static let floatingPanelOpacity = "floatingPanel.opacity"
        static let refreshIntervalSeconds = "meter.refreshIntervalSeconds"
    }
}
