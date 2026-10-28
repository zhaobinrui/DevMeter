import SwiftUI

struct ProviderAuthorizationView: View {
    let source: UsageSource
    let authorize: () -> Void
    @State private var showsPrivacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("授权读取 \(source.title) 额度", systemImage: "hand.raised")
                .font(.headline)
            Text(source.authorizationExplanation)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("尚未授权，未开始采集。可稍后决定，或在设置中随时撤销。授权不会把本地额度上传给 DevMeter。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("阅读隐私说明") { showsPrivacy = true }
            Button("允许读取 \(source.title) 额度", action: authorize)
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showsPrivacy) { PrivacyPolicyView(includesClaude: source == .claudeCode) }
    }
}
