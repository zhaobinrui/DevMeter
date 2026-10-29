import SwiftUI

struct PrivacyPolicyView: View {
    let includesClaude: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("隐私说明").font(.title2.bold())
                    Text("本说明可离线阅读，描述当前版本的数据处理方式。")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(PrivacyNotice.sections(includesClaude: includesClaude)) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title).font(.headline)
                            Text(section.body).textSelection(.enabled)
                        }
                    }
                    Link("联系与反馈（GitHub Issues）", destination: SupportInformation.feedbackURL)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 所有入口共用说明窗口，关闭按钮留在滚动区外，避免长正文挤出关闭操作。
            Divider()
            HStack {
                Spacer()
                Button("关闭", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("privacyNotice.close")
            }.padding(14)
        }
        .frame(width: 480, height: 580)
    }
}
