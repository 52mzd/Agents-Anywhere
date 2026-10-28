# Runtime 指令目录直通契约

来源：2026-10-24 "手机 `/` 菜单只有 /compact" 修复。connector 侧改动：
`connector/runtimes/dsh/runtime.py` 移除 compact 白名单过滤与
executeCommand 的非 compact 拒绝（尚未提交时以工作区为准）。

## 契约

**connector 对 DSH 指令目录零过滤、零语义判断**——`listCommands` 与
`executeCommand` 原样直通桥端。目录内容（哪些指令、metadata.ui.kind）
由桥端（dsh-bridge-next `RuntimeCommands`）全权决定；connector 在中间
过滤会**同时向所有客户端隐藏**条目（iOS/Android/Web/Desktop 共用同一条
RPC 链）。

守门职责归桥端：
- 目录收窄（native compact + `/model` selector + 用户可调用 skills）在
  `commands.ts` 的 list；
- execute 拒绝不认识的指令（`unknown_command`）并在技能执行前对照实时
  catalog 复验。

## ok 回执三件套契约（2026-10-28）

桥端返回 `ok: true` 的指令回执必须同时携带 `kind: 'success'`、非空
`commandId`、`executionState: 'accepted'`，且不得带 `retryable` 和顶层
`code`——见 `connector/runtimes/dsh/bridge/models.py` 的
"acknowledgement is incomplete or inconsistent" 校验。缺任何一项会被
connector 降级成 `command_outcome_unknown`，客户端看到的就是
"结果尚不确定"。

- 预算超时等拿不到原生 commandId 的场景，用合成 `pending-<uuid>` 顶替
  （server 只透传不关联，已核实 `sessions.py` execute_session_command）。
- **"结果尚不确定"这条报错文本在 TS 桥、Python connector、server 三层
  逐字存在**——凭消息无法定位来源层。定位方法：取 mtime 最新的
  `~/.agents-anywhere/logs/runtime-*.jsonl`，grep `executeCommand` 看
  duration 与 status（曾实证 status=ok duration_ms=5001：桥端正常返回、
  Python 校验拒绝）。

## 错误模式

- 在 connector 加"客户端还支持不了 X"之类的过滤：菜单内容是运行时下发
  的，客户端只渲染；正确做法是桥端按能力收窄目录，或客户端按
  capabilities 隐藏。
- 文档漂移：`connector/docs/runtime-commands.md` 曾长期描述 compact-only
  旧政策——改这里必须同步该文档。
