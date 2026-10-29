import Foundation
import Network

final class KindleHTTPServer: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case stopped
        case starting
        case ready(port: UInt16)
        case failed(String)
    }

    var onStateChange: (@Sendable (State) -> Void)?

    let token: String
    let requestedPort: UInt16

    private let queue = DispatchQueue(
        label: "com.zhaobinrui.devspace.meter.kindle-server"
    )
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var pageProvider: @Sendable () -> String = { "" }

    init(token: String, port: UInt16 = 8_765) {
        self.token = token
        requestedPort = port
    }

    func updatePage(_ html: String) {
        updatePageProvider { html }
    }

    func updatePageProvider(_ provider: @escaping @Sendable () -> String) {
        stateLock.lock()
        pageProvider = provider
        stateLock.unlock()
    }

    func start() throws {
        stateLock.lock()
        guard listener == nil else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let port = NWEndpoint.Port(rawValue: requestedPort) else {
            throw KindleHTTPServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: port)

        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        stateLock.lock()
        self.listener = listener
        stateLock.unlock()

        onStateChange?(.starting)
        listener.start(queue: queue)
    }

    func stop() {
        stateLock.lock()
        let listener = listener
        self.listener = nil
        stateLock.unlock()

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        onStateChange?(.stopped)
    }

    deinit {
        stop()
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            onStateChange?(.ready(port: listenerPort ?? requestedPort))
        case let .failed(error):
            releaseListenerAfterFailure()
            onStateChange?(.failed(error.localizedDescription))
        case .cancelled:
            onStateChange?(.stopped)
        default:
            break
        }
    }

    private func releaseListenerAfterFailure() {
        stateLock.lock()
        let listener = listener
        self.listener = nil
        stateLock.unlock()

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
    }

    private var listenerPort: UInt16? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listener?.port?.rawValue
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2_048) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var requestData = buffer
            if let data {
                requestData.append(data)
            }

            if requestData.count > 8_192 {
                send(status: "413 Payload Too Large", body: "Request too large", contentType: "text/plain; charset=utf-8", on: connection)
                return
            }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                respond(to: requestData, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receiveRequest(on: connection, buffer: requestData)
            }
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard let request = String(data: requestData, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            send(status: "400 Bad Request", body: "Bad request", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else {
            send(status: "400 Bad Request", body: "Bad request", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }
        guard parts[0] == "GET" else {
            send(status: "405 Method Not Allowed", body: "Read only", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        guard let components = URLComponents(string: "http://devmeter.local\(parts[1])"),
              components.path == "/" else {
            send(status: "404 Not Found", body: "Not found", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        let suppliedToken = components.queryItems?.first(where: { $0.name == "token" })?.value
        guard suppliedToken == token else {
            send(status: "401 Unauthorized", body: "Pairing token required", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        stateLock.lock()
        let provider = pageProvider
        stateLock.unlock()
        // 只在配对校验通过后渲染；锁外按请求时间判断过期，不增加后台定时器或阻塞状态更新。
        send(status: "200 OK", body: provider(), contentType: "text/html; charset=utf-8", on: connection)
    }

    private func send(
        status: String,
        body: String,
        contentType: String,
        on connection: NWConnection
    ) {
        send(status: status, body: Data(body.utf8), contentType: contentType, on: connection)
    }

    private func send(
        status: String,
        body: Data,
        contentType: String,
        on connection: NWConnection
    ) {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum KindleHTTPServerError: LocalizedError {
    case invalidPort

    var errorDescription: String? {
        "Kindle 服务端口无效"
    }
}
