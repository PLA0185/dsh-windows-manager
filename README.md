# DSH Windows Manager

Windows 上的 DeepSeek Harness 管理器。本仓库保存 2026-09-26 的实际部署源码、无窗口启动器和分项验收记录，不包含 API Key、聊天、运行日志、DPAPI 启动令牌或机器备份。

## 双击入口

| 文件 | 用途 | 窗口行为 |
|---|---|---|
| DSH_Start.vbs | 启动后台 DSH | 推荐，无可见终端 |
| DSH_Stop.vbs | 停止 DSH | 推荐，无可见终端 |
| DSH_Restart.vbs | 重启 DSH | 推荐，无可见终端 |
| DSH_Start.bat / DSH_Stop.bat / DSH_Restart.bat | 同名 VBS 的兼容入口 | 能用，但双击时可能闪一下 CMD |
| DSH_Manager.bat | 中文管理菜单 | 菜单窗口正常显示，退出不停止 DSH |

BAT 仍能使用，不承担后台宿主或登录自启功能。保留它们是为了兼容已经提供的双击入口；对完全无窗口的使用场景，选择 VBS。

后台链路：Windows Task Scheduler → GUI 类型 DSH-Launcher.exe → CreateNoWindow PowerShell Host → 官方 DSH CLI → 专属 Job Object。关闭启动控制器不会结束服务；stop 只结束本实例，不按名称终止所有 Node。

## 部署环境与恢复

本机 DSH_HOME 为 D:\DeepSeekHarnessData，CLI 位于 D:\npm-global，web profile 为现有部署。config.json 是不含凭据的本机路径配置；在其他机器使用前必须修改路径并准备官方 DSH 安装和 profile。本仓库不是带用户数据的一键迁移包，也不包含第三方插件依赖目录。

默认模型 deepseek-official/deepseek-flash；原 18 个插件保留；reasoningEffort=max 未改。自启为当前用户登录后延迟 30 秒，并非登录前系统服务。

恢复管理器时将根入口与 manager 目录放回 DSH_HOME，保留原有 profile、凭据和数据。需要的空目录为 manager/state、logs、history、reports。计划任务名 DSH Manager Web，Action 必须指向 manager/DSH-Launcher.exe，参数 host；使用当前用户 Interactive、登录延迟 30 秒、IgnoreNew、无运行时长限制。恢复后执行 manager/DSH-Manager.ps1 doctor。

启动器同时交付源码和编译结果，编译命令示例：

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ /out:manager\DSH-Launcher.exe manager\DSH-Launcher.cs
```

## 功能和证据

启动/停止/重启、登录自启配置、官方模型目录/切换、官方插件卸载/更新查询、版本查询、保护快照/恢复、doctor、日志脱敏与轮转。详细操作见 [使用说明](manager/README.md)，验收及限制见 [测试报告](manager/TEST-REPORT.md)，官方资料见 [来源](manager/OFFICIAL-SOURCES.md)。

用户曾实测关闭可见 Windows Terminal 会停止 DSH，推翻了早期仅凭 MainWindowHandle=0 判定无窗口的结论。修复后 9 项控制台隔离测试通过，用户实际确认“没有再出现，DSH 可正常使用”；证据在 validation。历史记录保留失败与修正，不将旧断言改写为正确。

真实 Windows 重启自启、当前不存在的新版升级、升级失败恢复仍未验证；曾发生宿主启动延迟，具体原因未确定。维护停止为关闭专属 Job Object 的有边界强制停止。

Task A 只增量追加长期任务规则，单独保存于 task-a/Long-Running-Task-Rules.md，并单独验收；不能据短会话测试宣称真实 maxTokens 截断后的续接已验证。
