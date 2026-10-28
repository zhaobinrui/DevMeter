# DevMeter 独立发行与付费验收

当前结论：**尚未通过正式发行/真实付费验收**。工程构建、替身测试和 Xcode 本地交易测试
必须分别记录，不能代替 Apple 签名、App Store Connect 沙盒、审核及正式交易。

## 已确认的销售方案

- 渠道：Mac App Store，Free + Pro。
- Pro：非消耗型一次性买断，目标中国大陆价格人民币 58 元，无自动续费。
- 商品 ID：`com.zhaobinrui.devspace.meter.pro.lifetime`。
- 实际展示金额取自 StoreKit `displayPrice`；App Store Connect 中必须选择并核验中国大陆
  CNY 58 价格点。若平台没有该价格点，需与产品负责人确认，不能在客户端伪造价格。
- 支付由 Apple 处理，中国大陆 Apple 账户可用的支付宝/微信等方式由 Apple 决定。
- 不引入自建付款服务器，不上传额度、历史、代码、提示词或 Provider 凭据。
- Free 保留当前额度与基础提醒。Pro 解锁新增历史采样、基础预测与预测提醒。
  退款/撤权停止新增 Pro 工作，但保留历史查看、保留策略和清除入口。
- 直接分发的 `DevMeter` scheme 是不收费的本地预览；`DevMeterAppStore` 才是商店目标，
  启用 App Sandbox，独立链接，不包含 Sparkle。两者不是可混用的付款渠道。

## 发行与内购执行记录（2026-10-27）

- macOS 27.0.1 / Apple Silicon：普通 `DevMeter` Debug 构建与测试通过，62 项通过、1 项跳过。
  跳过的是必须使用专用 scheme 的原生 StoreKit 测试，不能将其计为支付验收通过。
- `DevMeterAppStore` Debug 构建、Release Intel/Apple Silicon 通用构建通过。
  候选包不含 Sparkle 或 `.storekit`，主应用与 Widget 都包含隐私清单。
- 发行脚本拒绝错误 Bundle ID、单一架构、缺少清单、夹带 Sparkle/模拟商品等 6 项测试通过。
- 原生 `DevMeterPayments` 测试 **1 项失败**：¥58 商品加载、购买、重启后权益读取与恢复断言
  通过；退款后 10 秒内权益撤销断言失败。`SKTestSession` 的交易已有 `cancelDate`，
  StoreKit 2 `currentEntitlements` 中同一交易仍返回 `revocationDate=nil`；额外诊断监听也未收到
  退款更新事件。原因尚未确认，保留失败断言，不能用清空测试交易或替身通过来替代验收。
- 无证书机的原生交易测试临时移除了测试宿主的 App Group 权限并使用 ad-hoc 签名，
  仅用于本地模拟；这不证明正式 App Sandbox 能读取 Codex 数据。
- 新增购买设置页的真实 macOS 交互检查未完成：工程包与临时显示副本启动后，界面工具
  绑定超时；临时进程已退出。既有窗口单测通过不能替代新增界面与辅助功能验收。

本轮工程候选包位于 `/private/tmp/DevMeterAppStoreCandidate-20261027-final/DevMeter.app`，
检查报告位于同目录 `candidate-report.json`。这些是未通过商店分发签名的临时构建；
源代码包含工作区未提交修改，既不是正式发行包，也不是可收费下载。

随后新增的 Claude Code Provider 验证另见 [接入说明](../docs/claude-code-provider.md)。
其本地接收与合成数据测试不会解除本页已有的签名、退款、真实来源和实机验收阻塞。

## 自动化命令

```sh
# 输出真实未通过项。当前预检返回 2 是“尚不能发行”，不是脚本故障。
python3 release/release.py preflight

# 无签名通用工程候选包，不能标记为 Beta/Release 或商店已通过。
python3 release/release.py candidate --output /private/tmp/DevMeterAppStoreCandidate

# 核心回归；专用原生支付测试由下面的 scheme 单独运行。
xcodebuild -project DevMeter.xcodeproj -scheme DevMeter -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/DevMeterPhase1DerivedData \
  CODE_SIGNING_ALLOWED=NO build test

# 本地模拟商品，不产生真实扣款。常规签名准备好后优先直接运行此 scheme。
xcodebuild -project DevMeter.xcodeproj -scheme DevMeterPayments -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/DevMeterPhase1DerivedData \
  -only-testing:DevMeterTests/StoreKitAcceptanceTests \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60 test

# 只为无证书开发机验证本地交易的临时测试宿主使用；不生成正式商店签名或沙盒验收证据。
# 此命令覆盖的是测试宿主 entitlements，正式 DevMeterAppStore.entitlements 保持不变。
xcodebuild -project DevMeter.xcodeproj -scheme DevMeterPayments -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/DevMeterPhase1DerivedData \
  -only-testing:DevMeterTests/StoreKitAcceptanceTests \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60 \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM= build test

python3 -m unittest discover -s release -p 'test_*.py' -v
```

