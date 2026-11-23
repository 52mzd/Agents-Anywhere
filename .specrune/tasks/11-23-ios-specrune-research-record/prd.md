# 补齐 iOS SpecRune 面板的调研与记录维度

## Goal

iOS 客户端 SpecRune 任务详情的「调研」「记录」两个维度，与 DSH SpecRune 插件面板对齐：

- 调研：聚合任务根 `research.md`、任务根 `research-<slug>.md`（历史旧命名）与 `research/` 第一层 `.md`，形成可展开清单；显示文件名与大小，按文件名排序（用户裁决：不改 Connector，不显示修改时间）。
- 记录：聚合任务 `record.md` 与 `.specrune/sessions/*.md` 中 frontmatter `task` 匹配当前任务的会话记录，形成可展开清单；展开时显示 frontmatter 元信息行与去 frontmatter 的正文；时间取自会话记录文件名中的 UTC 时间戳（不是 mtime）。
- 两者都按 1 MiB 字节截断、缺失/读取失败容错，不拖垮任务详情其他维度。

## Confirmed Facts

- DSH 面板行为（只读参照，`/Users/Dae/Downloads/codes/SpecRune/plugins/dsh/panel/`）：
  - 调研：`index.js` 的 `readResearchFiles(dir)` 聚合任务根 `research.md`、任务根 `research-<slug>.md`、`research/` 第一层 `.md`（大小写不敏感、不递归）；同名去重时 `research/` 内版本优先；按 mtime 降序；清单项 `{name, at, bytes, truncated, content}`，1 MiB 字节生切。
  - 调研 UI：`client.js` 的 `TaskDetail` 在「调研」tab 显示「调研报告」+ 计数 + 排序开关（从晚到早/从早到晚）；每项显示文件名、`at`（本地时区秒级）、KB 大小；点击展开 Markdown，默认展开排序后第一项，可全部收起；截断时提示原始字节数。iOS 端按用户裁决不取 mtime，改用文件名排序、去掉时间与排序开关。
  - 记录：`readSessionRecords(repo, taskRef)` 扫 `<repo>/.specrune/sessions/*.md`，解析 frontmatter；`task` 等于任务目录名（或去掉 `NN-MM-` 前缀的短名）才入选；按文件名（UTC 时间戳）倒序；清单项 `{name, at, bytes, truncated, content, body, meta}`；`meta` 取 `title`/`status`/`created`/`developer`/`platform`/`branch`，空值省略；缺闭合 `---`、缺 `id`、`id`/`task` 为空值的畸形记录跳过。
  - 记录 UI：`record.md` 作为历史兼容项固定附在清单末尾（`at` 取文件 mtime），不参与会话记录时间序；每项显示文件名、时间、KB；展开显示 `meta` 行（title · status · created · branch）+ `body` Markdown；默认展开第一项。
  - tab 出现条件：`docs.research` 或 `researchFiles` 非空；`docs.record` 或 `sessionRecords` 非空。
- iOS 现状：
  - `SpecRuneTasksView` 详情 tabs = 概览 + 存在的 `SpecRuneDocKind`；`research`/`record` 目前按单文件 Markdown 渲染，没有多文件清单、时间/大小、排序或会话记录。
  - `SpecRuneKit` 的 `taskDetail` 只读根级 `research.md`/`record.md`（以及 prd/design/implement/review），不读 `research/` 目录、`research-<slug>.md` 与 `.specrune/sessions/*.md`。
  - `SpecRuneTransport` 已有 `shell`、`readText`、`listDirectory`；`SpecRuneDirectoryEntry` 只保留 `name`/`isDirectory`，丢弃 `V2WorkspaceEntry` 的 `size`/`modifiedAt`；`SpecRuneTextFile` 只保留 `content`/`truncated`，丢弃 `size`。
  - Connector 的 `fs.readDir` 当前不返回 `modifiedAt`（`V2WorkspaceEntry.modifiedAt` 在 iOS 已声明为可选字段，Server 透传，但 Connector 未填）；`fs.readText` 返回 `size`。
  - Android 客户端没有 SpecRune 面板（全仓检索零命中），本次只涉及 iOS。
- 既有约束（`.specrune/spec/`）：
  - `ios/markdown-rendering.md`：非流式全文必须显式关闭流式参数（`blockSpacing: 0`、`reservesStreamingHeight: false`），且不能用块数判断新旧；SpecRune 文档标签切换曾因此空白。
  - `ios/index.md`：`shell.exec` stdout 上限 64 000 字符，大列表走 `fs.readDir` + `fs.readText`；iOS UI 改动必须在模拟器/真机实跑才算验证。
  - `connector/local-rpc.md`：`fs.readText` 上限 4 MiB，`shell.exec` 64 000 字符；大列表用目录读取而非 CLI 输出。

## Requirements

