# DevMeter 开发约定

## 项目目标

DevMeter 是一个原生 macOS 菜单栏工具，当前持续展示 ChatGPT/Codex 账户的剩余额度，并按
DevSpace 路线逐步演进为多 AI Provider 用量、预测、趋势和 Agent 活动状态工具。它独立于
Provider 应用，不修改或注入其界面、菜单或进程。

长期架构保持数据采集与展示解耦：

```text
Codex app-server / 未来官方接口
                ↓
          UsageProvider
                ↓
          UsageSnapshot
                ↓
 macOS 菜单栏 / 浮窗 / Widget / Kindle 页面
```

## 已确认的数据源方案

- 首选本机 `codex app-server` 的 stdio JSONL 协议。
- 启动后先发送 `initialize`，再发送 `initialized`，随后调用只读方法 `account/rateLimits/read`。
- 支持 `rateLimitsByLimitId` 多额度桶；旧版本只有单桶时兼容 `rateLimits`。
- 展示主窗口和次窗口，不把多个额度合并成一个虚构的“总额度”。菜单栏显示所有窗口中最低的剩余百分比。
- `usedPercent`、`windowDurationMins`、`resetsAt`、`limitId`、`limitName` 和 credits 必须通过结构化解码读取。
- app-server 协议可能变化，因此协议 DTO 只能位于数据源适配层，不能泄漏到 SwiftUI 视图。
- 不抓取 Codex UI、DOM、Cookie 或登录令牌；协议不可用时明确显示错误，不静默降级到界面自动化。

## 初版改动范围

本阶段实现以下内容：

- 新增真实 `CodexLocalUsageProvider`，通过子进程调用本机 `codex app-server`。
- 新增 JSONL 请求/响应处理、超时、进程退出和协议错误映射。
- 将真实响应转换成既有 `UsageSnapshot` / `UsageLimit` 模型。
- 默认使用真实数据源，保留 `PreviewUsageProvider` 供 SwiftUI 预览或开发测试使用。
- 设置页显示真实数据源名称和实验性协议提示。
- 总开关关闭后停止刷新；应用退出或 provider 释放时终止由本应用启动的子进程。
- 为协议解码、多额度桶、单桶兼容和异常响应补充单元测试。

## 0.2 版本改动范围

- 新增 WidgetKit extension，通过 App Group 读取主应用最近一次成功快照；Widget 不直接启动 `codex app-server`。
- 新增 Kindle 局域网只读 HTTP 页面，使用随机配对令牌，不暴露写操作或认证信息。
- 使用 `SMAppService.mainApp` 实现用户可控的登录时启动。
- 使用 Sparkle 2 实现自动检查、下载和安装更新；只有配置 HTTPS appcast 与 EdDSA 公钥的正式构建才启用 updater。
- 私有代码仓库不得要求客户端保存 GitHub PAT；更新文件必须发布到可匿名访问的独立 HTTPS 地址。

## DevMeter 品牌迁移

- 本仓库由 CodexMeter 原地改名，必须保留 Git 历史，不建立第二份代码副本。
- Bundle Identifier 使用 `com.zhaobinrui.devspace.meter`，URL Scheme 保留给
  `devspace.local.v1`，没有实际路由前不得宣称跨应用功能可用。
- 首次启动迁移旧 Bundle Domain 的已知偏好；已有 DevMeter 偏好优先，不迁移未知键。
- 新 App Group 为 `group.com.zhaobinrui.devspace.meter`。迁移期可只读旧组并写入新组，
  不得继续把新快照写入旧组。

## Phase 1：Codex 历史、预测与提醒

- 历史、预测与提醒使用 Swift 6 严格并发检查，系统最低版本保持 macOS 14。
- 历史只记录额度窗口元数据和本机加盐个人账户分组，不持久化邮箱、Credits、凭据或原始错误。
- 组织账户或无法可靠识别归属时不记录历史、不预测，不以推测的账户身份分组。
- 五分钟内合并采样，默认保留 30 天，支持 7/90 天、暂停记录和清除；文件版本化、原子保存并限制大小。
- 不跨账户、重置、用量回退和超过 15 分钟的采样间隔预测；至少三次样本、跨度十分钟。
- 通知默认关闭，只在用户主动开启时申请权限；按账户/额度窗口去重，不展示原始错误。
- 历史和复杂分析位于独立窗口，菜单栏只显示摘要；读写历史失败不得破坏当前额度读取。

## 当前不包含

- 其他 AI Provider 与 Agent Activity Monitor。
- OpenAI API 组织用量、未来正式官方 provider 或公网中继。
- 消耗 rate-limit reset credits 等任何写操作。
- 向 Codex 本体注入菜单项或修改 Codex 配置。

## 实现约束

- 额度读取、Widget 和 Kindle 服务使用 Swift、SwiftUI 与系统框架；第三方依赖仅允许用于成熟的自动更新能力，当前固定为 Sparkle 2。
- macOS 最低版本保持 14.0，遵循项目现有 Xcode 配置和命名风格。
- 子进程只执行解析到的 `codex` 可执行文件，并使用参数数组；不得通过 shell 拼接命令。
- 不记录或展示认证信息。标准错误只用于形成简短、可操作的本地错误信息。
- 刷新失败时保留上一次成功快照，同时显示最新错误。
- Widget 与主应用通过 `group.com.zhaobinrui.devspace.meter` App Group 共享结构化快照，不共享认证信息；迁移期只读兼容旧 `group.com.zhaobinrui.CodexMeter`，不得向旧组写入新数据。
- Kindle 服务仅接受带配对令牌的 `GET /` 请求，并对动态 HTML 文本进行转义。
- 自动更新源必须使用 HTTPS，发布包必须经过 Developer ID 签名、公证与 Sparkle EdDSA 签名。

## 验证标准

- `xcodebuild` Debug 构建成功。
- `DevMeterTests` 全部通过。
- 使用 fixture 验证多桶响应、旧单桶响应、credits、空额度和协议错误。
- 验证 App Group 快照编解码、Widget target 构建、Kindle HTML 转义和局域网服务启停。
- 验证登录项注册状态能够在设置中正确反馈。
- 使用配置了测试 appcast 的签名安装包完成一次 Sparkle 升级验证；未配置更新源时 updater 必须保持禁用。
- 在本机允许访问 `~/.codex` 的环境中，完成一次真实 `account/rateLimits/read` 冒烟验证。
- 最终复查新增文件已加入 Xcode target，且没有把临时 schema、构建产物或认证数据写入项目。
