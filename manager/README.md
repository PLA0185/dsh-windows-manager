# DSH Windows Manager

正式入口：`D:\DeepSeekHarnessData\manager\DSH-Manager.ps1`。无参数启动中文菜单。

## 双击入口

在 `D:\DeepSeekHarnessData` 双击以下文件即可，无需手动输入命令：

推荐直接使用下面三个 VBS：全程不创建可见 CMD/Terminal。三个同名 BAT 是兼容入口，仍可使用，但 Windows 启动 BAT 时可能闪一下 CMD；它们不参与登录自启。DSH_Manager.bat 是需要显示的中文菜单，保留控制窗口属于预期行为。

| 文件 | 功能 |
|---|---|
| DSH_Start.bat | 一键启动后台 DSH；已经运行时保持当前实例 |
| DSH_Stop.bat | 一键停止本管理器的 DSH |
| DSH_Restart.bat | 一键重启 DSH |
| DSH_Manager.bat | 打开中文管理菜单 |

完全无窗口请双击根目录的 `DSH_Start.vbs`、`DSH_Stop.vbs`、`DSH_Restart.vbs`，分别执行启动、停止、重启。它们调用 GUI 类型的 `manager\DSH-Launcher.exe`，由启动器以 UseShellExecute=false / CreateNoWindow=true 创建 PowerShell。失败写入 `manager\logs\manager.log` 和 `launcher.log`。

三个对应 BAT 已改为转交给 VBS，执行期间不保留 CMD 窗口，但双击 BAT 时 Windows 仍可能短暂显示 CMD。中文管理菜单仍有可见控制窗口，关闭菜单不会停止后台 DSH。这些入口只调用新管理器，不自行创建后台实例、自启入口或执行按名称杀进程。旧六个 BAT 仍保留在备份内。登录自启继续使用现有隐藏计划任务，无需运行双击入口。

```powershell
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1'
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' status
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' start
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' stop
& 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' restart
```

