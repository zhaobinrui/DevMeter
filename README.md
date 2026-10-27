# DevMeter

DevMeter 是一个原生 macOS 菜单栏工具，用于持续查看当前 ChatGPT/Codex 账户的剩余额度。它会在菜单栏显示所有额度窗口中最低的剩余百分比，并提供可常驻最顶层的悬浮卡片，方便随时观察额度变化。

本仓库由 CodexMeter 原地演进而来，提交历史保持不变。当前版本先保留已验证的 Codex Provider
能力，现已加入本地额度历史、基础趋势预测和可选系统提醒。Claude Code 已加入基于官方状态行
的本地适配与来源切换，真实账户链路仍待验收；其他 AI Provider 与 Agent 活动状态仍属后续阶段。

## 主要功能

- 菜单栏实时显示最低剩余额度。
- Codex / Claude Code 可独立切换，分别保留可信快照与错误；只刷新所选来源，不合并跨来源总额度。
- 展示主窗口、次窗口等多个额度桶，不把不同额度合并成虚构的“总额度”。
- 提供跨桌面空间显示的置顶悬浮卡片，可拖动并记住位置。
- 支持显示或隐藏悬浮卡片，并可设置 0%～70% 的透明度。
- 支持 30 秒、1 分钟、2 分钟和 5 分钟刷新间隔。
- 刷新失败时保留上一次成功结果，同时展示错误提示；菜单栏以“旧”标记过期数据，连续失败时退避刷新。
- 从菜单栏打开独立“历史与预测”窗口，查看最近 24 小时、7 天或 30 天的额度曲线。
- 历史默认保留 30 天，可改为 7/90 天、暂停记录或清除；五分钟内合并采样，最多 30,000 条、16 MiB。
- 基础预测使用近两小时的连续样本，至少三次采样且跨度十分钟；重置、用量回退和超过 15 分钟的断采后重新积累。
- 系统通知默认关闭，主动开启时才申请权限；支持低额度、可能提前耗尽和持续刷新失败提醒。
- 提供 macOS WidgetKit 桌面小组件，显示主应用最近一次成功获取的额度。
- 可在局域网内向 Kindle 提供带随机配对令牌的只读电子墨水页面。
- 支持登录时自动启动。
- 直接分发预览集成 Sparkle 2；配置公开更新源后可检查并安装预览更新。商店版由 Mac App Store 更新。

## 工作原理

DevMeter 通过本机 `codex app-server` 的 stdio JSONL 协议，以只读方式调用 `account/read` 和 `account/rateLimits/read`，再将返回结果转换为应用内部的额度模型并显示：

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
Claude Code 使用主动配置的 status line 接收入口，只保留订阅窗口及时间；
不会读取登录凭据，也不会主动请求模型来获取额度。

## 系统要求

- macOS 14.0 或更高版本。
- 支持 Swift 6 及 macOS 14 Deployment Target 的 Xcode。
- 直接分发预览使用 `DevMeter` scheme；商店构建使用独立的 `DevMeterAppStore` scheme（App Sandbox、StoreKit 2，无 Sparkle）。
- 本机能够找到并运行 `codex`，且当前账户已完成登录。
- 构建可实际安装的 Widget 版本时，需要在 Apple Developer 账号中启用 `group.com.zhaobinrui.devspace.meter` App Group，并同时关联主应用和 Widget extension。迁移版本还需暂时保留旧 `group.com.zhaobinrui.CodexMeter` 权限，以读取旧 Widget 快照。

应用会从 `PATH`、常见 Codex CLI 安装目录，以及 Codex/ChatGPT 应用资源目录中查找 `codex` 可执行文件。

## 从源码启动

1. 克隆仓库并进入项目目录：

   ```bash
   git clone git@github.com:zhaobinrui/DevMeter.git
   cd DevMeter
   ```