有证书与 provisioning profiles 后，可用 `release.py archive --team-id TEAM_ID --output ABSOLUTE_PATH`
归档并导出；工具不自动上传或发布。`verify --signed APP_PATH` 核查商店分发签名、主应用与
Widget 的沙盒权限、架构、隐私清单以及未夹带 Sparkle/StoreKit 测试配置。

## 必须补齐的外部条件与人工证据

- [ ] Apple Developer 付费账号；在 Xcode 中配置开发/分发证书与主应用、Widget 的 App Group profiles。
  当前本机 `security find-identity -v -p codesigning` 为 0 个有效身份；用户确认尚未有开发者账号。
- [ ] App Store Connect 应用记录、商品、价格点、销售地域，以及由账号持有人完成的付费协议、
  税务与收款资料。仓库不代签条款，不虚构销售主体、隐私政策或退款承诺。
- [ ] 核对当前 Codex app-server 认证的商业适用范围。官方页面限制其认证用于 commercial/hosted
  services；该本地只读工具是否适用、是否需要另行接入或书面许可，仍须确认。
- [ ] 在真正签名的 App Sandbox 中完成 Codex 安装/登录状态发现、授权读取、重启、失效与恢复。
  当前普通 CLI 方案不能因无沙盒构建可用就视作商店适配成功；不得为上架关闭正式沙盒。
- [ ] 用真实 App Store Connect 商品和沙盒 Apple 账户跑通购买、取消、待批准、恢复、离线重启、
  退款撤权；先解决上文的本地退款权益不撤销失败。Xcode `.storekit` 中的 ¥58 不等于真实商品已配置。
- [ ] 经 TestFlight/商店分发验证安装、更新、卸载后恢复权益与数据迁移；商店版更新由商店负责。
- [ ] macOS 14 与当前 macOS 实机验收，记录架构、版本/构建号及发行包 SHA-256。
- [ ] 菜单栏、浮窗、历史、设置、键盘/VoiceOver、登录项、通知、Widget 与可选 Kindle 交互。
- [ ] 用户确认的商店说明、支持入口、隐私政策与截图；不得把未实现的多 Provider/Agent 监控写入商品承诺。

## 隐私与反馈入口的本地实现

已加入设置内离线隐私说明、固定 GitHub Issues 链接、版本信息和主动复制支持信息。
复制内容仅包含版本、系统版本、来源和通用状态，不含账号、额度、原始错误、路径或配对令牌；
不自动提交反馈。支持信息白名单、状态选择、链接范围及原生说明页加载均有测试。
本次新增 5 项测试，全量结果为 85 项通过、0 项失败、1 项专用支付测试跳过；
普通应用与独立商店目标的 Debug 构建通过。
新增设置控件的真实点击验证仍需补齐：本轮界面工具绑定超时，不能以窗口加载测试代替。
公开政策页面的发布 URL、App Store Connect 元数据和审核截图仍属于后续发行配置。

## Provider 授权与状态 127 排查（2026-10-27）

- 对用户正在运行的 Xcode Debug 进程只读提取 PATH，确认只有系统目录。自动找到的 CLI 是
  nvm v24.13.0 下的 npm 入口；同一入口在该 PATH 下 `--version` 返回 127 和
  `env: node: No such file or directory`，只补入配套 Node 的 bin 后返回 0 / codex-cli 0.142.0。
  修复仅调整 DevMeter 所启动子进程的 PATH，不安装依赖、不修改 shell 配置。
- 新增按 Provider、读取范围版本保存的主动授权。无记录的首次/升级启动不自动采集；
  自动和手动读取共用授权检查。撤销取消采集、拒绝迟到结果、清空当前展示与对应内存缓存，
  已保存历史保留。Claude 接收命令在读 stdin 前检查授权，拒绝返回 2；仅校验模式不写快照。
- 当前普通 Debug 构建和全量单元测试通过：**97 项通过、0 项失败、1 项专用支付测试跳过**。
  独立 `DevMeterAppStore` Debug 构建通过；本轮未重跑付费交易，不解除上文退款验收阻塞。
