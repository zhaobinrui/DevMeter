import Foundation
import Darwin

enum ClaudeStatusLineError: LocalizedError {
    case notConnected, noQuota, invalidData, invalidFile, ioFailure

    var errorDescription: String? {
        switch self {
        case .notConnected: "尚未收到 Claude Code 状态行数据，请在设置中完成本地接入。"
        case .noQuota: "Claude Code 本次事件没有订阅额度窗口。登录方式、套餐或尚未产生响应都可能影响可用字段。"
        case .invalidData: "Claude Code 额度字段无法识别，已保留上次可信数据。"
        case .invalidFile: "Claude 本地快照损坏、过大或版本不兼容，已保留原文件。"
        case .ioFailure: "无法读写 Claude 本地快照，请检查文件权限。"
        }
    }
}

// 只解码官方 status line 的订阅窗口；context_window、费用、路径与会话内容均不进入模型。
enum ClaudeStatusLineDecoder {
    private struct Event: Decodable { let rate_limits: Windows? }
    private struct Windows: Decodable { let five_hour: Window?; let seven_day: Window? }
    private struct Window: Decodable { let used_percentage: Double?; let resets_at: Double? }

    static func limits(from data: Data) throws -> [UsageLimit] {
        guard data.count <= ClaudeStatusLineCapture.maximumInputBytes else { throw ClaudeStatusLineError.invalidData }
        do {
            let event = try JSONDecoder().decode(Event.self, from: data)
            return try [
                limit(event.rate_limits?.five_hour, id: "claude.five-hour", name: "5 小时额度", minutes: 300),
                limit(event.rate_limits?.seven_day, id: "claude.seven-day", name: "7 天额度", minutes: 10_080)
            ].compactMap { $0 }
        } catch { throw ClaudeStatusLineError.invalidData }
    }

    private static func limit(_ window: Window?, id: String, name: String, minutes: Int) throws -> UsageLimit? {
        guard let window else { return nil }
        guard let used = window.used_percentage, used.isFinite, (0...100).contains(used),
              window.resets_at.map({ $0.isFinite && $0 > 0 && $0 < 253_402_300_800 }) ?? true else {
            throw ClaudeStatusLineError.invalidData
        }
        // 展示模型使用整数；向上取已用量，避免把小数消耗显示成更多可用额度。
        return UsageLimit(id: id, name: name, windowDurationMinutes: minutes,
                          usedPercent: Int(used.rounded(.up)),
                          resetsAt: window.resets_at.map(Date.init(timeIntervalSince1970:)))
    }
}

struct ClaudeStatusLineCapture: Codable, Sendable {
    static let maximumInputBytes = 1_048_576
    static let maximumFileBytes = 16_384
    let version: Int
    let capturedAt: Date
    let limits: [UsageLimit]

    init(data: Data, now: Date) throws {
        version = 1
        capturedAt = now
        limits = try ClaudeStatusLineDecoder.limits(from: data)
    }

    func snapshot(now: Date) throws -> UsageSnapshot {
        guard version == 1, capturedAt.timeIntervalSince1970.isFinite,
              capturedAt.timeIntervalSince1970 > 0, capturedAt <= now.addingTimeInterval(60),
              limits.count <= 2, Set(limits.map(\.id)).count == limits.count,
              limits.allSatisfy({ limit in
                  let expected = limit.id == "claude.five-hour" ? ("5 小时额度", 300)
                      : limit.id == "claude.seven-day" ? ("7 天额度", 10_080) : nil
                  return expected.map { limit.name == $0.0 && limit.windowDurationMinutes == $0.1 } == true
                      && (0...100).contains(limit.usedPercent)
                      && (limit.resetsAt.map { $0.timeIntervalSince1970 > 0 && $0.timeIntervalSince1970 < 253_402_300_800 } ?? true)
              }) else { throw ClaudeStatusLineError.invalidFile }
        guard !limits.isEmpty else { throw ClaudeStatusLineError.noQuota }
        // 状态行没有可靠账户 ID，不能把不同登录或会话拼接成历史及预测基线。
        return UsageSnapshot(limits: limits, creditBalance: nil, sourceName: "Claude Code · 本地状态行",
                             fetchedAt: capturedAt, accountKey: nil)
    }
}

struct ClaudeStatusLineFile: Sendable {
    let url: URL

    static var applicationFile: Self {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.zhaobinrui.devspace.meter/providers", isDirectory: true)
        return Self(url: directory.appendingPathComponent("claude-statusline-v1.json"))
    }

