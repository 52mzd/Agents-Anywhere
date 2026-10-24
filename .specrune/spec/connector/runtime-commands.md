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

## 错误模式

- 在 connector 加"客户端还支持不了 X"之类的过滤：菜单内容是运行时下发
  的，客户端只渲染；正确做法是桥端按能力收窄目录，或客户端按
  capabilities 隐藏。
- 文档漂移：`connector/docs/runtime-commands.md` 曾长期描述 compact-only
  旧政策——改这里必须同步该文档。
