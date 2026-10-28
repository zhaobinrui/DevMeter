# Provider 授权、错误状态与排查

适用于当前 Codex app-server 与 Claude Code 本地状态行适配。其他 Provider 尚未接入，不能套用
本表推断其状态码。先区分应用授权、子进程退出、JSON-RPC 错误和本地文件错误，再处理。

## 先检查授权

首次安装，以及升级前没有授权记录时，DevMeter 不自动采集。打开菜单栏、浮窗或
「设置 → Provider 授权」，阅读对应来源的数据范围后主动点击「允许读取」。
Codex 与 Claude 分别授权；启用 DevMeter、购买 Pro、CLI 已登录或复制过 statusLine 配置都不代替授权。
授权属于 DevMeter 的本地数据访问同意，不等于 Provider 账户登录、Apple 授权或 macOS 通知权限。

- 未授权：菜单栏显示「待授权」，不启动 Codex app-server，不读取 Claude 快照；手动刷新也不绕过。
- Claude 接收：先授权，再按[接入说明](claude-code-provider.md)手动配置 statusLine。
  接收进程在读取 stdin 前检查授权；拒绝时返回 **2**，不保存事件。
- 撤销：设置中点击对应来源的撤销按钮，停止采集、取消当前请求、拒绝迟到结果，清除当前展示
  和该来源的内存缓存；当前来源的 Widget 快照也会清空。已有历史与 Claude 文件保留，可另行清除。
  Claude 中保留的命令随后会被拒绝，建议同时移除配置以避免终端持续提示。
- 授权按来源和读取范围版本保存；范围扩大后需要重新同意。撤销不会退出 Codex/Claude 账户。

## 状态 127：本机已确认的原因

2026-10-27 对正在运行的 Xcode Debug DevMeter 做了只读核对：

| 检查 | 结果 |
| --- | --- |
| DevMeter 进程的 PATH | `/usr/bin:/bin:/usr/sbin:/sbin` |
| 自动找到的 Codex | `~/.nvm/versions/node/v24.13.0/bin/codex`，链接至 npm 包中的 `codex.js` |
| 脚本解释器 | `#!/usr/bin/env node` |
| 用 DevMeter 的 PATH 执行同一脚本 `--version` | **127**，`env: node: No such file or directory` |
| 仅在该子进程 PATH 前补入相同 nvm 的 bin | **0**，`codex-cli 0.142.0` |

本次问题是 **Node 已安装，但桌面进程找不到它**，发生在读取账户或额度之前；不是额度耗尽。
旧实现只判断 codex 文件能否执行，解析链接后直接启动，没有保留 nvm 的 Node 路径。
当前修复保留 CLI 的 bin 入口，只在同目录存在可执行 Node 时为该子进程补入路径；不加载 shell
启动文件、不修改用户全局 PATH、不自动安装 Node，也不自动换用其他账户/数据源。

