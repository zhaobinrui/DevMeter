# Claude Code：第二个 Provider 本地验证

接入依据是 [Claude Code 官方 status line 文档](https://code.claude.com/docs/en/statusline)。
DevMeter 接收用户主动配置的本地状态行事件，不读取 Claude 登录令牌、Keychain、会话文件或界面，
不向 Anthropic 发起额外请求，也不修改 Claude 设置。

## 使用方式

1. 将 DevMeter 安装到固定位置，在「设置 → Provider 授权」阅读范围并主动允许 Claude Code，
   再打开「Claude Code 本地接入」。未授权时接收器返回 2，不读取 stdin 或写入快照。
2. 查看并复制状态行配置，手动合并到 Claude Code 用户设置的 `statusLine` 字段。
   配置中的命令指向当前 DevMeter 可执行文件；移动应用后需要重新复制。
3. 若已有 `statusLine`，先保存原配置并自行整合，避免覆盖原有输出。DevMeter 不执行或包装未知脚本。
4. 在 Claude Code 中正常使用，收到包含额度字段的状态行事件后，在 DevMeter 选择 Claude Code。
   DevMeter 不会为了刷新额度主动发送模型请求。
5. 停用时可撤销 Claude 授权，并移除 Claude 中的接收配置；设置中的「清除 Claude 本地快照」
   删除已保存快照。只清除快照而保留授权与状态行配置时，下次事件会重新生成。

接收器退出码、文件错误及检查步骤见[Provider 排障说明](provider-troubleshooting.md)。

官方文档说明，订阅窗口通常在 claude.ai Pro/Max 的会话首次响应后出现，两个窗口可能分别缺失。
其他登录方式或旧版 CLI 不一定提供这些字段。DevMeter 显示缺失状态，不使用上下文占用或
会话费用推算订阅额度。多个 Claude 会话只采用最近写入的事件，不把它们相加。

## 数据与能力边界

输入允许包含完整 status line JSON，但只读取以下白名单字段：

- `rate_limits.five_hour.used_percentage`、`resets_at`。
- `rate_limits.seven_day.used_percentage`、`resets_at`。

原始输入最多 1 MiB，只在接收进程内存中处理。磁盘只保留一份版本化快照，包含两个订阅窗口、
本地接收时间与固定名称，最大 16 KiB；以 0600 权限创建临时文件后原子替换。
文件位于本机 Application Support 的
`com.zhaobinrui.devspace.meter/providers/claude-statusline-v1.json`。
不保存会话 ID、模型、项目路径、会话文件路径、费用、Token、提示词或凭据。

Claude 标记的「收到」时间是状态行事件的本机接收时间，不代表 DevMeter 独立查询了服务端。
轮询只重读文件，不会刷新这个时间；长期没有新事件或窗口已过重置时间时显示旧数据，
不能自行恢复为 100%。缺少重置字段时显示未知；非法事件不会覆盖上一次有效快照。
合法但没有订阅窗口的事件会更新为「本次无额度」，读取方保留已显示的旧值并明确报错。

状态行没有稳定的账户标识，因此 Claude 暂不记录历史、不预测，也不发送账户额度提醒。
Codex 既有账户隔离、历史与预测继续沿用。多来源切换归入 Pro，本地预览版允许体验；
商店付费与正式 Sandbox 验收仍以发行清单为准。

## 扩展方式

`UsageProvider` 负责采集并返回领域快照，`UsageSource` 声明来源及当前历史能力，
应用在初始化时登记适配器。所选来源才启动轮询；切换会取消旧请求、等待旧来源关闭，
拒绝迟到结果，并分别保留各来源最近的可信快照和错误。菜单栏与浮窗只显示所选来源，
Widget 切换时先清空旧来源数据，Kindle 页面也显示来源和接收时间。

增加更多来源前逐项验证：

- 有官方或明确支持的机器可读接口，并能以最小权限使用；不复用私人 OAuth endpoint 或抓取登录凭据。
- 明确数据单位、统计窗口、时间来源和账户归属；余额、费用、Token 与订阅百分比需要不同模型与展示。
- 覆盖正常、缺失、权限不足、协议变化、超时/取消和账户变化；没有账户依据就关闭账户历史与预测。
- 使用真实账户完成只读冒烟，再决定是否纳入正式支持列表。fixture 通过不等于真实 Provider 验收。
- 同时验证菜单栏、浮窗、Widget/Kindle 的来源语义，以及独立发行目标；不合并跨 Provider 总额度。

后续可评估 Gemini CLI 的官方可用输出，以及 DeepSeek 官方余额 API 等不同口径来源；
这些目前都没有登记为已支持 Provider。余额 API 不能直接套用订阅窗口或重置预测模型。

## 本地验证

```sh
xcodebuild -project DevMeter.xcodeproj -scheme DevMeter -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/DevMeterPhase1DerivedData \
  CODE_SIGNING_ALLOWED=NO build test

xcodebuild -project DevMeter.xcodeproj -scheme DevMeterAppStore -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/DevMeterPhase1DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

真实可执行文件还提供仅校验模式：将测试 JSON 通过 stdin 传入
`DevMeter --claude-statusline --validate-only`，stdout 只返回过滤后的结构，不写用户快照、
不启动界面、轮询或内购服务。直接运行 `--claude-statusline` 才会写入本机最新快照并输出简短状态行。

本轮已覆盖输入白名单、双窗口与缺失重置、错误字段、文件权限/大小/符号链接、清除、
接收时间保持、真实文件到 Provider/Store 的集成、迟到响应隔离、来源缓存/错误隔离、
重启恢复、Pro 撤权、通知迟到回调隔离以及 Widget 旧快照兼容。

2026-10-27 在 macOS 27.0.1 / Apple Silicon 的结果：18 项新增验证纳入全量测试，
共 80 项通过、0 项失败、1 项跳过。跳过的是需要专用 scheme 的原生支付测试，不属于 Claude 验证。
Debug 主应用与独立商店目标均构建通过；原生可执行文件的 `--validate-only` 模式已验证正确输入、
错误输入拒绝和敏感字段过滤，未写入用户快照或 Claude 设置。

最终通用 Release 工程候选包位于
`/private/tmp/DevMeterClaudeCandidate-20261027-final/DevMeter.app`，同目录的
`candidate-report.json` 与 `claude-verification.json` 记录打包检查和接收器复核结果。
最终候选包已通过正确输入、错误输入拒绝与敏感字段过滤复核；它尚未通过商店分发签名，
不能作为正式发行或真实 Claude 账户链路成功的证明。

本机未发现 Claude CLI；真实 Claude 事件尚未验收。界面工具绑定 DevMeter 超时，
本轮未完成新增切换控件的真实 macOS 交互检查。签名 Sandbox 下的状态行写入与读取也未验证，
不能把无签名工程构建或本地合成数据标为商店已支持。
