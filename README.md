# CodexMeter

CodexMeter 是一个原生 macOS 菜单栏工具，用于持续查看当前 ChatGPT/Codex 账户的剩余额度。它会在菜单栏显示所有额度窗口中最低的剩余百分比，并提供可常驻最顶层的悬浮卡片，方便随时观察额度变化。

## 主要功能

- 菜单栏实时显示最低剩余额度。
- 展示主窗口、次窗口等多个额度桶，不把不同额度合并成虚构的“总额度”。
- 提供跨桌面空间显示的置顶悬浮卡片，可拖动并记住位置。
- 支持显示或隐藏悬浮卡片，并可设置 0%～70% 的透明度。
- 支持 30 秒、1 分钟、2 分钟和 5 分钟刷新间隔。
- 刷新失败时保留上一次成功结果，同时展示错误提示。

## 工作原理

CodexMeter 通过本机 `codex app-server` 的 stdio JSONL 协议，以只读方式调用 `account/rateLimits/read`，再将返回结果转换为应用内部的额度模型并显示：

```text
codex app-server
        ↓
CodexLocalUsageProvider
        ↓
UsageSnapshot
        ↓
菜单栏 / 置顶悬浮卡片
```

应用不会抓取 Codex 界面、DOM、Cookie 或登录令牌，也不会修改 Codex 应用及其配置。

## 系统要求

- macOS 14.0 或更高版本。
- 支持 macOS 14 SDK 的 Xcode。
- 本机能够找到并运行 `codex`，且当前账户已完成登录。

应用会从 `PATH`、常见 Codex CLI 安装目录，以及 Codex/ChatGPT 应用资源目录中查找 `codex` 可执行文件。

## 从源码启动

1. 克隆仓库并进入项目目录：

   ```bash
   git clone git@github.com:zhaobinrui/CodexMeter.git
   cd CodexMeter
   ```

2. 使用 Xcode 打开 `CodexMeter.xcodeproj`。
3. 如 Xcode 提示签名问题，在项目的 Signing & Capabilities 中选择自己的开发团队。
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
- 关闭总开关后，应用会停止自动刷新。

## 归档 Release 版本

若只在自己的 Mac 上使用，可以直接在 Xcode 中运行，或选择 `Product > Archive` 后从 Organizer 导出应用。若需要分发给其他用户，建议使用 Apple Developer Program 提供的 `Developer ID Application` 证书签名，并完成公证。

1. 在 Xcode 中选择 `Any Mac` 或合适的 macOS 目标。
2. 选择 `Product > Archive`。
3. 在 Organizer 中选择新生成的归档，然后点击 `Distribute App`。
4. 面向站外分发时选择 Developer ID 方式，完成签名和导出。
5. 得到 `CodexMeter.app` 后，再制作 DMG 安装包。

Apple 官方参考：[分发 macOS 应用](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)、[创建 Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。

## 制作 DMG

将以下命令中的 `/path/to/CodexMeter.app` 和输出路径替换为实际位置：

```bash
mkdir -p /private/tmp/CodexMeter-dmg
cp -R "/path/to/CodexMeter.app" /private/tmp/CodexMeter-dmg/
ln -s /Applications /private/tmp/CodexMeter-dmg/Applications
hdiutil create \
  -volname CodexMeter \
  -srcfolder /private/tmp/CodexMeter-dmg \
  -ov \
  -format UDZO \
  "/path/to/CodexMeter.dmg"
```

分发前建议对 DMG 进行公证并附加票据。首次使用时先保存一次公证凭据：

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

未签名的开发构建仅适合本机测试。首次打开时如被系统拦截，可以在 Finder 中按住 Control 点击应用并选择“打开”；对外分发应使用签名和公证版本。

## 当前限制

- 本地 `codex app-server` 协议仍属于实验性接口，未来协议变化可能需要适配。
- 当前只读取本机 Codex 登录账户的额度，不包含 OpenAI API 组织用量。
- 当前版本尚未实现 WidgetKit 桌面小组件、Kindle 页面、自动更新和登录时启动。

更多实现范围与开发约定请参阅 [`AGENTS.md`](AGENTS.md)。