2. 使用 Xcode 打开 `DevMeter.xcodeproj`。
3. 如 Xcode 提示签名问题，在主应用和 `DevMeterWidget` 两个 target 的 Signing & Capabilities 中选择自己的开发团队，并确认两者使用相同 App Group。
4. 选择 `DevMeter` Scheme 和 `My Mac` 运行目标。
5. 按 `Command-R` 构建并运行。
6. 启动后在 macOS 菜单栏查找 `DM` 图标；悬浮额度卡片会按设置显示。

也可以在终端中完成 Debug 构建和测试：

```bash
xcodebuild \
  -project DevMeter.xcodeproj \
  -scheme DevMeter \
  -configuration Debug \
  -derivedDataPath /private/tmp/DevMeterDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project DevMeter.xcodeproj \
  -scheme DevMeter \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/DevMeterDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 日常使用

- 点击菜单栏中的 `DM` 图标可查看详细额度、手动刷新并进入设置。
- 菜单内的“浮窗”和“历史与预测”均可再次点击隐藏，再点击恢复；关闭历史窗口后仍可重新打开。
- “设置”显式打开独立设置窗口；再次点击会将同一个窗口置前，也可在应用处于前台时按 `Command-,`。
- 在设置中可以调整自动刷新间隔、悬浮卡片显示状态及透明度。
- 悬浮卡片可以直接拖动，应用会记住其位置。
- 切换 Codex 账户后，只要 `codex app-server` 使用的本地登录状态已经切换，DevMeter 会在下一次刷新时读取新账户的额度；也可以手动刷新立即确认。
- 关闭总开关后，应用会停止自动刷新，并停止 Kindle 局域网服务；重新启用后会按已保存的设置恢复。
- 首次运行主应用后，可在 macOS 桌面进入“编辑小组件”，搜索并添加“DevMeter 用量”。Widget 显示主应用最近一次成功刷新的快照。
- 在设置中启用“发布到 Kindle”，将生成的局域网地址复制到同一网络中的 Kindle 浏览器。地址包含随机配对令牌，主应用退出后页面会停止服务。
- 在设置中启用“登录时自动启动”；如果系统要求确认，请前往“系统设置 > 通用 > 登录项与扩展”允许 DevMeter。

## 本地历史、预测与提醒

点击菜单栏中的“历史与预测”，或在应用处于前台时按 `Command-Shift-H`，显示或隐藏独立窗口。
图表展示采样时的已用百分比；窗口重置、用量回退或断采时断开曲线，不把这些变化计算为消耗。
预测仅回答近期消耗速度下是否可能在重置前耗尽，不估算可发送的消息条数，也不合并不同额度桶。
样本不足、数据过期、重置时间未知或已到期时明确降级，不自行把额度恢复为 100%。

历史归属通过只读账户接口的个人邮箱与套餐生成本机加盐 SHA-256 分组；邮箱仅用于内存计算，
不写入文件、不展示、不上传。当前协议没有稳定工作区 ID，因此组织账户、未知套餐或身份缺失
时仍展示当前额度，但不记录历史、不预测，也不发送账户额度提醒。切换个人账户或套餐会隔离
历史分组。历史只保存额度窗口元数据，不包含 Credits、凭据、提示词、代码或原始错误。
文件位于本机 Application Support 的 `com.zhaobinrui.devspace.meter/usage-history-v1.json`，
采用版本化 JSON、原子保存和仅当前用户可读写的文件权限，不与 Widget 或 Kindle 共享历史。
关闭记录会停止新增采样；保留周期仍可清理到期记录，手动清除会删除所有账户的历史文件。

在设置的“提醒”中主动启用系统通知。默认低额度阈值为剩余 10%，可选择 5%/20%；
同一账户与窗口去重，应用重启保留已发提醒记录。额度回升超过阈值 5 个百分点或窗口重置后可再次提醒。
持续读取失败至少三次且持续两分钟才提醒，成功恢复后重新布防。可能提前耗尽提醒默认关闭。
通知只显示通用状态，不包含邮箱、账户标识或原始错误。系统拒绝权限时保留明确状态，不反复申请。

## Claude Code 本地接入

在设置中复制状态行配置并手动合并到 Claude Code 设置，收到事件后再选择 Claude Code。
已有状态行需先保留原配置；DevMeter 不自动修改外部设置。
当前展示 5 小时与 7 天订阅窗口及已提供的重置时间，缺失时明确降级；
它不等同于 Claude 会话上下文或 API 账单。没有稳定账户标识时不提供 Claude 历史、预测或账户额度提醒。
多来源切换属于 Pro，本地预览版可体验。
具体接入、隐私边界、验证结果和后续 Provider 准入规则见 [Claude Code 接入说明](docs/claude-code-provider.md)。

## 隐私与反馈

设置顶部的「帮助与隐私」提供离线隐私说明、GitHub Issues 反馈入口和版本信息。
「复制支持信息」仅复制版本、系统、来源与通用状态；不附带账号、额度、原始错误、路径或
Kindle 配对地址，也不会自动发送反馈。完整的数据范围、保留与清除方式见
[隐私说明](docs/privacy-policy.md)。

## 商店发行与 Pro 买断

已确认首发采用 Mac App Store 的 Free + Pro，Pro 为非消耗型一次性买断，中国大陆目标价格
人民币 58 元。商品 ID 为 `com.zhaobinrui.devspace.meter.pro.lifetime`。客户端显示 Apple 返回的
当地价格，不硬编码扣款金额；支付宝/微信等可用方式由用户的 Apple 账户和地区决定。

Pro 解锁新增历史采样、基础预测及预测提醒；Free 仍可查看当前额度和使用基础提醒。
退款撤权不删除已有历史，历史查看、保留策略与清除继续可用。权益只来自 StoreKit 已验证交易，
不使用偏好中的布尔值冒充购买凭据；购买、取消、待批准、恢复与失败各自显示状态。
首次启动只读取 Apple 本地权益，只有用户主动点击恢复时才执行 `AppStore.sync()`。
直接分发预览仍可体验功能，不发起真实收款；商店版由 Mac App Store 更新。

**当前未完成正式发行或真实付费验收**：本机无有效开发/分发证书，尚无 Apple Developer 账号；
App Store Connect 商品、签名沙盒中的 Codex 数据访问、商业数据源适用范围和真实交易均待验证。
`DevMeterPayments` scheme 和 `.storekit` 只用于本地模拟交易，不代表商品已经上线。
本轮模拟购买与恢复断言通过，退款后的权益撤销断言仍失败，尚不能验收付费闭环。
完整步骤、当前阻塞和证据要求见 [`release/acceptance.md`](release/acceptance.md)。

## 配置直接分发预览的更新

直接分发预览使用 [Sparkle 2](https://sparkle-project.org/)。项目默认不内置无效或需要登录的更新地址；准备预览更新源时需要提供：

- `DEVMETER_UPDATE_FEED_URL`：可匿名访问的 HTTPS `appcast.xml` 地址。
- `DEVMETER_UPDATE_PUBLIC_ED_KEY`：Sparkle `generate_keys` 生成的 EdDSA 公钥。

可以在 Xcode 的 Build Settings 中把这两个名称添加为 User-Defined Setting。若通过命令行归档，也可以作为构建设置传入：

```bash
xcodebuild archive \
  -project DevMeter.xcodeproj \
  -scheme DevMeter \
  -configuration Release \
  -archivePath /private/tmp/DevMeter.xcarchive \
  DEVMETER_UPDATE_FEED_URL="https://updates.example.com/devmeter/appcast.xml" \
  DEVMETER_UPDATE_PUBLIC_ED_KEY="你的 Sparkle EdDSA 公钥"