    func read(now: Date) throws -> UsageSnapshot {
        // O_NOFOLLOW 与 fstat 检查同一描述符，避免按路径检查后被替换成链接或无限输入。
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ClaudeStatusLineError.notConnected }
            throw ClaudeStatusLineError.ioFailure
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_uid == getuid(), attributes.st_size <= Self.maximumReadBytes else {
            throw ClaudeStatusLineError.invalidFile
        }
        do {
            let data = try Self.readBounded(handle, maximum: ClaudeStatusLineCapture.maximumFileBytes)
            let capture = try JSONDecoder().decode(ClaudeStatusLineCapture.self, from: data)
            return try capture.snapshot(now: now)
        } catch let error as ClaudeStatusLineError { throw error }
        catch { throw ClaudeStatusLineError.invalidFile }
    }

    private static let maximumReadBytes = off_t(ClaudeStatusLineCapture.maximumFileBytes)

    func write(_ capture: ClaudeStatusLineCapture) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(capture)
            guard data.count <= ClaudeStatusLineCapture.maximumFileBytes else { throw ClaudeStatusLineError.invalidFile }
            let temporary = directory.appendingPathComponent(".claude-\(UUID().uuidString).tmp")
            // 先以 0600 创建临时文件，再原子替换；原始状态行 JSON 永不写入磁盘。
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw ClaudeStatusLineError.ioFailure }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            guard rename(temporary.path, url.path) == 0 else { throw ClaudeStatusLineError.ioFailure }
        } catch let error as ClaudeStatusLineError { throw error }
        catch { throw ClaudeStatusLineError.ioFailure }
    }

    func clear() throws {
        // unlink 只移除这一项，拒绝把异常目录当作缓存递归删除；链接也不会跟随到目标。
        guard unlink(url.path) == 0 || errno == ENOENT else { throw ClaudeStatusLineError.ioFailure }
    }

    static func readBounded(_ handle: FileHandle, maximum: Int) throws -> Data {
        var data = Data()
        while let part = try handle.read(upToCount: min(8_192, maximum + 1 - data.count)), !part.isEmpty {
            data.append(part)
            guard data.count <= maximum else { throw ClaudeStatusLineError.invalidData }
        }
        return data
    }
}

struct ClaudeStatusLineProvider: UsageProvider {
    let sourceName = "Claude Code · 本地状态行"
    let file: ClaudeStatusLineFile
    init(file: ClaudeStatusLineFile = .applicationFile) { self.file = file }

    func fetchSnapshot() async throws -> UsageSnapshot {
        try Task.checkCancellation()
        return try file.read(now: .now)
    }
}

enum ClaudeStatusLineCommand {
    static func run(arguments: [String], defaults: UserDefaults = .standard,
                    file: ClaudeStatusLineFile = .applicationFile,
                    input: FileHandle = .standardInput, output: FileHandle = .standardOutput,
                    errorOutput: FileHandle = .standardError) -> Int32 {
        let validatesOnly = arguments == ["--claude-statusline", "--validate-only"]
        guard validatesOnly || arguments == ["--claude-statusline"] else { return 1 }
        defaults.synchronize()
        // 手动配置 statusLine 不代替应用内授权；未授权时连 stdin 的原始事件也不读取。
        guard validatesOnly || ProviderAuthorization.isGranted(.claudeCode, defaults: defaults) else {
            try? errorOutput.write(contentsOf: Data("DevMeter: 请先在设置中授权 Claude Code 额度接收（状态 2）。\n".utf8))
            return 2
        }
        do {
            let data = try ClaudeStatusLineFile.readBounded(input, maximum: ClaudeStatusLineCapture.maximumInputBytes)
            let capture = try ClaudeStatusLineCapture(data: data, now: .now)
            if validatesOnly {
                try output.write(contentsOf: JSONEncoder().encode(capture))
            } else {
                defaults.synchronize()
                guard ProviderAuthorization.isGranted(.claudeCode, defaults: defaults) else { return 2 }
                try file.write(capture)
                let summary = capture.limits.map { "\($0.name)剩余 \($0.remainingPercent)%" }.joined(separator: " · ")
                let text = summary.isEmpty ? "Claude · 暂无订阅额度" : "Claude · \(summary)"
                try output.write(contentsOf: Data((text + "\n").utf8))
            }
            return 0
        } catch {
            // 不回显原输入、解析错误详情或路径，避免状态行把敏感内容带到终端或日志。
            try? errorOutput.write(contentsOf: Data("DevMeter: Claude 状态行接收失败。\n".utf8))
            return 1
        }
    }

    static func settingsJSON(executable: URL) -> String {
        // Claude 的 command 由它的 shell 解释；这里只为固定应用路径转义，不执行任何用户命令。
        let command = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "' --claude-statusline"
        let value = ["statusLine": ["type": "command", "command": command]]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
