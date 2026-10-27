import Foundation
#if !APP_STORE
import Sparkle
#endif

@MainActor
final class UpdateController: ObservableObject {
    #if APP_STORE
    let isConfigured = false
    var statusText: String { "由 Mac App Store 提供更新" }
    var explanation: String { "此版本通过 Mac App Store 更新。" }
    func checkForUpdates() {}
    #else
    let updaterController: SPUStandardUpdaterController
    let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feedURL = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedFeedURL = URL(string: feedURL ?? "")
        isConfigured = parsedFeedURL?.scheme == "https"
            && parsedFeedURL?.host != nil
            && !(publicKey ?? "").isEmpty

        updaterController = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var statusText: String {
        isConfigured ? "已启用自动检查和安装" : "尚未配置公开更新源"
    }

    var explanation: String { "本地预览版使用 Sparkle；只有配置公开 HTTPS 更新源与签名公钥后才启用更新。" }

    func checkForUpdates() {
        guard isConfigured else { return }
        updaterController.checkForUpdates(nil)
    }
    #endif
}
