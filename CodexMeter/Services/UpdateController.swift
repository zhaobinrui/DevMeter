import Foundation
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
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

    func checkForUpdates() {
        guard isConfigured else { return }
        updaterController.checkForUpdates(nil)
    }
}
