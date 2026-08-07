# CodexMeter 开发约定

## 项目目标

CodexMeter 是一个原生 macOS 菜单栏工具，用来持续展示当前 ChatGPT/Codex 账户的剩余额度。工具独立于 Codex 应用，不修改或注入 Codex 的界面、头像菜单、Dock 菜单或进程。

长期架构保持数据采集与展示解耦：

```text
Codex app-server / 未来官方接口
                ↓
          UsageProvider
                ↓
          UsageSnapshot
                ↓
     macOS 菜单栏 / Kindle 页面
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

## 本阶段不包含

- Kindle 局域网 HTTP 服务、配对令牌和电子墨水页面。
- macOS 通知、登录启动、WidgetKit 或自动更新。
- OpenAI API 组织用量、未来正式官方 provider 或公网中继。
- 消耗 rate-limit reset credits 等任何写操作。
- 向 Codex 本体注入菜单项或修改 Codex 配置。

## 实现约束

- 使用 Swift、SwiftUI 和 Foundation，不为首版引入第三方依赖。
- macOS 最低版本保持 14.0，遵循项目现有 Xcode 配置和命名风格。
- 子进程只执行解析到的 `codex` 可执行文件，并使用参数数组；不得通过 shell 拼接命令。
- 不记录或展示认证信息。标准错误只用于形成简短、可操作的本地错误信息。
- 刷新失败时保留上一次成功快照，同时显示最新错误。
- 修改保持聚焦，不在本阶段顺带实现 Kindle 或其他长期功能。

## 验证标准

- `xcodebuild` Debug 构建成功。
- `CodexMeterTests` 全部通过。
- 使用 fixture 验证多桶响应、旧单桶响应、credits、空额度和协议错误。
- 在本机允许访问 `~/.codex` 的环境中，完成一次真实 `account/rateLimits/read` 冒烟验证。
- 最终复查新增文件已加入 Xcode target，且没有把临时 schema、构建产物或认证数据写入项目。