- 已通过真实 macOS 交互核对新版浮窗的读取说明、禁用刷新、隐私说明打开/Escape 关闭，
  以及 Command+, 设置窗口中的 Codex/Claude 独立授权说明和按钮。未代用户点击真实账户的允许
  或撤销按钮；这两条采集状态转换由测试替身验证，真实账户完整流程仍需用户主动授权后验收。
- 原生 CLI 已验证：未授权且 stdin 写端保持打开时立即返回 2；合成输入的仅校验返回 0，
  输出只有 version/capturedAt/limits 并过滤敏感字段，未写用户快照。
- 原有用户运行实例未替换；UI 检查使用 `/private/tmp` 下构建。源码变更需要重新构建并退出
  旧实例才会生效。正式签名 Sandbox、macOS 14 与真实 Claude 事件仍未验收。

完整错误表、Node 依赖区别及检查步骤见 [Provider 排障说明](../docs/provider-troubleshooting.md)。

## 隐私弹窗关闭修复（2026-10-28）

- 在用户实际运行的 Xcode Debug 应用中复现：浮窗授权入口打开的隐私说明没有关闭按钮；
  本次 Escape 未关闭，使用系统 Command+. 取消操作退出了原弹窗。此前未完整检查所有入口的关闭控件。
- 原因是设置页单独包装了关闭按钮，授权入口直接呈现只有正文的 `PrivacyPolicyView`。
  现将固定尺寸、滚动正文、底部关闭按钮与 Escape 快捷键统一放进共享弹窗，所有入口复用。
  关闭按钮位于滚动区外，不随长文移出可见区域。
- macOS 27.0.1 / Apple Silicon 实机：浮窗打开后滚到底部，关闭按钮仍存在，点击后返回浮窗；
  重新打开后 Escape 可关闭。设置帮助入口的按钮关闭、Claude 授权入口的 Escape 关闭也均通过。
  未点击真实账户授权或反馈链接，未更改 Provider 权限与数据。
- 普通 `DevMeter` Debug 构建与全量测试通过：97 项通过、0 项失败、1 项专用支付测试跳过；
  独立 `DevMeterAppStore` Debug 构建通过。本次未验证 macOS 14 或正式签名 Sandbox。
- 实机复测使用 `/private/tmp/DevMeterPhase1DerivedData` 中的修复构建，用户原实例的弹窗已解卡，
  原运行程序未覆盖；重新在 Xcode 运行后使用新实现。

## 浮窗标题拖动修复（2026-10-28）

- 旧实现只开启 `isMovableByWindowBackground`，没有为 SwiftUI 标题内容提供明确的拖动事件路径。
  现将图标与标题区域设为 AppKit 事件接收区，接受未激活时的首次鼠标按下，并处理拖动与释放。
  使用 `convertPoint(toScreen:)` 在全局逻辑点中计算移动量，不混用不同缩放屏幕的像素坐标，
  不安装全局鼠标监听，不新增系统权限要求。
- 刷新、隐藏及正文按钮位于拖动区之外；装饰边框禁用命中测试。标题区提供手形光标和拖动提示。
  父窗口有隐私 sheet、窗口不可移动或手势结束时停止移动。
- 不可缩放的浮窗使用 `setFrameUsingName(_:force: true)` 恢复位置；收到移动通知后显式保存。
  普通数据刷新在内容尺寸没有变化时不再重设窗口尺寸，避免干扰拖动。
- 新增 5 项测试，覆盖 SwiftUI 中的真实命中区域、拖动/释放、拒绝路径、位置保存和重建恢复。
  最终串行全量为 102 项通过、0 项失败、1 项专用支付测试跳过；普通应用与独立商店目标
  Debug 构建通过。接收器测试使用独立输出管道并验证输出，避免共享空设备句柄写入失败导致误报。
- 用户已于 2026-10-28 手动确认「可以进行拖动」，据此记录实际拖动通过。界面工具发送过拖动，
  但未获得可信的位置变化证据，不将该自动化动作记作成功；临时验证实例已退出。
  跨显示器、不同缩放比例、macOS 14，以及真实重启后位置恢复仍需另行实机验收；位置恢复目前
  通过原生窗口自动化测试覆盖。

## 参考

- [Apple 账户付款方式](https://support.apple.com/zh-cn/111741)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [StoreKit currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
- [恢复购买与 AppStore.sync](https://developer.apple.com/documentation/storekit/appstore/sync())
- [Codex app-server 认证说明](https://learn.chatgpt.com/docs/app-server#auth-endpoints)
