import XCTest
@testable import DevMeter

final class KindleHTTPServerTests: XCTestCase {
    func testServer_rendersOnEveryAuthorizedRequest_andNeverRendersBeforePairing() async throws {
        let server = KindleHTTPServer(token: "pair-token", port: 0)
        let ready = expectation(description: "Dynamic page server ready")
        let port = LockedPort()
        let counter = LockedPageCounter()
        server.onStateChange = { state in
            if case let .ready(activePort) = state { port.value = activePort; ready.fulfill() }
        }
        server.updatePageProvider { "page-\(counter.next())" }
        try server.start()
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let activePort = try XCTUnwrap(port.value)
        let rejected = try await request(URL(string: "http://127.0.0.1:\(activePort)/")!)
        XCTAssertEqual(rejected.statusCode, 401)
        let first = try await request(URL(string: "http://127.0.0.1:\(activePort)/?token=pair-token")!)
        let second = try await request(URL(string: "http://127.0.0.1:\(activePort)/?token=pair-token")!)
        XCTAssertEqual(first.body, "page-1")
        XCTAssertEqual(second.body, "page-2")
    }

    func testServer_requiresTokenAndServesLatestPage() async throws {
        let server = KindleHTTPServer(token: "pair-token", port: 0)
        let ready = expectation(description: "Kindle server is ready")
        let port = LockedPort()
        server.onStateChange = { state in
            guard case let .ready(activePort) = state else { return }
            port.value = activePort
            ready.fulfill()
        }
        server.updatePage("<html><body>quota: 64%</body></html>")
        try server.start()
        defer { server.stop() }

        await fulfillment(of: [ready], timeout: 3)
        let activePort = try XCTUnwrap(port.value)

        let authorized = try await request(
            URL(string: "http://127.0.0.1:\(activePort)/?token=pair-token")!
        )
        XCTAssertEqual(authorized.statusCode, 200)
        XCTAssertTrue(authorized.body.contains("quota: 64%"))

        let unauthorized = try await request(
            URL(string: "http://127.0.0.1:\(activePort)/")!
        )
        XCTAssertEqual(unauthorized.statusCode, 401)
    }

    private func request(_ url: URL) async throws -> (statusCode: Int, body: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        return (httpResponse.statusCode, String(decoding: data, as: UTF8.self))
    }
}

private final class LockedPageCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class LockedPort: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: UInt16?

    var value: UInt16? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
