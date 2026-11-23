# 设计：补齐 iOS SpecRune 面板的调研与记录维度

## 架构与边界

改动只落在 iOS：

- `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/`：DTO、聚合/解析逻辑、传输层字段。
- `ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift`：详情页的调研/记录清单 UI。
- `ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/`：纯逻辑测试。

Connector、Server、Android、桌面/Web 均不改。数据只经 Connector 既有 `fs.readDir` / `fs.readText` / `shell.exec` 获取，不新增 RPC method 或 Server 路由。

## 数据流与契约

### 1. 传输层补齐大小

清单要显示 KB，而 `readText` 响应本来就带真实字节数 `size`，但 `SpecRuneTextFile` 目前丢弃了它。给 `SpecRuneTextFile` 加 `size: Int`，由 `SpecRuneConnectorTransport.readText` 填 `response.size`；`SpecRuneDoc` 加 `bytes: Int`，由 `taskDetail` 从读文件结果带入。`readSpec` 返回的 `SpecRuneTextFile` 同样带 `size`（UI 暂不使用）。

目录项不加字段：调研/记录清单必须读内容才能展开，读取时自然拿到 `size`，无需先依赖 `fs.readDir` 的 `size`。

### 2. 调研聚合（对齐 `readResearchFiles`）

`SpecRuneClient.researchFiles(repo:taskDir:)`：

1. 列任务目录（`listDirectory`），筛选文件名匹配 `^research(?:-[^/]+)?\.md$`（大小写不敏感）且 `isDirectory == false`。
2. 列 `research/`（存在才列），筛选 `.md`（大小写不敏感）且是文件；子目录、非 `.md` 不读。
3. 合并去重：同名时 `research/` 内版本优先（根版本被覆盖）。
4. 排序：按文件名升序（`localizedStandardCompare`）。用户裁决不改 Connector，因此不取 mtime、不显示修改时间、不提供时间排序开关。
5. 逐个读内容（`readText`），构造 `SpecRuneResearchFile { name, bytes, truncated, content }`；读取失败跳过该文件，不整体失败。

`research.md` 仍会进 `docs.research`（既有 `taskDetail` 逻辑），调研 tab 优先用 `researchFiles`；`researchFiles` 为空但 `docs.research` 存在时，退化为单文件清单（与 DSH 面板同形态）。

### 3. 记录聚合（对齐 `readSessionRecords`）

`SpecRuneClient.sessionRecords(repo:taskRef:)`：

1. 列 `.specrune/sessions`（不存在 → 空数组）。
2. 筛选 `.md`（大小写不敏感）文件，分批并发读取（每批 6 个），解析 frontmatter：
   - 段匹配 `^---\r?\n([\s\S]*?)\r?\n---`；缺闭合段跳过。
   - `id` / `task` 用 `^key:[ \t]*(.*)$`（只吃水平空白，避免空值吞下一行）；空值视为缺失，跳过该条。
   - 入选条件：`task == taskRef` 或 `task == taskRef` 去掉 `^\d{2}-\d{2}-` 前缀后的短名。
   - `meta`：`title` / `status` / `created` / `developer` / `platform` / `branch`，空值省略。
   - `body`：`content` 去掉 frontmatter 段及其后连续空行（`^(?:\r?\n)+`）。
   - `at`：从文件名 `^(\d{8})T(\d{6})-` 解析 UTC 时间，格式化为本地时区 `yyyy-MM-dd HH:mm:ss`；解析失败留空。这是记录生成时间，不是 mtime。
   - `bytes` / `truncated` 来自 `readText`；1 MiB 字节截断由 Connector 的 `maxBytes` 保证。
3. 按文件名倒序（与 DSH 的 UTC 时间戳序一致）。
4. 单个文件读失败跳过；目录读取失败返回空数组，不拖垮详情。

`record.md` 作为历史兼容项固定附在清单末尾：`name = "record.md"`、`bytes` / `truncated` / `content` 来自 `docs.record`，`at` 留空（不取 mtime），`meta` 为空，`body` 用 `content`（DSH 同样直接渲染 record.md 全文）。

### 4. 详情装配

