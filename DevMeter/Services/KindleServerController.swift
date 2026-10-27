import Combine
import Foundation

@MainActor
final class KindleServerController: ObservableObject {
    @Published private(set) var state: KindleHTTPServer.State = .stopped
    @Published private(set) var accessURL: URL?

    private let store: UsageStore
    private let port: UInt16
    private let token: String
    private var server: KindleHTTPServer?
    private var cancellables = Set<AnyCancellable>()

    init(
        store: UsageStore,
        defaults: UserDefaults = .standard,
        port: UInt16 = 8_765
    ) {
        self.store = store
        self.port = port
        token = Self.loadOrCreateToken(defaults: defaults)
    }

    func start() {
        guard cancellables.isEmpty else { return }

        store.$publishToKindle
            .combineLatest(store.$isEnabled)
            .map { publishToKindle, meterEnabled in
                publishToKindle && meterEnabled
            }
            .removeDuplicates()
            .sink { [weak self] shouldRun in
                self?.setEnabled(shouldRun)
            }
            .store(in: &cancellables)

        store.$snapshot
            .combineLatest(store.$lastError)
            .sink { [weak self] snapshot, error in
                self?.updatePage(snapshot: snapshot, lastError: error)
            }
            .store(in: &cancellables)
    }

    func retry() {
        guard store.publishToKindle else { return }
        stopServer()
        startServer()
    }

    var statusText: String {
        switch state {
        case .stopped:
            return "未启动"
        case .starting:
            return "正在启动"
        case .ready:
            return "局域网服务已启动"
        case let .failed(message):
            return "启动失败：\(message)"
        }
    }

    private func setEnabled(_ enabled: Bool) {
        enabled ? startServer() : stopServer()
    }

    private func startServer() {
        guard server == nil else { return }

        let server = KindleHTTPServer(token: token, port: port)
        server.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.state = state
                self?.updateAccessURL(for: state)
            }
        }
        server.updatePage(KindlePageRenderer.render(snapshot: store.snapshot, lastError: store.lastError))
        self.server = server

        do {
            try server.start()
        } catch {
            state = .failed(error.localizedDescription)
            self.server = nil
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        state = .stopped
        accessURL = nil
    }

    private func updatePage(snapshot: UsageSnapshot?, lastError: String?) {
        server?.updatePage(KindlePageRenderer.render(snapshot: snapshot, lastError: lastError))
    }

    private func updateAccessURL(for state: KindleHTTPServer.State) {
        guard case let .ready(activePort) = state else {
            accessURL = nil
            return
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = LocalNetworkAddress.preferredIPv4Address()
            ?? ProcessInfo.processInfo.hostName
        components.port = Int(activePort)
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        accessURL = components.url
    }

    private static func loadOrCreateToken(defaults: UserDefaults) -> String {
        if let token = defaults.string(forKey: Keys.token), !token.isEmpty {
            return token
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(token, forKey: Keys.token)
        return token
    }

    private enum Keys {
        static let token = "kindle.pairingToken"
    }
}
