import Foundation
import CryptoKit

final class CodexLocalUsageProvider: UsageProvider, @unchecked Sendable {
    let sourceName = "Codex app-server"

    private let configuredExecutableURL: URL?
    private let timeout: Duration
    private let identitySalt: String
    private let stateLock = NSLock()
    private var activeSession: CodexAppServerSession?

    init(
        executableURL: URL? = nil,
        timeout: Duration = .seconds(8),
        identitySalt: String = UUID().uuidString
    ) {
        configuredExecutableURL = executableURL
        self.timeout = timeout
        self.identitySalt = identitySalt
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let executableURL = try configuredExecutableURL ?? CodexExecutableLocator().locate()
        let session = CodexAppServerSession(executableURL: executableURL)
        try install(session)

        defer {
            session.stop()
            clear(session)
        }

        let reading = try await session.readRateLimits(timeout: timeout)
        let before = CodexAccountIdentity.key(from: reading.accountBefore, salt: identitySalt)
        let after = CodexAccountIdentity.key(from: reading.accountAfter, salt: identitySalt)
        guard before == after else {
            throw UsageProviderError.protocolFailure("读取期间账户发生变化，请重新刷新")
        }
        return try CodexRateLimitsDecoder.decodeSnapshot(
            from: reading.rateLimits,
            sourceName: sourceName,
            fetchedAt: .now,
            accountKey: before
        )
    }

    func shutdown() async {
        stopActiveSession()
    }

    deinit {
        stopActiveSession()
    }

    private func stopActiveSession() {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()
        session?.stop()
    }

    private func install(_ session: CodexAppServerSession) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard activeSession == nil else {
            throw UsageProviderError.unavailable
        }
        activeSession = session
    }

    private func clear(_ session: CodexAppServerSession) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if activeSession === session {
            activeSession = nil
        }
    }
}

