# Task A 独立验收

- 修改文件：D:\DeepSeekHarnessData\AGENTS.md
- 备份：D:\DeepSeekHarnessData\backup\20260926-122001-task-a\AGENTS.md
- 修改前 SHA256：03F90B2B6E25C5FA4B71320DF609948B7C7EFF7CC3E9B691459E64935202C45F
- 修改后 SHA256：601AB2D06A26841253DEC34C3BF74D69F3BA2D7A26ACAA4A5B58636D82DE0E81
- 修改前：3255 bytes，53 行（按换行符分割含结尾空行）。
- 修改后：4641 bytes，65 行（同一统计口径）。
- 新增章节：Long-Running Task Rules；仅一次。
- 原文件字节前缀：完整保留；原有规则与 Environment 没有重写。
- Task A 修改其他配置文件：No；cordis.patch.yml：No。

文件验证 PASS。standard 新建 DSH 会话 `session-0314d355-eeec-46ed-bc19-b96e55c0a005` 的实际 request/header 包含新增章节；回答说明了阶段边界、落盘、下轮按进度续接、避免重复、不把单轮拖到 maxTokens，以及区分中间量与真实功能验证。会话正常 completed，短答文本约 1194 字符。证据见 reports/task-a-validation.json。

首次短测试选择 minimal preset，但该 preset 不挂载 agent-instructions，故未作为规则有效性证据；随后改用官方 standard preset，没有修改 preset 或 system prompt。没有重新运行完整 A/B 实验，没有故意制造 token 截断。

已知限制：规则已注入、短答已体现约束；不能据此宣称实际 maxTokens 截断后的长任务自动续接已经验证。现有长寿命会话可能存在上下文惯性。测试时既有记忆/UI 插件会加入额外输出，因此短答带 dsh-ui 块；未为本任务修改这些插件。

本报告属于交付记录。Task B 的系统修改、备份和运行测试单独记账，不计为 Task A 的配置改动。
