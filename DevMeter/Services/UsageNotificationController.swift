import CryptoKit
import Foundation
import UserNotifications

struct UsageAlert: Equatable, Sendable {
    enum Kind: Sendable { case lowQuota, forecastRisk, refreshFailed }
    let id: String
    let kind: Kind

    var title: String {
        switch kind {
        case .lowQuota: "Codex 额度偏低"
        case .forecastRisk: "Codex 额度可能提前耗尽"
        case .refreshFailed: "DevMeter 持续无法刷新"
        }
    }

    var body: String {
        switch kind {
        case .lowQuota: "至少一个额度窗口已达到提醒阈值，请打开 DevMeter 查看。"
        case .forecastRisk: "按近期消耗速度，额度可能在重置前耗尽。预测仅供参考。"
        case .refreshFailed: "多次读取失败，当前数据可能过期。请打开 DevMeter 检查数据源。"
        }
    }
}

struct UsageAlertPolicy: Codable, Sendable {
    private(set) var deliveredIDs: [String] = []
    private var failureCount = 0
    private var failureStartedAt: Date?
    private var lastFailureAt: Date?
    private var failureID: String?

    mutating func success(
        snapshot: UsageSnapshot, forecasts: [UsageForecast], threshold: Int,
        lowEnabled: Bool, predictionEnabled: Bool
    ) -> [UsageAlert] {
        if let failureID { deliveredIDs.removeAll { $0 == failureID } }
        failureCount = 0
        failureStartedAt = nil
        lastFailureAt = nil
        failureID = nil
        guard let account = snapshot.accountKey else { return [] }
        var events: [UsageAlert] = []
        for limit in snapshot.limits {
            let scope = "\(account)|\(limit.id)|\(limit.resetsAt?.timeIntervalSince1970.description ?? "unknown")|\(limit.windowDurationMinutes ?? 0)"
            let lowID = Self.identifier("low|\(scope)|\(threshold)")
            // 回升越过阈值加 5 个百分点才重新布防，避免阈值附近反复通知。
            if limit.remainingPercent > threshold + 5 { deliveredIDs.removeAll { $0 == lowID } }
            if lowEnabled, limit.remainingPercent <= threshold,
               limit.resetsAt.map({ $0 > snapshot.fetchedAt }) ?? true,
               !deliveredIDs.contains(lowID) {
                events.append(UsageAlert(id: lowID, kind: .lowQuota))
            }
            let riskID = Self.identifier("risk|\(scope)")
            if predictionEnabled, (!lowEnabled || limit.remainingPercent > threshold),
               forecasts.first(where: { $0.id == limit.id })?.status == .atRisk,
               !deliveredIDs.contains(riskID), !events.contains(where: { $0.id == lowID }) {
                events.append(UsageAlert(id: riskID, kind: .forecastRisk))
            }
        }
        return events
    }

    mutating func failure(now: Date) -> UsageAlert? {
        // 重启或休眠造成的长间隔不计为连续故障；取消不会进入此路径。
        if let lastFailureAt, now.timeIntervalSince(lastFailureAt) > 900 || now < lastFailureAt {
            failureCount = 0
            failureStartedAt = nil
            failureID = nil
        }
        if failureStartedAt == nil {
            failureStartedAt = now
            failureID = UUID().uuidString
        }
        failureCount += 1
        lastFailureAt = now
        guard failureCount >= 3, let failureStartedAt,
              now.timeIntervalSince(failureStartedAt) >= 120, let failureID,
              !deliveredIDs.contains(failureID) else { return nil }
        return UsageAlert(id: failureID, kind: .refreshFailed)
    }

    mutating func markDelivered(_ alert: UsageAlert) {
        guard !deliveredIDs.contains(alert.id) else { return }
        deliveredIDs.append(alert.id)
        deliveredIDs = Array(deliveredIDs.suffix(256))
    }

    private static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum UsageNotificationPermission: String, Sendable {
    case notDetermined = "尚未申请权限"
    case denied = "系统未允许通知"
    case authorized = "系统已允许通知"
}

@MainActor
protocol UsageNotificationSending {
    func permission() async -> UsageNotificationPermission
    func requestPermission() async throws -> Bool
    func send(_ alert: UsageAlert) async throws
}

@MainActor
final class SystemUsageNotificationSender: UsageNotificationSending {
    private let center = UNUserNotificationCenter.current()

    func permission() async -> UsageNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(_ alert: UsageAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        // 通知不包含邮箱、账户标识、原始错误或其他开发内容。
        content.body = alert.body
        try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
    }
}
