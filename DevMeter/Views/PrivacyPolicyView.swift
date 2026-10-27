import SwiftUI

struct PrivacyPolicyView: View {
    let includesClaude: Bool
    var body: some View {
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
    }
}
