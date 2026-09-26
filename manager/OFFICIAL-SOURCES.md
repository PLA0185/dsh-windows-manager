# 官方依据

## 控制台隔离修复依据（2026-09-26）

- [Microsoft Process Creation Flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)：CREATE_NO_WINDOW=0x08000000，不能与 DETACHED_PROCESS 或 CREATE_NEW_CONSOLE 混用以期保留该语义。
- [ProcessStartInfo.CreateNoWindow](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.createnowindow?view=netframework-4.8.1)：与 UseShellExecute=false 配合创建无窗口进程。
- [Microsoft Terminal Default Terminal 规范](https://github.com/microsoft/terminal/blob/main/doc/specs/%23492%20-%20Default%20Terminal/spec.md)：控制台委派给默认 Terminal 的创建流程，PowerShell 主窗口句柄不是充分证据。

实际采用 Windows GUI 子系统启动器隔离后台控制台，不修改用户全局默认 Terminal 设置。

查证日期：2026-09-26（Asia/Shanghai）。DSH 官方文档固定到 commit `477b4f420553e8a52c2fbccc464d7561b239c443`，对应发布 tag `dsh-v0.1.7-rc.2`，GitHub 发布于 2026-09-24 14:10:21 UTC，npm 发布于 14:18:11 UTC。实际阅读的缓存在 `official-docs`。

| 官方资料 | 使用依据 |
|---|---|
| [主 README](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/README.md) | npm 分发、Web 默认地址、no-open |
| [CLI behavior reference](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/apps/cli/reference/README.md) | profile 分层、app 参数、插件 pnpm 转发、bundle reconcile、启动诊断 |
| [Web App README](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/packages/bundle/web-app/README.md) | `dsh --profile web --no-open`、认证 URL、readiness 与完整 Loader 初始化 |
| [Plugin Manager README](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/packages/boot/plugin-manager/README.md) | bundle 与 row 区别、卸载顺序、兼容检查、失败恢复和包替换重启 |
| [Tool Catalog](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/docs/tool-catalog.md#deepseek-aidsh-plugin-manager) | plugin_manager 语义 |
| [Providers Guide](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/docs/user/guide/providers.md) | 模型目录、credential reference、自定义配置与下一次请求生效 |
| [DeepSeek adapter README](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/packages/llm/llm-deepseek/README.md) | models 是整体覆盖、内置目录及容量默认值 |
| [pi-ai adapter README](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/packages/llm/llm-pi-ai/README.md) | 多 provider 与已安装 catalog |
| [当前 Release / Changelog](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.7-rc.2) | 最新 RC、Windows/桌面变更；不是本管理器已验收的功能声明 |
| [Desktop README](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/apps/desktop/README.md) | 评估桌面生命周期与更新；未安装 Desktop 来替换当前 Web/profile |
| [仓库 package.json](https://github.com/deepseek-ai/deepseek-harness/blob/477b4f420553e8a52c2fbccc464d7561b239c443/package.json) | Node `^22.19.0 || >=24.0.0`，开发 pnpm pin `11.7.0` |
| [Node Releases](https://nodejs.org/en/about/previous-releases) | 推荐 LTS；本机 v24.21.0 已满足 |
| [pnpm installation](https://pnpm.io/installation) | Windows 安装方式；当前通用最新版本不能替代 DSH 仓库 pin |
| [Microsoft Task Scheduler](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page) | 独立原生任务运行与登录触发 |
| [Microsoft Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects) | 仅本宿主进程树的生命周期边界 |
| [Win32_Process.Create](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/create-method-in-class-win32-process) / [ProcessStartup](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processstartup) | 备用 WMI 分离运行；正式方案未采用此路径 |

版本查询：官方 npm registry `@deepseek-ai/dsh` 的 `latest=0.1.5-rc.3`，`next=0.1.7-rc.2`，`alpha=0.1.7-alpha.2`；这些标签均非正式稳定版。不能把较旧的 latest 标签当成当前 RC 的升级目标。

官方 CLI 支持 plugin 的 list/add/remove/update/why 等 pnpm 原始语义。管理器通过精确版本 `add package@version` 实现选中包更新，随后官方 CLI reconcile bundle。模型目录不通过虚构的 `dsh models refresh` 命令更新。

运行时认证 RPC 协议还核对了本机同版本官方只读文件：`dsh-client-connection/lib/client.js`、`dsh-api-gateway/lib/index.js`、`dsh-api-settings-controller/lib/typert.*.js`、`dsh-api-session-controller/lib/typert.*.js`。没有修改任何官方包源码。

当前 Web CLI 文档未提供 Windows 服务化、自启或 DSH update 命令；本管理器明确使用 Windows 机制与 npm 分发。Desktop 有自己的后台与更新能力，但不作为当前 Web profile 的生命周期管理接口。
