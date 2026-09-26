# 迁移交付

最新修正（2026-09-26）：用户关闭可见 Windows Terminal 导致 DSH 停止，此前无窗口验收不充分。计划任务与根目录 VBS 已改用 GUI 类型 DSH-Launcher.exe，以 CreateNoWindow 创建 PowerShell；宿主实际控制台隔离、启动控制器结束后存活及停止/重启等 9 项新测试通过。证据见 reports/console-isolation.json。历史 MainWindowHandle=0 断言不再视为无可见终端的充分证据。

Task A：增量规则已完成、备份和新会话注入验证已完成。完整文件范围、前后 SHA256 和效果限制见 [TASK-A-RESULT.md](TASK-A-RESULT.md)。

Task B：管理器已部署，DSH 正常运行，核心维护功能实测通过；真实 Windows 重启自启、新版本升级与故障恢复仍未验收，详见 [TEST-REPORT.md](TEST-REPORT.md)。

## 当前体系

- 正式入口：`D:\DeepSeekHarnessData\manager\DSH-Manager.ps1`，无参数为中文菜单，保留命令行参数模式。
- 后台：Windows Task Scheduler → GUI 类型 DSH-Launcher.exe → CreateNoWindow 的系统 Windows PowerShell 5.1 Host → 官方 Node CLI → 专属 Job Object。
- 自启：唯一任务 `DSH Manager Web`，当前用户登录后延迟 30 秒，已启用；不属于登录前系统服务。
- DSH：0.1.7-rc.2；Node v24.21.0；pnpm 10.20.0；Git 2.55.0.windows.5。
- 默认模型：deepseek-official / deepseek-flash；reasoningEffort=max 保留；原有 18 个插件保留。完整列表见 audit-after.md。
- 旧管理员任务已由用户运行修复后的 Complete-Migration.ps1 删除，复查不存在。
- 初始 Task B 备份：`D:\DeepSeekHarnessData\backup\20260926-122327-task-b-before`；旧环境快照：`manager\history\20260926-122327-old-environment`。后续保护快照均镜像到 backup。
- 最终管理器/profile 快照：`20260926-130705-302-installation-final`，在 history 和 backup 各有一份；最终审计见 audit-after.md。

已从活动目录移除并归档的 BAT：Clean_Old_DSH_Autostart.bat、Disable_DSH_Autostart_FIXED_v2.bat、DSH_Background_Start_FIXED.bat、DSH_Restart_FIXED.bat、DSH_Stop_FIXED.bat、Enable_DSH_Autostart_FIXED_v2.bat。DSH_VERIFY.ps1 改为 doctor 代理，旧 PID 已归档。未清空原始聊天、凭据或项目，未修改官方包源码。

## 操作

```powershell
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1'
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' start
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' stop
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' restart
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' plugins list
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' plugins remove '<精确包名>'
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' snapshot list
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' snapshot restore '<完整 ID>'
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' doctor
```

详细模型、更新和日志操作见 [README.md](README.md)。完全移除时先 autostart disable、stop，再删除唯一计划任务；保留需要的 history/backup 后人工移走 manager，不删除 DSH_HOME/profile。人工回滚和原体系应急恢复见 [ROLLBACK.md](ROLLBACK.md)。

## 官方依据与已知问题

实际阅读资料、链接、commit、release/date 全部列于 [OFFICIAL-SOURCES.md](OFFICIAL-SOURCES.md)：固定 commit 477b4f420553e8a52c2fbccc464d7561b239c443，tag dsh-v0.1.7-rc.2，GitHub 发布 2026-09-24 14:10:21 UTC，查证日期 2026-09-26。包括主 README、CLI reference、Web App、Plugin Manager、Tool Catalog、Providers Guide，以及 Windows 计划任务和 Job Objects 官方资料。

系统宿主曾在 Node 创建前延迟约两分钟，后续启动正常；原因未确定。等待上限 180 秒及阶段日志用于诊断，不代表延迟已解决。未验证项、失败记录与各项验收范围按 TEST-REPORT.md 保留。