```

Sparkle 更新源必须是无需登录即可访问的 HTTPS 地址。建议使用只存放签名安装包、appcast 和
发布说明的公开静态更新站点，不让客户端依赖 GitHub 登录状态。每次发布时使用 Sparkle 自带的
`generate_appcast` 生成并签名 appcast，再上传 DMG/ZIP 和 appcast。

## 从 CodexMeter 迁移

- 主应用标识已迁移为 `com.zhaobinrui.devspace.meter`，Widget 标识为
  `com.zhaobinrui.devspace.meter.widget`。
- 首次启动会迁移旧 CodexMeter 的刷新、浮窗、Kindle 和窗口位置偏好；已有新值不会被覆盖。
- 新 App Group 会在首次读取时接收旧 Widget 快照，之后只写入新组。
- 正式签名迁移版本需要同时授权新旧两个 App Group；确认用户完成过渡后，才能在后续主版本中
  移除旧组权限。
- Bundle Identifier 已变化，旧 CodexMeter 登录项不会自动变成 DevMeter 登录项；用户确认
  DevMeter 正常运行后应移除旧应用，并在 DevMeter 设置中重新启用登录启动。

## 归档 Release 版本

若只在自己的 Mac 上使用，可以直接在 Xcode 中运行，或选择 `Product > Archive` 后从 Organizer 导出应用。若需要分发给其他用户，建议使用 Apple Developer Program 提供的 `Developer ID Application` 证书签名，并完成公证。

1. 在 Xcode 中选择 `Any Mac` 或合适的 macOS 目标。
2. 选择 `Product > Archive`。
3. 在 Organizer 中选择新生成的归档，然后点击 `Distribute App`。
4. 面向站外分发时选择 Developer ID 方式，完成签名和导出。
5. 确认归档中已经写入正确的 `SUFeedURL` 和 `SUPublicEDKey`，再导出 `DevMeter.app` 并制作 DMG。

Apple 官方参考：[分发 macOS 应用](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)、[创建 Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。

## 制作 DMG

个人安装使用时，直接运行仓库内的一键打包脚本：

```bash
./scripts/package_dmg.sh
```

脚本会完成 Release 构建、嵌套组件签名、DMG 创建和完整性验证，最终文件写入 `dist/DevMeter-<版本号>.dmg`。默认使用 ad-hoc 签名，适合在当前 Mac 上个人安装，不要求付费 Apple Developer Program 或公证。也可以指定本机已有的签名身份：

```bash
DEVMETER_SIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" \
  ./scripts/package_dmg.sh