`SpecRuneTaskDetail` 增加 `researchFiles: [SpecRuneResearchFile]` 与 `sessionRecords: [SpecRuneSessionRecord]`。`taskDetail` 在读完 docs/context 后调用两个聚合函数；两个调用各自容错，失败返回空数组。会话记录读取会逐文件请求，详情加载时间可能增加（见风险）。

### 5. UI 装配

`SpecRuneTasksView` 的 `DetailTab` 保持 `overview` + `doc(kind)`，可见性改为：

- `research`：`detail.researchFiles` 非空，或 `docs[.research]` 存在。
- `record`：`detail.sessionRecords` 非空，或 `docs[.record]` 存在。
- 其它 kind：`docs[kind]` 存在（不变）。

正文：

- `research` → 调研清单：标题「调研报告」+ 计数；每项「展开箭头 + 文件名 + KB」；点击展开/收起；默认展开第一项（`@State openResearch: String?`，`nil` = 未点过，`""` = 全部收起）；展开区用 `ChatMarkdownView(text:blockSpacing:0,reservesStreamingHeight:false)`，截断时提示原始字节数。
- `record` → 记录清单：标题「记录」+ 计数；每项「展开箭头 + 文件名 + 记录时间 + KB」；展开区先显示 `meta` 行（`title · status · created · branch`，空值省略），再显示 `body` Markdown；默认展开第一项；截断提示；`record.md` 在末尾。
- 其它 kind → 现有 `docBody` 不变。

加载/空态：清单数据随详情加载；读取失败时对应 tab 不出现或显示空态说明。保留现有 `ProgressView` / `ContentUnavailableView` 语义。

## 兼容性与迁移

- `SpecRuneTextFile` / `SpecRuneDoc` / `SpecRuneTaskDetail` 加字段：更新包内构造点与测试；字段都是新增，不影响既有调用方。
- 既有文档 tab（PRD/设计/实施/审查）与概览行为不变；`record.md` / `research.md` 单文件仍可通过清单查看。
- 不改 Connector/Server，因此没有协议版本、迁移或发布顺序要求。
- iOS 端不新增权限；读取范围仍限制在任务目录与 `.specrune/sessions`（`fs.readText` 的 repo 约束不变）。

## 取舍与风险

- **会话记录逐文件读取**：`.specrune/sessions` 可能有上百个文件，详情加载时逐个 `readText` 会增加延迟。缓解：每批 6 个并发、单文件失败跳过、详情按 repo|ref 缓存。若实测明显拖慢详情，后续改为「点击记录 tab 时懒加载」；本次先一次性加载以对齐 tab 条件。
- **调研排序语义**：没有 mtime，按文件名升序是确定性替代；不提供时间排序开关（用户已裁决接受）。
- **记录时间来源**：文件名 UTC 时间戳是记录生成时间，通常接近 DSH 面板显示的 mtime；不取 mtime 是用户裁决的结果。
- **tab 条件偏差**：记录 tab 依赖 `sessionRecords` 非空（一次加载后才能判断），与 DSH 面板一致；若加载失败则按空态处理，不显示虚假数据。
- **截断**：1 MiB 由 Connector `readText` 的 `maxBytes` 保证；UI 只提示，不拼接。

## 回滚

改动集中在 SpecRuneKit 与 SpecRuneTasksView，回滚即删除新增 DTO/聚合函数/UI 分支，并恢复 `SpecRuneTextFile`/`SpecRuneDoc`/`SpecRuneTaskDetail` 的构造参数。Connector/Server 未改，无跨端回滚。

## 备选方案

- **A. Connector 补 `fs.readDir` 的 `modifiedAt`**：功能与 DSH 完全对齐（时间、按时间排序），但跨端改动、需跑 Connector 测试；用户裁决选 B，本次不做。
- **B. 只改 iOS，按文件名排序、不显示修改时间**：已选。范围最小，调研清单缺时间与时间排序。
- **C. 会话记录懒加载**：详情加载更快，但记录 tab 的出现条件无法在加载前判断（会显示空 tab 或需要额外的目录探测）；本次选一次性加载，保留后续优化空间。
- **D. 记录时间不显示**：更贴近「不显示修改时间」的字面裁决，但会丢掉文件名里可靠的记录时间；本次显示文件名解析出的记录时间（不是 mtime）。