DevMeter 自身是原生 Swift 应用，不依赖 Node。**npm 版 Codex 的 JS 入口依赖 Node**；如果机器
根本没有 Node，上述路径修复不会凭空提供运行时。可以由用户选择安装匹配的 Node，或按
[Codex 官方安装文档](https://learn.chatgpt.com/docs/cli)使用独立安装版。Claude 的 DevMeter
接收器是原生可执行文件，不要求 Node；Claude Code 自身的安装要求以其官方文档为准。

### 检查与处理步骤

1. 先确认已授权 Codex，并开启 DevMeter。若仍运行旧构建，退出旧应用后重新在 Xcode 构建运行。
   仅修改源码不会改变已经运行的应用，也不要同时运行安装版和 Debug 版。
2. 在终端只检查可执行文件和版本：

   ```sh
   command -v codex
   command -v node
   codex --version
   codex app-server --help
   ```

3. 若 codex 是 npm/nvm 入口，可用下面的只读版本检查复现桌面环境。命令不发起模型任务：

   ```sh
   CODEX_BIN="$(command -v codex)"
   env PATH='/usr/bin:/bin:/usr/sbin:/sbin' "$CODEX_BIN" --version
   env PATH="$(dirname "$CODEX_BIN"):/usr/bin:/bin:/usr/sbin:/sbin" "$CODEX_BIN" --version
   ```

   第一条报 127、第二条成功，说明同目录 Node 路径是关键。终端与 DevMeter 可能找到不同版本，
   不能只凭终端中 `codex --version` 成功断言桌面应用可用。当前查找顺序是 PATH、
   `~/.codex/bin`、`~/.local/bin`、Homebrew 常见目录、已知应用内路径、nvm 各版本（新版本优先）。
4. 若没有 Node 且使用 npm 版，选择官方独立安装版或修复 npm/Node 安装，再重新启动 DevMeter。
   若 Node 在其他目录，当前补入同目录的修复不会搜索任意 Node；建议使用配套安装或独立版。
   不要用 `chmod -R 777`、关闭系统保护或向应用中复制未知解释器来解决。
5. 版本与启动正常后，再运行 `codex login status` 检查登录模式；它不是服务端凭据有效性或额度
   可用的保证。若需要登录，使用官方 CLI 的交互登录流程，不在 DevMeter 中填写登录令牌。
   最后在 DevMeter 手动刷新，确认来源、数据时间和错误提示。

## Codex：应用错误与进程状态

应用错误没有另编数字编号，下面使用代码中的枚举名定位。`processExited(N)` 中的 N 来自
Foundation `Process.terminationStatus`，不是 HTTP 状态或 Provider 的额度错误码。
刷新失败时保留上次可信快照，主菜单/浮窗标记旧值；撤销授权则清除当前展示。

| 内部状态 / 页面提示 | 含义或常见原因 | 检查与处理 |
| --- | --- | --- |
| `executableNotFound` / 未找到 codex 命令 | 所有候选位置均无可执行 CLI | 按上节检查实际安装路径；安装官方 CLI 后重启。仅安装桌面客户端不保证当前适配器能找到 CLI。 |
| `launchFailed` / 无法启动 Codex app-server | `Process.run()` 失败；权限、失效入口、架构或 Sandbox 限制等 | 检查入口是否存在、为普通可执行文件且可运行；核对 Intel/Apple Silicon 安装包。区分无沙盒 Debug 与正式签名 Sandbox，勿把它们互相当作验收。 |
| `processExited(127)` | 本次已证实为 `/usr/bin/env` 找不到 Node；其他启动器也可能用 127 表达命令缺失 | 执行上节最小 PATH 对照；检查 npm 入口与配套 Node。127 单独不能证明所有机器都是同一原因。 |
| `processExited(126)` | 某些 shell/启动器以此表示命令找到但无法执行 | 检查解释器、执行权限和架构；这不是 Codex 官方定义的账户码。 |
| `processExited(0)` | 子进程正常退出，但在完整协议响应之前就结束 | 检查 CLI 是否支持 app-server、是否为错误的同名程序或包装脚本；更新到兼容版本后重试。 |
| `processExited(其他 N)` | CLI/解释器提前结束，数字本身不足以定位原因 | 记录 N、CLI 版本、安装方式与只读启动检查结果。当前文案未区分 `terminationReason`，不要把 9/15 或 137/143 一律解释为特定崩溃或 OOM。 |
| `timedOut` / 读取 Codex 用量超时 | 默认 8 秒内握手或只读响应未完成 | 先排除启动问题，再检查 Codex 自身连接、代理和登录；恢复后手动刷新。自动失败重试会退避，最长 15 分钟，不要反复启动实例。 |
| `unavailable` / 当前用量数据源不可用 | 会话被停止、写入失败或并发读取被拒绝 | 观察是否正在切换来源或停用应用；保留单个实例再刷新。取消本身不应被当作新的刷新失败。 |
| `protocolFailure(message)` / app-server 返回错误 | 服务返回 JSON-RPC error；当前显示可选数字 code 和截断消息 | 先区分下表协议码；未登录相关消息用官方登录流程处理。不要公开原始响应或账户信息。 |
| `protocolFailure` / 读取期间账户发生变化，请重新刷新 | 同次读取前后身份变化，或收到 account/updated | 等待切换账号完成后刷新；不把两账户数据混写到历史。 |
| `invalidResponse` / 无法识别的数据 | 无效 JSON、字段类型/响应 ID 不符、重复额度 ID，或没有完整响应 | 核对 CLI 版本与 app-server 帮助，更新兼容版本；反馈版本与通用状态，勿提交完整 stdout。 |
| `noUsageLimits` / 当前账户没有可展示的 Codex 额度 | 协议成功但没有可展示窗口 | 检查登录模式、套餐与账户是否提供订阅窗口；不等同于剩余 0%，不将 OpenAI API 用量或 Credits 换算成订阅额度。 |

### JSON-RPC code 与上游错误

服务返回 `error.code` 时会显示在消息前，例如 `-32000：…`；缺失 code 时仅显示消息。
这是对收到的数值原样分类，不保证各 Codex 版本返回相同代码。
[JSON-RPC 标准](https://www.jsonrpc.org/specification#error_object)定义如下：

| code | 含义 | 处理 |
| --- | --- | --- |
| `-32700` | 请求 JSON 解析失败 | 检查版本兼容或包装器是否污染协议；属于适配诊断，不通过修改用户账户解决。 |
| `-32600` | 请求格式无效 | 核对握手与协议版本；反馈 CLI/DevMeter 版本。 |
| `-32601` | 方法不存在或不可用 | 当前 CLI 可能不支持所需方法，更新兼容版本。 |
| `-32602` | 参数无效 | 协议版本或参数不兼容，需要适配器检查。 |
| `-32603` | 服务内部错误 | 检查消息、重启本应用的读取会话后重试；持续发生则反馈。 |
| `-32000` 至 `-32099` | 实现自定义服务错误 | 必须结合消息解释；不能把 `-32000` 永久等同于「未登录」。 |

官方文档中的 `-32001 / Server overloaded` 针对 **WebSocket 入口队列**；DevMeter 当前使用
stdio，不能把它当作所有读取失败的固定码。也不能把任务执行阶段的 `codexErrorInfo` 当作本应用
只读额度调用的返回模型。接口与传输说明见[官方 app-server 文档](https://learn.chatgpt.com/docs/app-server)。

DevMeter 不直接调用 Provider HTTP 端点，当前没有独立的 HTTP 状态字段。只有消息明确包含时，
才按上游 401（检查登录）、403（检查访问范围/组织策略）、429（等待服务允许重试）、5xx（稍后重试）
进一步排查；不要从本地 127 推导认证失败，不保证这些上游码一定原样透传。

## Claude Code：接收命令退出码

这里的数字是 **DevMeter 自己的 `--claude-statusline` 接收器退出码**，不是 Anthropic API 状态码。
当前适配器不向 Anthropic 发起 HTTP 请求，因此不能提供它并未收到的 401/429 等服务端代码。

| 退出码 | 含义 | 检查与处理 |
| --- | --- | --- |
| **0** | 事件过滤并写入成功；`--validate-only` 时表示仅校验成功 | 不保证事件一定有订阅窗口。合法空事件输出「暂无订阅额度」，读取方显示 `noQuota`。 |
| **1** | 参数错误、输入非法/超 1 MiB，或文件写入失败等 | 检查命令参数、路径引号、输入结构和目录权限；只用合成数据测试，勿保存原始事件。标准错误故意不回显原输入与详细路径。 |
| **2** | 未授权或授权在接收期间被撤销 | 在 DevMeter 设置中阅读范围并主动允许；若要停用，移除 Claude 中的命令，无需修改权限或重装 Node。 |
| shell 的 **126/127** | Claude 在启动接收器之前就无法执行/找到配置中的命令 | 应用可能已移动、删除或路径引号错误。固定安装位置后，从 DevMeter 设置重新复制配置。不能当作接收器的 1/2。 |

`--validate-only` 专用于用户提供的测试输入：不读取 Provider、不保存快照、不授予权限，
因此可以在未授权时运行。它的成功不是真实账户接入验收。

## Claude Code：读取快照的状态

以下是 `ClaudeStatusLineError` 的枚举名，**没有额外数字错误码**。

| 状态 / 提示 | 含义 | 检查与处理 |
| --- | --- | --- |
| `notConnected` / 尚未收到状态行数据 | 快照文件不存在（`ENOENT`） | 确认已授权、配置指向当前固定应用位置、Claude 已运行并产生事件。可检查 `claude --version`，不为刷新额度主动生成模型请求。 |
| `noQuota` / 本次事件没有订阅额度窗口 | 合法事件缺少 five_hour/seven_day | 检查订阅与登录方式、CLI 版本，等待正常使用中的首次响应。官方还支持网关 spend_limit，但本适配器只接受两个订阅窗口，不把费用或上下文占用冒充额度。 |
| `invalidData` / 额度字段无法识别 | JSON、类型、百分比范围或重置时间非法；输入过大 | 用下面的合成事件校验接收器；检查兼容版本。非法事件不覆盖上次有效文件。 |
| `invalidFile` / 快照损坏、过大或版本不兼容 | 非普通文件、非当前用户所有、超 16 KiB、版本/窗口字段不符、接收时间异常等 | 先只检查文件属性与大小，勿手改结构；使用设置中的清除入口，再等授权后的新事件。文件异常不会自动覆盖或递归删除。 |
| `ioFailure` / 无法读写本地快照 | 打开/创建/写入/替换/删除失败；符号链接因 O_NOFOLLOW 被拒绝也可进入此状态 | 检查当前用户拥有的目录与文件权限、是否为链接、是否使用不同发行目标的容器；不要全盘提权。修复后重试或清除本应用快照。 |

只读检查示例（无沙盒本地预览；Sandbox 的 Application Support 位于应用容器中，路径不同）：

```sh
CLAUDE_CAPTURE="$HOME/Library/Application Support/com.zhaobinrui.devspace.meter/providers/claude-statusline-v1.json"
ls -ld "$(dirname "$CLAUDE_CAPTURE")"
ls -l "$CLAUDE_CAPTURE"
stat -f 'owner=%Su mode=%Sp bytes=%z modified=%Sm' "$CLAUDE_CAPTURE"
```

接收器新建目录为 0700、临时文件为 0600，再原子替换。只检查自己所属的数据；不要把
auth、Keychain、Claude 设置全集或完整 status line JSON 贴到 Issue。清除文件不会修复错误命令，
保留命令且仍授权时，下个事件会重新生成。轮询文件不会刷新接收时间，旧窗口也不会自动恢复 100%。

在终端用固定的实际安装路径运行合成测试（移动过应用时先更正路径）：

```sh
printf '%s\n' '{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1900000000}}}' \
  '/Applications/DevMeter.app/Contents/MacOS/DevMeter' --claude-statusline --validate-only
```

Claude 字段与缺失条件参见[官方 status line 文档](https://code.claude.com/docs/en/statusline#rate-limit-usage)。
真实 Claude 账户、正式签名 Sandbox 以及 macOS 14 运行验收仍需分别完成。

## 反馈需要哪些信息

在「设置 → 帮助与隐私」复制支持信息，自行检查后提交到项目反馈入口。可补充 DevMeter/CLI
版本、安装方式、发生在哪个来源、授权是否开启、准确的数字或上述枚举名、最小复现步骤。
支持信息只含版本、系统、来源和通用状态，`awaitingAuthorization` 表示待授权，不表示网络故障。
不要附带账户邮箱、Token、Cookie、凭据文件、原始事件、完整进程环境或 Kindle 配对地址。

## 本次验证范围

本机已通过同一 npm 入口的最小 PATH/配套 Node 对照定位 127，未读取凭据或发起模型任务。
代码回归覆盖 npm 链接与同目录解释器、原生 CLI 环境保持、退出码与 JSON-RPC code、首次未授权
零采集、按来源恢复、撤销及迟到响应、Claude 接收前拒绝和仅校验模式。
自动化通过不代替真实账户及签名发行验收；实际测试结果另见发行验收清单。