```

如需公开分发，则应改用 `Developer ID Application` 证书，对应用和 DMG 完成公证并附加票据。首次使用时先保存一次公证凭据：

```bash
xcrun notarytool store-credentials "DevMeterNotary"
xcrun notarytool submit "/path/to/DevMeter.dmg" \
  --keychain-profile "DevMeterNotary" \
  --wait
xcrun stapler staple "/path/to/DevMeter.dmg"
xcrun stapler validate "/path/to/DevMeter.dmg"
```

公证流程需要有效的 Apple Developer 账号、Developer ID 签名以及对应的公证凭据。详情参见 Apple 的[公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 安装 DMG

1. 双击打开 `DevMeter.dmg`。
2. 将 `DevMeter.app` 拖入 `Applications` 文件夹。
3. 从“应用程序”中启动 DevMeter。
4. 应用是菜单栏工具，不会显示普通 Dock 图标；启动后请在顶部菜单栏查找 `DM`。

脚本默认生成的 ad-hoc 签名构建仅适合本机个人使用。首次打开时如被系统拦截，可以在 Finder 中按住 Control 点击应用并选择“打开”；对外分发应使用 Developer ID 签名和公证版本。

## 当前限制

- 本地 `codex app-server` 协议仍属于实验性接口，未来协议变化可能需要适配。
- 当前只读取本机 Codex 登录账户的额度，不包含 OpenAI API 组织用量。
- Widget 不会自行启动 `codex app-server`；主应用长时间未运行时，它会继续显示最近一次成功快照。
- Kindle 页面只在主应用运行且 Mac 与 Kindle 位于同一局域网时可用，目前不提供公网中继。
- 未配置公开 appcast 和 EdDSA 公钥的构建会明确禁用自动更新。

更多实现范围与开发约定请参阅 [`AGENTS.md`](AGENTS.md)。