struct CodexRateLimitsDecoder {
    static func decodeSnapshot(
        from responseData: Data,
        sourceName: String = "Codex app-server",
        fetchedAt: Date = .now,
        accountKey: String? = nil
    ) throws -> UsageSnapshot {
        let envelope: JSONRPCResponse<GetAccountRateLimitsResponse>

        do {
            envelope = try JSONDecoder().decode(
                JSONRPCResponse<GetAccountRateLimitsResponse>.self,
                from: responseData
            )
        } catch {
            throw UsageProviderError.invalidResponse
        }

        if let error = envelope.error {
            throw UsageProviderError.protocolFailure(error.summary)
        }

        guard envelope.id == CodexAppServerSession.rateLimitsRequestID,
              let response = envelope.result else {
            throw UsageProviderError.invalidResponse
        }

        var buckets: [(key: String, snapshot: RateLimitSnapshot)] = []
        if let rateLimitsByLimitID = response.rateLimitsByLimitId,
           !rateLimitsByLimitID.isEmpty {
            buckets = rateLimitsByLimitID
                .map { (key: $0.key, snapshot: $0.value) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        } else if let rateLimits = response.rateLimits {
            buckets = [(key: rateLimits.limitId ?? "codex", snapshot: rateLimits)]
        }

        let limits = buckets.flatMap { bucket in
            makeLimits(for: bucket.snapshot, fallbackID: bucket.key)
        }

        guard !limits.isEmpty else {
            throw UsageProviderError.noUsageLimits
        }
        guard Set(limits.map(\.id)).count == limits.count else {
            throw UsageProviderError.invalidResponse
        }

        return UsageSnapshot(
            limits: limits,
            creditBalance: creditBalance(in: buckets),
            sourceName: sourceName,
            fetchedAt: fetchedAt,
            accountKey: accountKey
        )
    }

    private static func makeLimits(
        for snapshot: RateLimitSnapshot,
        fallbackID: String
    ) -> [UsageLimit] {
        let bucketID = normalized(snapshot.limitId) ?? fallbackID
        let bucketName = normalized(snapshot.limitName)
        var limits: [UsageLimit] = []

        if let primary = snapshot.primary {
            limits.append(
                makeLimit(
                    window: primary,
                    id: "\(bucketID).primary",
                    roleName: "主要额度",
                    bucketName: bucketName
                )
            )
        }

        if let secondary = snapshot.secondary {
            limits.append(
                makeLimit(
                    window: secondary,
                    id: "\(bucketID).secondary",
                    roleName: "次要额度",
                    bucketName: bucketName
                )
            )
        }

        return limits
    }

    private static func makeLimit(
        window: RateLimitWindow,
        id: String,
        roleName: String,
        bucketName: String?
    ) -> UsageLimit {
        let windowName = quotaWindowName(
            durationMinutes: window.windowDurationMins,
            fallback: roleName
        )
        let name = bucketName.map { "\($0) · \(windowName)" } ?? windowName

        return UsageLimit(
            id: id,
            name: name,
            windowDurationMinutes: window.windowDurationMins,
            // 协议未承诺百分比范围；越界值按原有显示语义归一化，避免超额时反而读不到额度。
            usedPercent: max(0, min(100, window.usedPercent)),
            resetsAt: window.resetsAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
        )
    }

    private static func quotaWindowName(
        durationMinutes: Int?,
        fallback: String
    ) -> String {
        guard let durationMinutes else { return fallback }

        switch durationMinutes {
        case 300:
            return "5 小时额度"
        case 1_440:
            return "每日额度"
        case 10_080:
            return "周额度"
        default:
            if durationMinutes.isMultiple(of: 1_440) {
                return "\(durationMinutes / 1_440) 天额度"
            }
            if durationMinutes.isMultiple(of: 60) {
                return "\(durationMinutes / 60) 小时额度"
            }
            return "\(durationMinutes) 分钟额度"
        }
    }

    private static func creditBalance(
        in buckets: [(key: String, snapshot: RateLimitSnapshot)]
    ) -> String? {
        for bucket in buckets {
            guard let credits = bucket.snapshot.credits else { continue }
            if credits.unlimited == true {
                return "无限"
            }
            if let balance = normalized(credits.balance) {
                return balance
            }
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private struct CodexExecutableLocator {
    private let fileManager = FileManager.default
    private let environment = ProcessInfo.processInfo.environment

    func locate() throws -> URL {
        var candidates: [URL] = []

        if let path = environment["PATH"] {
            candidates.append(contentsOf:
                contentsOfPath(path).map { directory in
                    URL(fileURLWithPath: directory, isDirectory: true)
                        .appendingPathComponent("codex")
                }
            )
        }

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            homeDirectory.appendingPathComponent(".codex/bin/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        ])
        candidates.append(contentsOf: nvmCandidates(in: homeDirectory))

        var visitedPaths = Set<String>()
        for candidate in candidates where visitedPaths.insert(candidate.path).inserted {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }

        throw UsageProviderError.executableNotFound
    }

    private func contentsOfPath(_ path: String) -> [String] {
        path.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    }

    private func nvmCandidates(in homeDirectory: URL) -> [URL] {
        let versionsDirectory = homeDirectory.appendingPathComponent(
            ".nvm/versions/node",
            isDirectory: true
        )
        guard let versions = try? fileManager.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return versions
            .sorted {
                $0.lastPathComponent.compare(
                    $1.lastPathComponent,
                    options: .numeric
                ) == .orderedDescending
            }
            .map { $0.appendingPathComponent("bin/codex") }
    }
}

private struct CodexUsageReading: Sendable {
    let rateLimits: Data
    let accountBefore: Data?
    let accountAfter: Data?
}

enum CodexAccountIdentity {
    static func key(from data: Data?, salt: String) -> String? {
        guard let data,
              let response = try? JSONDecoder().decode(JSONRPCResponse<AccountResponse>.self, from: data),
              response.error == nil, let account = response.result?.account,
              account.type == "chatgpt", let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty, let plan = account.planType,
              ["free", "go", "plus", "pro", "prolite"].contains(plan) else { return nil }
        // 当前协议不返回组织工作区 ID。同邮箱的组织账户不能可靠分区，因此不持久化它们。
        guard let bytes = try? JSONEncoder().encode([salt, email.lowercased(), plan]) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private struct AccountResponse: Decodable { let account: Account? }
    private struct Account: Decodable {
        let type: String
        let email: String?
        let planType: String?
    }
}

private final class CodexAppServerSession: @unchecked Sendable {
    static let initializeRequestID = 0
    static let rateLimitsRequestID = 1
    static let accountBeforeRequestID = 2
    static let accountAfterRequestID = 3

    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let stateLock = NSLock()
    private var isStopped = false

    init(executableURL: URL) {
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
    }

    func readRateLimits(timeout: Duration) async throws -> CodexUsageReading {
        do {
            try start()
            try send(InitializeRequest())
        } catch let error as UsageProviderError {
            stop()
            throw error
        } catch {
            stop()
            throw UsageProviderError.launchFailed
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CodexUsageReading.self) { group in
                group.addTask {
                    try await self.readRateLimitsResponse()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    try Task.checkCancellation()
                    throw UsageProviderError.timedOut
                }

                do {
                    guard let response = try await group.next() else {
                        throw UsageProviderError.invalidResponse
                    }
                    group.cancelAll()
                    stop()
                    return response
                } catch {
                    group.cancelAll()
                    stop()
                    throw error
                }
            }
        } onCancel: {
            self.stop()
        }
    }

    func stop() {
        stateLock.lock()
        guard !isStopped else {
            stateLock.unlock()
            return
        }
        isStopped = true
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        stateLock.unlock()
    }

    deinit {
        stop()
    }

    private func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isStopped else {
            throw CancellationError()
        }

        do {
            try process.run()
        } catch {
            throw UsageProviderError.launchFailed
        }
    }

    private func readRateLimitsResponse() async throws -> CodexUsageReading {
        var didCompleteInitialization = false
        var accountBefore: Data?
        var rateLimits: Data?

        do {
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8) else {
                    throw UsageProviderError.invalidResponse
                }

                let header: JSONRPCResponseHeader
                do {
                    header = try JSONDecoder().decode(JSONRPCResponseHeader.self, from: data)
                } catch {
                    throw UsageProviderError.invalidResponse
                }

                if let error = header.error,
                   (header.id == Self.initializeRequestID ||
                    header.id == Self.rateLimitsRequestID) {
                    throw UsageProviderError.protocolFailure(error.summary)
                }
                if header.method == "account/updated", accountBefore != nil {
                    throw UsageProviderError.protocolFailure("读取期间账户发生变化，请重新刷新")
                }

                if header.id == Self.initializeRequestID,
                   !didCompleteInitialization {
                    try send(InitializedNotification())
                    try send(AccountReadRequest(id: Self.accountBeforeRequestID))
                    didCompleteInitialization = true
                } else if header.id == Self.accountBeforeRequestID {
                    accountBefore = data
                    try send(RateLimitsRequest())
                } else if header.id == Self.rateLimitsRequestID {
                    rateLimits = data
                    try send(AccountReadRequest(id: Self.accountAfterRequestID))
                } else if header.id == Self.accountAfterRequestID, let rateLimits {
                    return CodexUsageReading(rateLimits: rateLimits, accountBefore: accountBefore, accountAfter: data)
                }
            }
        } catch let error as UsageProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageProviderError.invalidResponse
        }

        if !process.isRunning {
            throw UsageProviderError.processExited(process.terminationStatus)
        }
        throw UsageProviderError.invalidResponse
    }

    private func send<Message: Encodable>(_ message: Message) throws {
        var data: Data
        do {
            data = try JSONEncoder().encode(message)
            data.append(0x0A)
        } catch {
            throw UsageProviderError.invalidResponse
        }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isStopped, process.isRunning else {
            throw UsageProviderError.unavailable
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw UsageProviderError.unavailable
        }
    }
}

private struct InitializeRequest: Encodable {
    let method = "initialize"
    let id = CodexAppServerSession.initializeRequestID
    let params = InitializeParams()
}

private struct InitializeParams: Encodable {
    let clientInfo = ClientInfo()
    let capabilities = InitializeCapabilities()
}

private struct ClientInfo: Encodable {
    let name = "codex_meter"
    let title = "DevMeter"
    let version = "0.1.0"
}

private struct InitializeCapabilities: Encodable {
    let experimentalApi = true
}

private struct InitializedNotification: Encodable {
    let method = "initialized"
    let params = EmptyParams()
}

private struct RateLimitsRequest: Encodable {
    let method = "account/rateLimits/read"
    let id = CodexAppServerSession.rateLimitsRequestID
}

private struct AccountReadRequest: Encodable {
    let method = "account/read"
    let id: Int
    let params = AccountReadParams()
}

private struct AccountReadParams: Encodable { let refreshToken = false }

private struct EmptyParams: Encodable {}

private struct JSONRPCResponseHeader: Decodable {
    let id: Int?
    let method: String?
    let error: JSONRPCErrorPayload?
}

private struct JSONRPCResponse<Result: Decodable>: Decodable {
    let id: Int?
    let result: Result?
    let error: JSONRPCErrorPayload?
}

private struct JSONRPCErrorPayload: Decodable {
    let code: Int?
    let message: String

    var summary: String {
        let singleLine = message.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(240))
    }
}

private struct GetAccountRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

private struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?
}

private struct CreditsSnapshot: Decodable {
    let balance: String?
    let unlimited: Bool?
}
