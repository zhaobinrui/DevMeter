# CodexMeter

CodexMeter 是一个原生 macOS 菜单栏工具，用于持续查看当前 ChatGPT/Codex 账户的剩余额度。它会在菜单栏显示所有额度窗口中最低的剩余百分比，并提供可常驻最顶层的悬浮卡片，方便随时观察额度变化。

## 主要功能

- 菜单栏实时显示最低剩余额度。
- 展示主窗口、次窗口等多个额度桶，不把不同额度合并成虚构的“总额度”。
- 提供跨桌面空间显示的置顶悬浮卡片，可拖动并记住位置。
- 支持显示或隐藏悬浮卡片，并可设置 0%～70% 的透明度。
- 支持 30 秒、1 分钟、2 分钟和 5 分钟刷新间隔。
- 刷新失败时保留上一次成功结果，同时展示错误提示。
- 提供 macOS WidgetKit 桌面小组件，显示主应用最近一次成功获取的额度。
- 可在局域网内向 Kindle 提供带随机配对令牌的只读电子墨水页面。
- 支持登录时自动启动。
- 集成 Sparkle 2 自动更新；配置公开更新源后可自动检查、下载并安装新版本。

## 工作原理

CodexMeter 通过本机 `codex app-server` 的 stdio JSONL 协议，以只读方式调用 `account/rateLimits/read`，再将返回结果转换为应用内部的额度模型并显示：

```text
codex app-server
        ↓
CodexLocalUsageProvider
        ↓
UsageSnapshot
   ┌────┼─────────────┐
   ↓    ↓             ↓
菜单栏  App Group     局域网 HTTP
浮窗    WidgetKit     Kindle 页面
```

应用不会抓取 Codex 界面、DOM、Cookie 或登录令牌，也不会修改 Codex 应用及其配置。

## 系统要求

- macOS 14.0 或更高版本。
- 支持 macOS 14 SDK 的 Xcode。
- 本机能够找到并运行 `codex`，且当前账户已完成登录。
- 构建可实际安装的 Widget 版本时，需要在 Apple Developer 账号中启用 `group.com.zhaobinrui.CodexMeter` App Group，并同时关联主应用和 Widget extension。

应用会从 `PATH`、常见 Codex CLI 安装目录，以及 Codex/ChatGPT 应用资源目录中查找 `codex` 可执行文件。

## 从源码启动

1. 克隆仓库并进入项目目录：

   ```bash
   git clone git@github.com:zhaobinrui/CodexMeter.git
   cd CodexMeter
   ```

2. 使用 Xcode 打开 `CodexMeter.xcodeproj`。
3. 如 Xcode 提示签名问题，在主应用和 `CodexMeterWidget` 两个 target 的 Signing & Capabilities 中选择自己的开发团队，并确认两者使用相同 App Group。
4. 选择 `CodexMeter` Scheme 和 `My Mac` 运行目标。
5. 按 `Command-R` 构建并运行。
6. 启动后在 macOS 菜单栏查找 `CX` 图标；悬浮额度卡片会按设置显示。

也可以在终端中完成 Debug 构建和测试：

```bash
xcodebuild \
  -project CodexMeter.xcodeproj \
  -scheme CodexMeter \
  -configuration Debug \
  -derivedDataPath /private/tmp/CodexMeterDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project CodexMeter.xcodeproj \
  -scheme CodexMeter \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/CodexMeterDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 日常使用

- 点击菜单栏中的 `CX` 图标可查看详细额度、手动刷新并进入设置。
- 在设置中可以调整自动刷新间隔、悬浮卡片显示状态及透明度。
- 悬浮卡片可以直接拖动，应用会记住其位置。
- 切换 Codex 账户后，只要 `codex app-server` 使用的本地登录状态已经切换，CodexMeter 会在下一次刷新时读取新账户的额度；也可以手动刷新立即确认。
- 关闭总开关后，应用会停止自动刷新，并停止 Kindle 局域网服务；重新启用后会按已保存的设置恢复。
- 首次运行主应用后，可在 macOS 桌面进入“编辑小组件”，搜索并添加“Codex 剩余额度”。Widget 显示主应用最近一次成功刷新的快照。
- 在设置中启用“发布到 Kindle”，将生成的局域网地址复制到同一网络中的 Kindle 浏览器。地址包含随机配对令牌，主应用退出后页面会停止服务。
- 在设置中启用“登录时自动启动”；如果系统要求确认，请前往“系统设置 > 通用 > 登录项与扩展”允许 CodexMeter。

## 配置自动更新

自动更新使用 [Sparkle 2](https://sparkle-project.org/)。项目默认不内置无效或需要登录的更新地址；正式打包时必须提供：

- `CODEXMETER_UPDATE_FEED_URL`：可匿名访问的 HTTPS `appcast.xml` 地址。
- `CODEXMETER_UPDATE_PUBLIC_ED_KEY`：Sparkle `generate_keys` 生成的 EdDSA 公钥。

可以在 Xcode 的 Build Settings 中把这两个名称添加为 User-Defined Setting。若通过命令行归档，也可以作为构建设置传入：

```bash
xcodebuild archive \
  -project CodexMeter.xcodeproj \
  -scheme CodexMeter \
  -configuration Release \
  -archivePath /private/tmp/CodexMeter.xcarchive \
  CODEXMETER_UPDATE_FEED_URL="https://updates.example.com/codexmeter/appcast.xml" \
  CODEXMETER_UPDATE_PUBLIC_ED_KEY="你的 Sparkle EdDSA 公钥"
