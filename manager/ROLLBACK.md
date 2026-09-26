# 回滚与恢复

最新控制台隔离修复后，任务 Action 为 manager\DSH-Launcher.exe，参数 host。人工回滚必须成套恢复 DSH-Launcher.cs、DSH-Launcher.exe、Host、Common、Manager，并核对任务 Action 和根目录 VBS。不要恢复直接执行 powershell.exe 的旧任务动作，否则可能重现可见 Terminal 和关闭窗口导致停机。修复前备份为 backup\20260926-142811-console-isolation-fix。

## Task A 独立回滚

仅在明确需要撤销大任务规则时，将 `D:\DeepSeekHarnessData\backup\20260926-122001-task-a\AGENTS.md` 复制回根目录。备份 SHA256：`03F90B2B6E25C5FA4B71320DF609948B7C7EFF7CC3E9B691459E64935202C45F`。Task B 的 snapshot restore 不覆盖此文件。

## profile / 插件 / DSH 回滚

运行 `DSH-Manager.ps1 snapshot list`，审阅精确 ID，再执行 `snapshot restore '<ID>' -WhatIf`。正式恢复使用相同命令去掉 WhatIf；自动保护当前状态，恢复匹配 CLI 版本和 profile 锁定依赖，并重新验证启动。原始会话和凭据不参与复制或删除。

最初旧环境快照：`history\20260926-122327-old-environment`。独立备份：`D:\DeepSeekHarnessData\backup\20260926-122327-task-b-before`。后续操作都有独立 before-* 快照。

## 管理器本身回滚

先禁用自启并 stop。选择 `history\<ID>\manager` 中完整的配置和脚本版本，保护当前 manager 文件后复制回对应文件；保持 UTF-8 BOM。检查 config 中的执行路径并按其 backend 恢复任务 Action，之后 start、doctor 验证。不要只恢复一个脚本而混用不同版本的 Common/helper/Host。

旧环境历史快照没有 manager 子目录；它用于恢复原有 profile 或有意回退旧 BAT，不用于恢复管理器代码。

## 有意恢复旧 BAT 体系

这是人工应急方案，不属于正式管理功能：

1. 新管理器 `autostart disable`、`stop`，验证 3080 无监听。
2. 从旧环境快照 `old-scripts` 恢复原有 BAT（不要与新任务一起自动启动）。
3. 如需恢复原计划任务，在管理员 PowerShell 使用 `Register-ScheduledTask -TaskName 'DeepSeek Harness' -Xml (Get-Content -LiteralPath '<备份 task XML 路径>' -Raw)`；XML 位于旧环境快照与独立备份内。
4. 恢复时不得用按名称终止全部 Node 的命令。旧停止脚本存在未校验监听者即终止的风险，优先保留新管理器精准停止逻辑。

`DSH_VERIFY.ps1` 的旧文本位于原备份 `old-scripts`；当前入口调用新 doctor。旧 PID 文件也已归档。旧数据目录、聊天、凭据与项目均未清空。
