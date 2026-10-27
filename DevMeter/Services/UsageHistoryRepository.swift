import Foundation

protocol UsageHistoryPersisting: Sendable {
    func load(retentionDays: Int, now: Date) async throws -> [UsageHistorySample]
    func record(_ sample: UsageHistorySample, retentionDays: Int, now: Date) async throws -> [UsageHistorySample]
    func clear() async throws
}

enum UsageHistoryError: LocalizedError {
    case invalidFile
    var errorDescription: String? { "历史文件损坏、过大或版本不兼容；原文件已保留，可在设置中清除后重新记录。" }
}

actor LocalUsageHistoryRepository: UsageHistoryPersisting {
    private struct Archive: Codable {
        let version: Int
        let samples: [UsageHistorySample]
    }

    private let fileURL: URL
    private var cached: [UsageHistorySample]?
    // 五分钟内合并采样；90 天也保持在约 26,000 条，避免常驻工具无界增长。
    static let maximumSamples = 30_000
    static let maximumBytes = 16 * 1_024 * 1_024

    init(fileURL: URL) { self.fileURL = fileURL }

    static func applicationRepository() -> LocalUsageHistoryRepository {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.zhaobinrui.devspace.meter", isDirectory: true)
        return LocalUsageHistoryRepository(fileURL: directory.appendingPathComponent("usage-history-v1.json"))
    }

    func load(retentionDays: Int, now: Date) throws -> [UsageHistorySample] {
        let existing = try read()
        let retained = prune(existing, retentionDays: retentionDays, now: now)
        if retained != existing { try write(retained) }
        return retained
    }

    func record(_ sample: UsageHistorySample, retentionDays: Int, now: Date) throws -> [UsageHistorySample] {
        guard isValid(sample), sample.fetchedAt <= now.addingTimeInterval(60) else {
            throw UsageHistoryError.invalidFile
        }
        var samples = try load(retentionDays: retentionDays, now: now)
        let slot = floor(sample.fetchedAt.timeIntervalSince1970 / 300)
        if let index = samples.lastIndex(where: {
            $0.accountKey == sample.accountKey && floor($0.fetchedAt.timeIntervalSince1970 / 300) == slot
        }) {
            if samples[index].fetchedAt >= sample.fetchedAt { return samples }
            samples[index] = sample
        } else {
            samples.append(sample)
        }
        samples = prune(samples, retentionDays: retentionDays, now: now)
        try write(samples)
        return samples
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        cached = []
    }

    private func read() throws -> [UsageHistorySample] {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cached = []
            return []
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= Self.maximumBytes else {
            throw UsageHistoryError.invalidFile
        }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1, archive.samples.count <= Self.maximumSamples,
                  archive.samples.allSatisfy(isValid) else { throw UsageHistoryError.invalidFile }
            cached = archive.samples.sorted { $0.fetchedAt < $1.fetchedAt }
            return cached ?? []
        } catch { throw UsageHistoryError.invalidFile }
    }

    private func isValid(_ sample: UsageHistorySample) -> Bool {
        sample.accountKey.count == 64 && sample.accountKey.allSatisfy { $0.isHexDigit }
            && sample.fetchedAt.timeIntervalSince1970.isFinite
            && !sample.limits.isEmpty && sample.limits.count <= 100
            && Set(sample.limits.map(\.id)).count == sample.limits.count
            && sample.limits.allSatisfy {
                !$0.id.isEmpty && $0.id.count <= 256 && $0.name.count <= 256
                    && (0...100).contains($0.usedPercent)
                    && ($0.windowDurationMinutes.map { $0 > 0 } ?? true)
                    && ($0.resetsAt?.timeIntervalSince1970.isFinite ?? true)
            }
    }

    private func prune(_ samples: [UsageHistorySample], retentionDays: Int, now: Date) -> [UsageHistorySample] {
        let cutoff = now.addingTimeInterval(-Double(min(90, max(1, retentionDays))) * 86_400)
        return Array(samples.filter { $0.fetchedAt >= cutoff && $0.fetchedAt <= now.addingTimeInterval(60) }
            .sorted { $0.fetchedAt < $1.fetchedAt }.suffix(Self.maximumSamples))
    }

    private func write(_ samples: [UsageHistorySample]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Archive(version: 1, samples: samples))
        guard data.count <= Self.maximumBytes else { throw UsageHistoryError.invalidFile }
        // 原子替换成功后才更新可信内存状态；写入失败不覆盖上一份数据。
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        cached = samples
    }
}