如果本机执行策略阻止本地脚本，可仅对当前进程使用系统 PowerShell 参数：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\DeepSeekHarnessData\manager\DSH-Manager.ps1' status
```

## 后台与自启

Windows Task Scheduler 的 `DSH Manager Web` 任务运行 GUI 类型的 `DSH-Launcher.exe host`。启动器以 CreateNoWindow=true 创建系统 Windows PowerShell 5.1，避免默认 Windows Terminal 接管可见控制台。`DSH-Host.ps1` 用无窗口进程启动官方 DSH CLI，并将该实例及后代放入独立 Job Object。控制器窗口退出不结束任务；宿主退出时 Job Object 清理其 DSH 后代。

配置明确指定 `DSH_HOME=D:\DeepSeekHarnessData`、profile、Node、CLI 与 pnpm 路径。官方等价命令为 `dsh.cmd --profile web --no-open`。启动需通过进程身份、创建时间、端口、认证 RPC 和 8 秒稳定窗口。已有本管理器实例时不会重复启动；未知监听者不会被停止。

启动等待上限为 180 秒。迁移测试中曾有一次系统 PowerShell 宿主在创建 Node 之前延迟约两分钟，后续启动恢复正常；具体原因未确定。新增宿主阶段日志便于继续定位，不能把延长等待视为延迟已解决。超时不会报告启动成功，请用 status、doctor 和日志核对实际状态。

```powershell
.\DSH-Manager.ps1 autostart enable
.\DSH-Manager.ps1 autostart disable
.\DSH-Manager.ps1 autostart status
```

自启采用**当前用户登录**触发，延迟 30 秒；不是用户尚未登录时启动的系统服务。任务保持启用，关闭自启只移除触发器，手动 start 仍可用。当前配置已开启登录自启。计划任务使用 Interactive 登录类型：注销后停止，下一次登录重新启动。注销、重启的真实效果尚未验证。

Windows Web CLI 没有已查证的官方 HTTP 停止接口。停止请求由独立 Host 执行，关闭其自己持有的 Job Object；这是有边界的强制停止，不宣称正常 SIGTERM 退出。不使用按名称杀死全部 Node 的命令。维护前请让正在运行的 DSH 对话结束。

备用 WMI 后台机制仅在配置 `backend=wmi` 时使用。正式安装使用计划任务；备用路径未做最终验收。

## 模型

```powershell
.\DSH-Manager.ps1 models list
.\DSH-Manager.ps1 models select '<实际 Model ID>' -Provider '<实际 Provider ID>'
.\DSH-Manager.ps1 models refresh
.\DSH-Manager.ps1 models refresh -Apply
```

运行时从官方 `session/modelCatalog` 读取真实可选目录，从官方设置描述读取容量字段。切换通过官方 `settings/mutate` 只设置默认 Provider/Model，并以 revision 防止覆盖并发设置；保留 reasoningEffort、凭据、endpoint 和自定义模型。默认选择对新会话/下一次请求生效，已发送请求的会话保留自己的选择。离线列表仅列出 profile 显式声明的模型，不冒充完整运行时目录。

内置目录随 DSH/provider 包发布；`refresh` 检查配置渠道并重新读取目录。当前 profile 的 `models` 是用户显式覆盖，刷新不会删除或覆盖它。发现包新版后必须显式 `-Apply`，通过运行要求和快照检查后才能更新。自定义 provider 的在线发现请使用官方 Settings → Models → Fetch available models；管理器不伪造通用刷新 API。非 DeepSeek Provider 未由当前环境实际验证，无法从设置取得的容量显示为空。

## 插件与 DSH 更新

```powershell
.\DSH-Manager.ps1 plugins list
.\DSH-Manager.ps1 plugins remove '<列表中的精确包名>' -WhatIf
.\DSH-Manager.ps1 plugins remove '<列表中的精确包名>'
.\DSH-Manager.ps1 plugins update
.\DSH-Manager.ps1 plugins update '<列表中的精确包名>' -WhatIf
.\DSH-Manager.ps1 plugins update '<列表中的精确包名>'
.\DSH-Manager.ps1 dsh update
.\DSH-Manager.ps1 dsh update -Apply -WhatIf
.\DSH-Manager.ps1 dsh update -Apply
```

插件 list 显示包名（同时为 bundle identifier）、实际版本、bundle 选择、disabled 行数、来源、spec 和 peer 兼容警告计数。完整行 ID、peers 与禁用状态保存于快照 `reports/plugins.json`。包选择为 enabled 不代表每个子插件成功加载，真实启动错误见 doctor 和 DSH diagnostics。

插件更新默认只检查；指定单个已安装 npm 包后查询精确 registry 版本并检查 DSH peers。Git/local 更新不猜测 spec，请自行审阅后使用官方 CLI；卸载支持这些已安装包。官方基础组件在本管理器中受保护。普通卸载先展示声明行影响，询问 YES、自动快照、停止、官方 remove、验证 manifest/YAML、重新启动。失败保留日志并尝试保护恢复。`-Yes` 可在明确的自动化操作中代替交互确认。

DSH 配置渠道为 `next`，与当前 RC 安装一致，避免 npm `latest` 意外降级。执行升级前读取目标版本官方 tag 的 Node engines 与 pnpm pin，并检查现有插件的 DSH peers；要求不满足即拒绝更新。0.x 的次版本边界也视为兼容性边界，必须审阅并显式 `-AllowMajor`。不会自动升级 Node/pnpm。当前 pnpm 10.20.0 已验证可维护现有 profile，但当前仓库开发 pin 是 11.7.0，未来执行 DSH 升级前需单独处理这项要求。

更新前快照，更新后版本回读及后台健康验证；失败提供保护恢复选项。当前无新版，真实 DSH 升级、插件新版升级及升级失败回滚未验证。peer Warning 本身不等于启动 Error；管理器不会为消除警告修改官方源码或强行安装不兼容版本。

## 快照与恢复

```powershell
.\DSH-Manager.ps1 snapshot create 'manual'
.\DSH-Manager.ps1 snapshot list
.\DSH-Manager.ps1 snapshot restore '<精确快照 ID>' -WhatIf
.\DSH-Manager.ps1 snapshot restore '<精确快照 ID>'
```

快照在 `history`，并镜像到 `D:\DeepSeekHarnessData\backup\<同一 ID>`。包含 profile 关键配置、lockfile、pnpm 策略、兼容许可（若存在）、管理器源文件/config、AGENTS、插件清单、版本与 SHA256。默认不复制凭据、聊天历史、缓存及大型 node_modules。检测到内联 secret/API Key 的配置会拒绝快照并中止变更；请先用官方凭据引用迁移。Web 启动 URL 使用当前用户 DPAPI 加密存入 `state`，日志中 token 被脱敏。

恢复只接受有效 manifest 和白名单文件，先校验摘要、保护当前状态，再停止实例，必要时安装匹配 DSH 版本，恢复 profile，执行官方 CLI `install --frozen-lockfile --ignore-scripts`，最后启动验证。禁用构建脚本意味着某些曾依赖安装脚本生成的第三方包可能需要明确的重新构建授权；此时诊断保留，不宣称恢复成功。

恢复不会覆盖 `.credentials.yaml`、原始会话、工作区项目或全局 AGENTS。快照里的 AGENTS 和管理器文件用于审计/人工回滚，避免 Task B 恢复覆盖独立 Task A。升级 DSH 时可恢复目标快照记录的精确 CLI 版本。管理器版本回滚方法见 `ROLLBACK.md`。

## 诊断、日志和移除

```powershell
.\DSH-Manager.ps1 doctor
.\DSH-Manager.ps1 logs
```

doctor 只读检查执行路径、profile/YAML/lock、监听者、重复 DSH、计划任务、Run/Startup、插件 peer 状态及最近错误。日志分为 `dsh-host.log`、`manager.log`、`update.log`、`plugin-operations.log`、`restore.log`；10 MiB 轮转，最多 5 个历史文件。失败 diagnostics 的完整堆栈保留，凭据字段脱敏。退出码 0 表示成功/已处于目标状态，1 表示失败，WhatIf 不改包或系统目标配置。

完全停用：先 `autostart disable`，再 `stop`，之后删除已停用的 `DSH Manager Web` 任务。确认需要保留的 history/backup 已另存后可人工移走 manager 目录；不要删除 DSH_HOME 或 profile。旧 BAT 仅保存在旧环境快照，恢复旧体系需要按 `ROLLBACK.md` 有意执行。

验收范围和未验证项见 `TEST-REPORT.md`；官方依据见 `OFFICIAL-SOURCES.md`。

## 控制台窗口故障修复（2026-09-26）

用户实测发现关闭可见 Windows Terminal 后 DSH 立即退出，推翻了此前仅以 MainWindowHandle=0 判定无窗口的结论。计划任务和 VBS 都已转用 GUI 启动器。Host 实际记录 GetConsoleWindow=0，控制台进程列表仅自身；旧主窗口断言不能作为无可见 Windows Terminal 的充分证据。最新验证见 reports/console-isolation.json，真实 GUI 点按关闭的用户观察与进程级测试分开记账。

启动器源文件为 DSH-Launcher.cs；本机可用系统 .NET Framework csc.exe 以 /target:winexe 重新编译 DSH-Launcher.exe。launcher.log 同样按 10 MiB、5 份历史轮转并脱敏。不改变用户全局默认终端设置。