```

当前 GitHub 仓库是私有仓库，客户端无法匿名读取其中的 Release 和 appcast。建议另建一个只存放签名安装包、appcast 和发布说明的公开静态更新站点，源代码仓库仍可保持私有。每次发布时使用 Sparkle 自带的 `generate_appcast` 生成并签名 appcast，再上传 DMG/ZIP 和 appcast。

## 归档 Release 版本

若只在自己的 Mac 上使用，可以直接在 Xcode 中运行，或选择 `Product > Archive` 后从 Organizer 导出应用。若需要分发给其他用户，建议使用 Apple Developer Program 提供的 `Developer ID Application` 证书签名，并完成公证。

1. 在 Xcode 中选择 `Any Mac` 或合适的 macOS 目标。
2. 选择 `Product > Archive`。
3. 在 Organizer 中选择新生成的归档，然后点击 `Distribute App`。
4. 面向站外分发时选择 Developer ID 方式，完成签名和导出。
5. 确认归档中已经写入正确的 `SUFeedURL` 和 `SUPublicEDKey`，再导出 `CodexMeter.app` 并制作 DMG。

Apple 官方参考：[分发 macOS 应用](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)、[创建 Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。

## 制作 DMG

个人安装使用时，直接运行仓库内的一键打包脚本：

```bash
./scripts/package_dmg.sh
```

脚本会完成 Release 构建、嵌套组件签名、DMG 创建和完整性验证，最终文件写入 `dist/CodexMeter-<版本号>.dmg`。默认使用 ad-hoc 签名，适合在当前 Mac 上个人安装，不要求付费 Apple Developer Program 或公证。也可以指定本机已有的签名身份：

```bash
CODEXMETER_SIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" \
  ./scripts/package_dmg.sh
```

如需公开分发，则应改用 `Developer ID Application` 证书，对应用和 DMG 完成公证并附加票据。首次使用时先保存一次公证凭据：

```bash
xcrun notarytool store-credentials "CodexMeterNotary"
xcrun notarytool submit "/path/to/CodexMeter.dmg" \
  --keychain-profile "CodexMeterNotary" \
  --wait
xcrun stapler staple "/path/to/CodexMeter.dmg"
xcrun stapler validate "/path/to/CodexMeter.dmg"
```

公证流程需要有效的 Apple Developer 账号、Developer ID 签名以及对应的公证凭据。详情参见 Apple 的[公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 安装 DMG

1. 双击打开 `CodexMeter.dmg`。
2. 将 `CodexMeter.app` 拖入 `Applications` 文件夹。
3. 从“应用程序”中启动 CodexMeter。
4. 应用是菜单栏工具，不会显示普通 Dock 图标；启动后请在顶部菜单栏查找 `CX`。

脚本默认生成的 ad-hoc 签名构建仅适合本机个人使用。首次打开时如被系统拦截，可以在 Finder 中按住 Control 点击应用并选择“打开”；对外分发应使用 Developer ID 签名和公证版本。

## 当前限制

- 本地 `codex app-server` 协议仍属于实验性接口，未来协议变化可能需要适配。
- 当前只读取本机 Codex 登录账户的额度，不包含 OpenAI API 组织用量。
- Widget 不会自行启动 `codex app-server`；主应用长时间未运行时，它会继续显示最近一次成功快照。
- Kindle 页面只在主应用运行且 Mac 与 Kindle 位于同一局域网时可用，目前不提供公网中继。
- 未配置公开 appcast 和 EdDSA 公钥的构建会明确禁用自动更新。

更多实现范围与开发约定请参阅 [`AGENTS.md`](AGENTS.md)。
