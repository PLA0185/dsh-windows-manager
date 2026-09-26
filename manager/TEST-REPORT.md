# 分项验收记录

最新纠正：用户实测关闭可见 Windows Terminal 会停止 DSH，推翻了早期仅凭 MainWindowHandle=0 判定无窗口的结论。历史断言记录保留，不再作为无可见终端的充分证据。

2026-09-26 控制台隔离修复：计划任务及 VBS 改用 Windows GUI 子系统的 DSH-Launcher.exe，通过 UseShellExecute=false / CreateNoWindow=true 创建 PowerShell。宿主检查实际 ConsoleWindow=0、控制台进程列表仅宿主自身，拒绝带控制台窗口的 scheduler 宿主。

最新 9 项验证通过，见 reports/console-isolation.json：PE 为 GUI 子系统、实际控制台隔离、计划任务 Action、独立启动控制器成功、结束控制器后 DSH 和认证 RPC 持续可用、无窗口停止不影响其他 Node、重新启动、重启更换 PID、VBS 保持单实例。随后用户实际确认：“没有再出现，DSH 可正常使用”。无可见终端和真实可用性已有用户确认；未额外通过 GUI 关闭其他终端进行测试，真实 Windows 重启后的自启仍未验证。

查证和测试日期：2026-09-26。Task A 独立结果见 [TASK-A-RESULT.md](TASK-A-RESULT.md)，此文件记录 Task B。不以综合 PASS 掩盖未验证项。

## 已验证

三份结构化测试记录累计 32 条通过断言：`reports/integration.json` 18 条、`reports/native-smoke.json` 8 条、`reports/final-checks.json` 6 条。第一组使用早期 PowerShell 7 宿主；第二、三组针对最终系统 Windows PowerShell 5.1。它们不是 32 次独立环境或全部需求覆盖率。

| 范围 | 实际证据与结论 |
|---|---|
| start / stop / restart | 3080 和认证模型 RPC 可用；重复 start 保持单实例；stop 释放端口；restart 更换 PID 并通过稳定窗口 |
| 精准停止 | 另起独立 Node 哨兵，停止和重启 DSH 后哨兵仍存活 |
| 独立后台 | 启动控制器成功后强制结束控制器，DSH 继续运行；宿主独立于控制器进程树；Host/Node 的 MainWindowHandle 为 0 |
| 最终后台实现 | 正式任务执行系统 Windows PowerShell 5.1，不依赖 Codex runtime；最终原生重启成功 |
| 自启配置 | disable 移除登录触发器，仍可手动启动；enable 恢复唯一延迟 30 秒触发器；最后保持开启 |
| 模型 | 官方运行时目录读取；实际切换 deepseek-flash → deepseek-v4-pro → deepseek-flash；凭据摘要、profile 原文本保持；reasoningEffort=max 保留 |
| 模型刷新 | 官方渠道版本检查并重读目录；未覆盖用户显式 models；当前无新包版本 |
| 插件 | 18 个原插件完整保留；通过官方 CLI 安装本地空 Bundle 夹具、卸载、恢复重新安装，再恢复原集合；未卸载用户原插件进行破坏性验收 |
| 历史恢复 | 创建保护快照、列出、摘要校验、恢复 profile 和锁定依赖、重新启动；凭据、AGENTS 和原插件集合保留 |
| 更新查询 | 所有 18 个包的 registry 版本已查；DSH next 与已安装 0.1.7-rc.2 相同；不存在可用新版 |
| WhatIf | 插件卸载、历史恢复、DSH 更新预演不改变 profile 或产生快照；选定插件更新的 metadata/peer 检查在系统 PS5 下正常 |
| 日志 | 合成 token/API Key/password 脱敏通过；隔离测试日志按两份保留策略轮转通过，实际日志仍为 10 MiB / 5 份 |
| 清理 | 活动根目录旧 BAT 为 0，旧 DeepSeek Harness 任务不存在，仅 DSH Manager Web；最终 doctor 识别一份 DSH |

11 个活动脚本通过系统 Windows PowerShell 5.1 语法解析且均为 UTF-8 BOM，记录见 `reports/syntax-validation.json`；历史版本不纳入活动脚本检查，人工恢复旧版本时仍需按 ROLLBACK.md 校验编码和路径。最终只读诊断见 `reports/doctor-final.txt`。当前 profile 五个关键文件摘要与迁移前一致，记录于 `reports/audit-after.json`。

## 失败诊断与修正

- 初次自启验收发现 PowerShell 将空 triggers 转成含 null 数组，误判已开启；改为过滤 null。空 XML Triggers 的重复 disable 改用 XML 节点 RemoveAll；随后 enable/disable 验收通过。首次失败保留在 integration-attempt-1.json。
- 管理员清理脚本最初 UTF-8 无 BOM，系统 Windows PowerShell 5.1 误读中文并解析失败；没有执行清理。改为 UTF-8 BOM，经 PS5 parser 校验，用户管理员重跑成功，最终旧任务不存在。
- 原生宿主迁移时曾出现启动约 123 秒，旧 60 秒等待误报超时。增加启动阶段日志并将有界等待调整为 180 秒，后续原生重启通过；具体延迟根因仍未确定，未宣称已根治。
- 最终 WhatIf 触发 PS5 Get-FileHash 内部行为差异，无法读取 Hash；改用只读 .NET SHA256，不受 WhatIf 影响。registry 暂存文件改为显式文件 IO，预演仍可完成只读兼容检查并清理临时文件。重新验证通过。
- doctor 的 CLI 参数匹配遗漏带引号的 profile，误报实例数 0；修正引号兼容匹配，最终诊断为 1，与精确进程身份和监听 PID 一致。

## 未验证与限制

- 没有重启或注销用户的 Windows。真实登录后自动启动、disable 后重启不启动以及重启过程无窗口，仍待实际登录场景验证。触发器机制已验证。
- 强制关闭独立 PowerShell 控制器证明生命周期独立；未通过 GUI 点按关闭 Windows Terminal 做单独验收。
- 当前无更新版本，未实际执行 DSH/第三方插件新版升级，也未故意制造升级、卸载、恢复失败。失败保护分支和保护快照机制存在，不能宣称故障恢复效果已验证。
- 备用 WMI backend、其他模型 provider 未最终验收。
- Task A 短会话验证了规则注入与回答体现，没有制造真正 maxTokens 截断或完成长任务续接实测。
- 停止为关闭专属 Job Object 的有边界强制停止；没有已查证的官方 Windows Web CLI 正常退出接口。维护前先结束正在运行的对话。
- 未来 DSH 更新预检可能因当前 pnpm 10.20.0 与官方仓库 pin 11.7.0 不符而拒绝，需另行审阅包管理器升级，不自动变更。