1. **调研数据层**：在 `SpecRuneKit` 中聚合三类调研来源，规则与 `readResearchFiles` 一致（根 `research.md`、根 `research-<slug>.md`、`research/` 第一层 `.md`；大小写不敏感、不递归；同名去重 `research/` 优先；1 MiB 字节截断；`bytes` 为真实字节数）；排序按文件名升序（不取 mtime）。
2. **记录数据层**：扫描 `.specrune/sessions/*.md`，按 frontmatter `task` 匹配当前任务目录名（短名兜底），解析 `meta`/`body`，按文件名倒序；`at` 从文件名中的 UTC 时间戳解析并转本地时区展示；畸形记录跳过；`record.md` 固定附在清单末尾；1 MiB 字节截断。
3. **详情数据装配**：`SpecRuneTaskDetail` 携带 `researchFiles` 与 `sessionRecords`；只在需要时读取（不存在的来源不报错），单个来源失败不影响详情其他部分。
4. **调研 UI**：新增「调研」清单视图（标题「调研报告」+ 计数；每项文件名/大小；点击展开 Markdown；默认展开第一项；可全部收起；截断提示），单文件 `research.md` 也走同一清单。
5. **记录 UI**：新增「记录」清单视图（标题「记录」+ 计数；每项文件名/记录时间/大小；展开显示 meta 行 + 正文；默认展开第一项；截断提示），`record.md` 在末尾。
6. **tab 条件**：仅当对应 docs 或清单非空时出现「调研」「记录」；与现有文档 tab 的样式、切换动画、可访问性保持一致。
7. **取数通道**：只经 Connector 既有 `fs.readDir`/`fs.readText`/`shell.exec`；不新增 Server 路由、不新增 Connector RPC method。

## Acceptance Criteria

- [ ] 调研清单：任务根 `research.md`、根 `research-<slug>.md`、`research/` 第一层 `.md` 全部入选；同名时 `research/` 版本优先；按文件名升序；每项显示文件名、KB；默认展开第一项；展开显示正文；超 1 MiB 显示截断提示。
- [ ] 记录清单：仅当前任务的 `.specrune/sessions/*.md` 入选（含短名兜底）；按文件名倒序；每项显示文件名、文件名解析出的记录时间、KB；`record.md` 固定末尾；展开显示 meta 行与去 frontmatter 正文；畸形/无关记录跳过；默认展开第一项；超 1 MiB 显示截断提示。
- [ ] tab 条件与容错：`docs.research` 或调研清单非空才出现「调研」，`docs.record` 或记录清单非空才出现「记录」；单个来源读取失败时详情页仍可打开、其他 tab 正常显示。
- [ ] `SpecRuneKit` 纯逻辑测试覆盖调研聚合/去重/排序/截断与记录匹配/短名兜底/畸形跳过/排序，`swift test` 通过。
- [ ] iOS 模拟器实跑：进入任务详情，切到「调研」「记录」，展开/收起多份文件，确认无空白、无标签/正文错位；非流式 Markdown 参数正确。

## Deliverables

- `SpecRuneKit` 数据层：DTO、调研/记录聚合与解析、测试。
- iOS `SpecRuneTasksView` 调研/记录清单 UI 与 tab 装配。
- 传输层补齐清单所需的 `size`（`SpecRuneTextFile.size` / `SpecRuneDoc.bytes`）；不改 Connector 的 `fs.readDir` 字段。

## Out of Scope

- Android 客户端（当前没有 SpecRune 面板）。
- SpecRune 写操作（worktree、设父、初始化向导、升级器）。
- 新增 Server 路由或 Connector 专用 `specrune.*` RPC method。
- 会话记录实时刷新/订阅、搜索、分页。
- 桌面/Web 端改动。

## Open Questions

- （已裁决，2026-11-23）mtime 来源选 B：不改 Connector；iOS 端按文件名排序、调研清单不显示修改时间。记录清单时间取自文件名中的 UTC 时间戳。

## Coverage taxonomy

- Goal & scope：covered（只 iOS 只读面板；Android/写操作 out）。
- Domain & data：covered（调研文件、会话记录、record.md、task 目录名匹配）。
- Interaction & states：covered（tab 条件、默认展开、收起、加载/失败/空态）。
- Non-functional quality：covered（1 MiB 截断、并发读取上限、失败容错；性能细节在 design.md）。
- Integration & dependencies：covered（Connector `fs.readDir` / `fs.readText` / `shell.exec` 既有端点；不改 Connector、Server）。
- Edge cases & failure handling：covered（同名去重、畸形 frontmatter、CRLF、缺失目录、截断）。
- Constraints & trade-offs：covered（跨端改动范围、会话记录逐个读取的请求成本）。
- Completion signals：covered（swift test + 模拟器实跑）。

## Implicit requirements sweep

- 数据在崩溃后不丢失/不重复：not-applying（只读展示，无持久化）。
- 敏感/个人数据处理：not-applying（只读任务产物与会话记录，已有 Connector 权限边界）。
- 权限与谁可操作：not-applying（沿用现有 Connector 鉴权；不新增写操作）。
- 审计：not-applying（只读）。
- 失败时用户看到什么：applied（Requirements 3/6 与 AC 3：单个来源失败不拖垮详情）。
- 依赖当前行为的兼容性：applied（保留现有文档 tab；`record.md`/`research.md` 单文件仍可读）。
- 可访问性/本地化/合规：applied（沿用现有 tab 的 accessibility；中文标签与 DSH 面板一致）。
