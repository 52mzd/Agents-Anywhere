# 审查第 1 轮：11-23-ios-specrune-research-record

本轮为第 1 轮审查，无旧 findings。审查对象：`git diff` 的全部改动 + 未跟踪新增文件 `ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/FakeTransport.swift`、`ResearchRecordTests.swift`。

## 验证（独立复跑）

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` → 35 tests / 6 suites 全绿（exit 0）。
- `cd ios/Packages/SpecRuneKit && swift build --disable-sandbox` → Build complete（exit 0）；仅有 `~/Library/org.swift.swiftpm` 缓存不可写的沙箱警告，不影响构建。
- `xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO`：普通命令被沙箱拒绝（exit 74，`cannot open file '/Users/Dae/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/*.dia' (Operation not permitted)`）。用 `CFFIXED_USER_HOME=<tmp>/home -packageCachePath <tmp>/pkgcache -derivedDataPath <tmp>/dd OTHER_SWIFT_FLAGS="-disable-sandbox"` 复跑 → **BUILD SUCCEEDED**（exit 0）。临时目录在 `/tmp`，未写入仓库。
- `shasum -a 256 contracts/specrune/1.0/schemas/task-detail.response.schema.json` → `9b069330c37c7bf0de76a4196e772c9ba213131ffc084d75619ffc37d1ff3ec3`，与 `manifest.json` 一致。
- `python3 -m json.tool` 校验 schema 与 manifest → 均合法。
- `git diff --check` → 无空白错误。
- `git status --short connector/ server/` → 空；`android/ desktop-workbench/ web-next/` → 空。
- 未跑 Draft 2020-12 schema 校验：本机无 `jsonschema` 模块（`No module named 'jsonschema'`），README 的验证脚本无法执行。
- 未做实跑：模拟器/真机 UI 验收未做（见 F1）。

## F1 blocker docs/specrune-mobile/README.md:59

- evidence: prd.md:46 的验收标准要求「iOS 模拟器实跑：进入任务详情，切到「调研」「记录」，展开多份文件……确认无空白、无标签/正文错位」，`.specrune/spec/ios/index.md:41-43` 也要求 iOS UI 改动必须在模拟器/真机实跑一次才算验证；而 `docs/specrune-mobile/README.md:59` 明确写着「未做：真机 / iPhone Duo 模拟器实跑（含「调研」「记录」清单的展开与截断提示）」。本轮只有编译、单测与静态核对，没有 UI 实跑证据。另：当前仓库没有调研数据源（`ls .specrune/tasks/*/research*` 与 `ls .specrune/tasks/*/research/*.md` 均为空，归档任务目录只有 prd/design/implement/check/review/task.json，没有 `record.md`），因此调研 tab、`research.md` 单文件兜底、`record.md` 固定末尾三项需要在临时造数据后实跑；记录 tab 有真实数据可验（`.specrune/sessions/` 中 task 匹配归档任务 `11-21-fix-specrune-board-picker-drawer-shift`、`11-13-sync-upstream-package-dsh-plugin`、`11-04-ios-duo-cover-sidebar` 的记录）。
- status: open

## F2 minor .specrune/tasks/11-23-ios-specrune-research-record/prd.md:46

- evidence: 验收标准第 5 条仍写「展开多份文件、切换排序」，但 prd.md:15 与 prd.md:64 的用户裁决、design.md:28/81 都明确 iOS 端「去掉时间与排序开关」（不改 Connector、不取 mtime）。实现（`SpecRuneTasksView.swift` 的 `researchBody`/`recordBody`）没有排序开关，符合裁决；AC 未同步更新会让验收按「切换排序」检查而误判缺失。建议把 AC 第 5 条的「切换排序」删掉或改为「展开/收起多份文件」。
- fix: prd.md:46 按裁决 B 把「展开多份文件、切换排序」改为「展开/收起多份文件」，其余验收点（无空白、无标签/正文错位、非流式 Markdown 参数）保持不变。
- status: open

## F3 minor ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1062

- evidence: prd.md:15 把 DSH 面板行为列为参照：「截断时提示原始字节数」；DSH `client.js` 实际显示「已截断：原始 N 字节，仅显示前 1 MiB」。iOS 清单行的截断提示只显示「已截断：原文超过 1 MiB」，没有使用已经携带真实字节数的 `SpecRuneResearchFile.bytes` / `SpecRuneSessionRecord.bytes`。AC 第 1/2 条只要求「显示截断提示」，故不算 blocker；但数据已具备，补齐即可与 DSH 对齐。
- fix: `SpecRuneTasksView.swift:1068` 改为 `Text(verbatim: "已截断：原始 \(bytes) 字节，仅显示前 1 MiB")`，`bytes` 即行传入的 `SpecRuneResearchFile.bytes` / `SpecRuneSessionRecord.bytes`（`record.md` 项用 `docs.record.bytes`），与 DSH `client.js:1325/1366` 同文案。`docBody`（PRD/设计等单文档）的同类提示不属于本 finding，未改。
- status: open

## F4 minor contracts/specrune/1.0/schemas/task-detail.response.schema.json:122

- evidence: `SessionRecord.at` 描述为「本地时区 yyyy-MM-dd HH:mm:ss，取自文件名中的 UTC 时间戳」，`contracts/specrune/1.0/README.md:56` 同样写法；但 DSH `readSessionRecords` 实际返回 `at: isoOf(st.mtime)`（ISO 8601 mtime），而 README:76「与现有实现的对齐」仍称字段语义以 `index.js` 为准。同一 schema 的 `ResearchFile.at`（第 110 行）注明了「iOS 客户端不取 mtime」，`SessionRecord.at` 却没有对应的客户端差异说明，契约对「DSH 用 mtime / iOS 用文件名时间」的区分不完整。
- fix: schema `task-detail.response.schema.json:122` 的 `SessionRecord.at` 描述改为说明客户端差异（DSH 宿主返回文件 mtime ISO 8601；iOS 不取 mtime，改用文件名 UTC 时间戳格式化成本地 `yyyy-MM-dd HH:mm:ss`，无合法时间戳为空）；`README.md:56` 的记录清单条目同步标注该差异，`README.md:77`「与现有实现的对齐」新增「时间字段的客户端差异」条目（覆盖 `ResearchFile.at` 与 `SessionRecord.at`）。`manifest.json:29` 的 sha256 已重算为 `ae061485ce712a45f81b07c829ef5eb3785017b2786aff35fedacf193798ace2`，5 个 schema 与 manifest 全量核对一致。
- status: open

## F5 nit ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneClient.swift:406

- evidence: `recordDate(fromName:)` 只校验数字与 `T`/`-` 位置，不校验日期合法性。实测 `Calendar.date(from:)` 会把 `2026-02-30` 调整为 `2026-03-02`、`2026-13-01` 调整为 `2027-01-01`，与设计「解析失败留空」在非法日期上不一致。实际 CLI 生成的会话文件名总是合法日期，故为 nit；现有测试只覆盖「文件名不含时间戳时留空」。
- fix: `SpecRuneClient.swift:435-444` 在 `Calendar.date(from:)` 后用同一 UTC Calendar 反向取年/月/日/时/分/秒并与输入核对，任一不一致返回空（等价严格解析）；`ResearchRecordTests.swift:322` 新增「`2026-02-30` / `2026-13-01` 不被顺延」用例，`:342` 新增闰日 `2024-02-29` 合法对照用例。`swift test --disable-sandbox` 37 tests / 6 suites 全绿。
- status: open

## F6 nit ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1055

- evidence: `SpecRuneDocListRow` 的 `accessibilityLabel` 只包含文件名与 KB；记录行在视觉上显示了 `at`（记录时间），VoiceOver 不播报该时间。requirement 6 的可访问性要求主要针对 tab，且原有文档 tab 也没有显式 label，故为 nit。
- fix: `SpecRuneTasksView.swift:1029-1034` 新增 `accessibilityText`（文件名 + `at` 非空时拼记录时间 + KB），`:1061` 的 `accessibilityLabel` 改用它；调研行 `at` 为空，播报内容与原来一致。
- status: open

Candidate: red

## 审查第 2 轮（append-only；第 1 轮内容见上，未改动）

审查对象：`git diff` 的全部改动 + 未跟踪新增文件 `ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/FakeTransport.swift`、`ResearchRecordTests.swift`。逐条复核第 1 轮 F1–F6 的 fix，再找新问题。

### 验证（独立复跑）

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` → **37 tests / 6 suites 全绿**（exit 0）。
- `cd ios/Packages/SpecRuneKit && swift build --disable-sandbox` → Build complete（exit 0）；仅有 `~/Library/org.swift.swiftpm` 缓存不可写的沙箱警告，不影响构建。
- `xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO`：**本轮未能复跑**。普通命令与三种 workaround 均被沙箱拒绝：`CFFIXED_USER_HOME`/`-packageCachePath`/`-derivedDataPath` 指向 `/tmp` + `OTHER_SWIFT_FLAGS="-disable-sandbox"`、`-disableAutomaticPackageResolution`、`-clonedSourcePackagesDirPath` 指向已有 DerivedData，均报 `xcodebuild: error: Could not resolve package dependencies: sandbox-exec: sandbox_apply: Operation not permitted`（exit 1）。这是 DSH 文件沙箱不允许子进程应用 seatbelt profile，不是代码错误；临时目录都在 `/tmp`，未写入仓库。
- 部分替代：`xcrun swiftc -parse "ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift"` → exit 0（只验证语法，未做类型检查）。
- `shasum -a 256 contracts/specrune/1.0/schemas/task-detail.response.schema.json` → `ae061485ce712a45f81b07c829ef5eb3785017b2786aff35fedacf193798ace2`，与 `manifest.json` 一致；5 个 schema 全量哈希逐一核对均一致（`ALL_MATCH`）。
- `python3 -m json.tool` 校验 schema 与 manifest → 均合法。
- `git diff --check` → 无空白错误。
- `git status --short connector/ server/ android/ desktop-workbench/ web-next/` → 空（0 行）。
- 未做：模拟器/真机 UI 实跑（F1 仍 open）；`xcodebuild` 未复跑，UI 代码本轮无编译验证（F3/F6 的 fix 只有语法解析兜底）。

### 旧 finding 验证

- **F1 blocker：仍 open。** `docs/specrune-mobile/README.md:59` 仍写「未做：真机 / iPhone Duo 模拟器实跑（含「调研」「记录」清单的展开与截断提示）」；本轮没有实跑证据，`xcodebuild` 也被沙箱拒绝，UI 代码连编译验证都没有。主会话正在处理用户裁决，本轮不标记 deferred/verified。
- **F2 minor：verified。** `prd.md:46` 已按裁决 B 改为「展开/收起多份文件」，不再写「切换排序」；AC 第 1–4 条与第 5 条其余验收点（无空白、无标签/正文错位、非流式 Markdown 参数）未降低。残留见新 F7。
- **F3 minor：verified。** `SpecRuneTasksView.swift:1068` 的截断提示用行内 `bytes`（`Int`）显示「已截断：原始 \(bytes) 字节，仅显示前 1 MiB」；调研项取 `SpecRuneResearchFile.bytes`、记录项取 `SpecRuneSessionRecord.bytes`、`record.md` 项取 `docs.record.bytes`，与 DSH `client.js:1325/1366` 同文案。`bytes` 类型正确，无回归；`docBody`/`specRow` 的同类提示按 F3 范围未改。
- **F4 minor：verified。** schema `SessionRecord.at`（第 122 行）已注明「DSH 宿主返回文件 mtime ISO 8601；iOS 用文件名 UTC 时间戳格式化成本地 `yyyy-MM-dd HH:mm:ss`，无合法时间戳为空」；`contracts/specrune/1.0/README.md:56` 与 `:77` 同步标注客户端差异；`manifest.json` 的 sha256 `ae061485…` 与实际 `shasum` 一致，5 个 schema 全量核对一致。
- **F5 nit：verified。** `SpecRuneClient.recordDate` 在 `Calendar.date(from:)` 后用同一 UTC Calendar 反向核对年/月/日/时/分/秒，`2026-02-30` / `2026-13-01` 返回空；`ResearchRecordTests.swift:321-355` 覆盖非法日期与闰日 `2024-02-29` 对照用例；`swift test` 37 tests 全绿。合法日期未被误拒（闰日用例通过）。
- **F6 nit：verified。** `SpecRuneTasksView.swift:1029-1033` 的 `accessibilityText` 在 `at` 非空时拼记录时间，`:1061` 的 `accessibilityLabel` 使用它；调研行 `at` 为空，播报内容与原来一致。

### 新 findings

#### F7 minor .specrune/tasks/11-23-ios-specrune-research-record/prd.md:70

- evidence: Coverage taxonomy 第 70 行仍写「Interaction & states：covered（tab 条件、默认展开、收起、**排序开关**、加载/失败/空态）」，第 72 行仍写「Connector 字段补齐为 Open Question」。裁决 B（prd.md:15/64、design.md:28/81）已明确去掉排序开关、不改 Connector；F2 只改了 AC 第 5 条，这两处残留会让人误以为仍需排序开关或 Connector 字段。
- fix: `prd.md:52` Deliverables 去掉「若确认需要改 Connector…modifiedAt」条件句，改为只补 `size`（`SpecRuneTextFile.size` / `SpecRuneDoc.bytes`）且不改 Connector 的 `fs.readDir` 字段；`:70` Coverage taxonomy 删去「排序开关」；`:72` 改为 Connector `fs.readDir` / `fs.readText` / `shell.exec` 既有端点、不改 Connector/Server。三处均与 design.md:11/17/28/75 一致。
- status: open

#### F8 minor docs/specrune-mobile/README.md:55

- evidence: 写「`cd ios/Packages/SpecRuneKit && swift test` → **35 个测试**全绿」，实测 `swift test --disable-sandbox` 为 **37 tests / 6 suites**（F5 fix 新增 `rejectsInvalidDates`、`acceptsLeapDay` 两个用例后未同步）。文档的验证状态与当前测试数不一致。
- fix: `docs/specrune-mobile/README.md:55` 的「35 个测试全绿」改为「37 个测试全绿（6 suites，含调研聚合、会话记录解析与详情装配）」，与 `swift test --disable-sandbox` 实测 37 tests / 6 suites 一致。
- status: open

#### F9 nit ios/Packages/SpecRuneKit/Sources/SpecRuneKit/Transport.swift:26

- evidence: `SpecRuneTransport` 的文档注释（第 26–30 行）与 `SpecRuneTextFile` 的注释（第 31 行）连续、中间无空行，整块归属 `SpecRuneTextFile`，协议本身反而没有 doc comment。本任务改第 31 行时未修正归属。既有错位，不影响编译与行为。
- fix: `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/Transport.swift:26` 只保留 `SpecRuneTextFile` 自身说明；原协议注释整块移到 `:50-53` 协议声明（`:54`）前，改写为「宿主（主 app）提供的传输能力：跑 shell、读文本、列目录」并同步为 `shell/exec`、`fs/readText`、`fs/readDir` 三条端点。仅注释变动。
- status: open

#### F10 nit docs/specrune-mobile/README.md:10

- evidence: 文件说明仍写「把 `shell/exec` 与 `fs/readText` 桥成 `SpecRuneTransport`」；`SpecRuneConnectorTransport.swift:6` 头注释同样写「只用官方 Server 既有的两条端点：`shell/exec` 与 `fs/readText`」。本任务的调研/记录清单依赖 `listDirectory`（`fs.readDir`），取数表第 27 行已补，但文件说明与传输层头注释未同步。既有描述不完整，非本轮引入。
- fix: `docs/specrune-mobile/README.md:10` 文件说明改为「把 `shell/exec`、`fs/readText` 与 `fs/readDir` 桥成 `SpecRuneTransport`」；`ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneConnectorTransport.swift:6` 头注释改为「只用官方 Server 既有的三条端点：`shell/exec`、`fs/readText` 与 `fs/readDir`」。
- status: open

### 新 blocker/major 排查

- 调研聚合（三来源、大小写不敏感、同名 `research/` 优先、文件名升序、单文件失败跳过）符合 prd Requirements 1/4 与 design.md:23-31。
- 记录解析（frontmatter 匹配、短名兜底、畸形跳过、CRLF、meta 空值省略、文件名 UTC 转本地、按文件名倒序、每批 6 并发）符合 prd Requirements 2/5 与 design.md:35-49；`record.md` 固定末尾、`at` 留空符合裁决 B。
- 详情装配（`researchFiles`/`sessionRecords` 各自容错、失败空数组）符合 Requirements 3；tab 条件 `researchFiles` 非空或 `docs.research`、`sessionRecords` 非空或 `docs.record` 符合 Requirements 6 与 design.md:57-61。
- 非流式 Markdown 全部使用 `ChatMarkdownView(blockSpacing: 0, reservesStreamingHeight: false)`（researchBody/recordBody），符合 `ios/markdown-rendering.md`。
- 契约 schema/manifest/README 三者一致：sha256 一致、JSON 合法、`SessionRecord`/`SessionMeta` 与 iOS DTO 形状一致、`ResearchFile.at` 可选且 iOS 省略。
- `git status --short connector/ server/ android/ desktop-workbench/ web-next/` 为空，未越界改上游。
- `review.md` 第 1 轮 fix 记录格式（finding id/severity/file:line/evidence/fix/status）合规，本轮为 append-only 追加。

### Candidate

Candidate: red（F1 blocker 仍 open；F7/F8/F9/F10 为待主会话 fix pass 的新 finding。本轮只写 review.md，未改代码/规格/任务产物。）

## 实跑（主会话，2026-11-24 04:00–04:18）

用户人工登录 iPhone Duo 模拟器（138A5F69-4F9D-4FE2-A215-E1DAB226A92F）；用签名构建（Sign to Run Locally）安装最新 app。测试数据造在归档任务 `11-21-fix-specrune-board-picker-drawer-shift`：`research.md`、`research-legacy.md`、`research/topic.md`、`research/big.md`（1.9 MB）、`record.md`。

已验证：
- 记录 tab：2 项（会话记录 + `record.md` 末尾），显示文件名/时间/KB，默认展开第一项；展开显示 meta 行（title · status · created · branch）与 Git Commits/Summary 正文；`record.md` 展开显示正文。无空白/错位。
- 调研 tab：4 项按名称升序（big.md、research-legacy.md、research.md、topic.md），显示 KB，默认展开第一项；big.md 显示「已截断：原始 1980076 字节，仅显示前 1 MiB」；topic.md / research.md 展开正文正常。
- 概览 tab 正常；tab 条含概览/PRD/设计/实施/记录/调研/审查。

## F11 blocker ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift（调研/记录清单展开区）

- evidence: 展开 `research/big.md`（1.9 MB，截断后 1 MiB）时 app 崩溃退出（SIGSEGV；SwiftUI `Text.resolve` 递归 16349 层栈溢出，崩溃日志 `~/Library/Logs/DiagnosticReports/Agents Anywhere-2026-11-24-041539.ips`）。截断提示已显示，但把 1 MiB / 约 90000 段落的正文交给 ChatMarkdownView 渲染导致栈溢出。正常文件（topic.md / research.md / 会话记录）正文正常。
- fix: `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneDocClamp.swift:9-24` 新增 `SpecRuneDocClamp`（`maxCharacters = 64_000`；`clamp(_:maxCharacters:) -> (text: String, clamped: Bool)` 按 `Character` 数截到前 64 000）；`ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:999-1014` 新增私有 `SpecRuneDocMarkdown`，`:670`（调研展开区）与 `:697`（记录展开区）改用它——超过 64000 字符时只把前 64000 字符交给 `ChatMarkdownView`，并在正文下方显示「正文过大，仅显示前 64000 字符（原始 N 字节）」；既有「已截断：原始 N 字节，仅显示前 1 MiB」提示保留（大文件两条同时显示）；`ChatMarkdownView` 通用组件与其它文档 tab 的 `docBody` 未改。`ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/SpecRuneDocClampTests.swift:8-37` 新增短文本原样/超长截到 64000/空文本/恰好阈值四个用例；`swift test --disable-sandbox` 41 tests / 7 suites 全绿，`swift build --disable-sandbox` exit=0，`xcodebuild build` → BUILD SUCCEEDED。
- status: open

F1 实跑已执行；因 F11 崩溃，AC 第 1 条「展开显示正文」对大文件未满足，F1 仍 open，待 F11 修复后复跑。

## F11 fix（第 2 次，2026-11-24）

- 阈值从 64 000 降到 16 000：按 64 000 字符截断后实跑展开 `research/big.md` 仍崩溃（`~/Library/Logs/DiagnosticReports/Agents Anywhere-2026-11-24-044134.ips`，递归深度 16301；与 F11 最初 04:15 的 1 MiB 崩溃 16349 是两次）；64 000 字符的短段落约 8000 段 × 2 层嵌套即接近 SwiftUI `Text` 的递归上限（约 16300）。16 000 字符约 2000 段 × 2 = 4000 层，留出安全余量，正常调研报告通常远小于此。
- `SpecRuneDocClamp.swift:8-14` 的 `maxCharacters` 改为 `16_000`，注释同步说明「64 000 对短段落仍会爆栈，实测后收紧」；`SpecRuneDocClampTests.swift` 用例改为 90000 字符截到 16000、恰好 16000 不截断，doc comment 同步；`SpecRuneTasksView.swift:994-998` 注释同步，截断提示经 `SpecRuneDocClamp.maxCharacters` 插值自动显示「正文过大，仅显示前 16000 字符（原始 N 字节）」；`docs/specrune-mobile/README.md:36` 的 64 000/64000 改为 16 000/16000（`shell.exec` 的 64 000 上限不动，测试数仍 41）。
- 验证：`swift test --disable-sandbox` 41 tests / 7 suites 全绿（exit 0）；`swift build --disable-sandbox` Build complete（exit 0）；`xcodebuild build`（`CFFIXED_USER_HOME`/`-packageCachePath`/`-derivedDataPath` 指向 `/tmp`、`OTHER_SWIFT_FLAGS="-disable-sandbox"`、`CODE_SIGN_IDENTITY="-"`）→ BUILD SUCCEEDED（exit 0，未安装，待主会话实跑复验）。
- status: open（待实跑展开 `research/big.md` 确认不再崩溃）。

### 实跑复验（F11 修复后，2026-11-24 05:04）

- 重新构建签名版（`CODE_SIGN_IDENTITY="-"`）安装到 iPhone Duo，导航到归档任务 `11-21-fix-specrune-board-picker-drawer-shift` → 调研 tab。
- 展开 `research/big.md`（1934 KB）：正文显示「大文件调研（research/big.md）」+「截断验证段落」；底部显示「正文过大，仅显示前 16000 字符（原始 1980076 字节）」与「已截断：原始 1980076 字节，仅显示前 1 MiB」；app 未崩溃（无障碍树完整；05:04 无新增崩溃日志，04:41 的崩溃属于 64000 字符旧版）。
- 记录 tab / 调研 tab 其余项与前次一致：4 项按名称升序、KB、默认展开第一项；记录 2 项（会话记录 + record.md 末尾）、meta 行与正文正常。
- 测试数据已清理，归档任务目录恢复原状。

F1 实跑已完成（记录/调研两 tab、展开、默认展开、截断、tab 条件、无空白/错位）；F11 修复后大文件展开不崩溃。两项具备 verified 证据。

## 审查第 3 轮（append-only；第 1/2 轮、实跑与 F11 fix 记录见上，未改动）

审查对象：`git diff` 的全部改动 + 未跟踪新增文件 `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneDocClamp.swift`、`ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/FakeTransport.swift`、`ResearchRecordTests.swift`、`SpecRuneDocClampTests.swift`。本轮为收口轮：逐条复核 F1–F11 的最终状态，再查新问题。

### 验证（独立复跑）

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` → **41 tests / 7 suites 全绿**（exit 0）。
- `cd ios/Packages/SpecRuneKit && swift build --disable-sandbox` → Build complete（exit 0）；仅有 `~/Library/org.swift.swiftpm` 缓存不可写的沙箱警告，不影响构建。
- `xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO`：普通命令 exit 74（`cannot open file '~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/textual.dia' … Operation not permitted`）；workaround（`CFFIXED_USER_HOME` / `-packageCachePath` / `-derivedDataPath` 指向 `/tmp/specrune-r3.*`、`OTHER_SWIFT_FLAGS="-disable-sandbox"`、`CODE_SIGN_IDENTITY="-"`）仍 exit 74（`xcodebuild: error: Could not resolve package dependencies: sandbox-exec: sandbox_apply: Operation not permitted`）。这是 DSH 文件沙箱不允许子进程应用 seatbelt profile，不是代码错误；本轮无法独立复跑 UI 编译，接受主会话 05:04 的 BUILD SUCCEEDED 记录（见 F11 fix 第 2 次）。临时目录都在 `/tmp`，未写入仓库。
- 部分替代：`xcrun swiftc -parse` 解析 `SpecRuneTasksView.swift`、`SpecRuneConnectorTransport.swift`、`SpecRuneDocClamp.swift` → exit 0（只验证语法，未做类型检查）。
- `shasum -a 256 contracts/specrune/1.0/schemas/task-detail.response.schema.json` → `ae061485ce712a45f81b07c829ef5eb3785017b2786aff35fedacf193798ace2`，与 `manifest.json` 一致；5 个 schema 全量核对 `ALL_MATCH`。
- `python3 -m json.tool` 校验 schema 与 manifest → 均合法。
- `git diff --check` → 无空白错误。
- `git status --short connector/ server/ android/ desktop-workbench/ web-next/` → 0 行（空）。
- 归档任务 `11-21-fix-specrune-board-picker-drawer-shift` 目录只剩原始 7 个文件（prd/design/implement/check/review/task.json 与 implement.jsonl），无 `research/`、`research*.md`、`record.md` 测试数据；`find .specrune/tasks -name record.md` 无命中。
- 崩溃日志：`~/Library/Logs/DiagnosticReports` 有 04:01、04:15、04:41 三条 `Agents Anywhere` SIGSEGV（均为 `Text.resolve` 递归爆栈；04:41 为 64000 字符旧版）；05:04 之后无新增，支持 F11 修复后的实跑复验。
- 未做：本轮没有登录态/测试数据，不能自行重跑模拟器 UI；F1/F11 的 UI 证据取自主会话实跑记录。

### 旧 finding 最终状态

- **F1 blocker：verified。** `review.md`「实跑」（04:00–04:18）与「实跑复验」（05:04）已记录 iPhone Duo 模拟器证据：记录 tab 2 项（会话记录 + `record.md` 末尾）、文件名/时间/KB、默认展开第一项、meta 行（title · status · created · branch）与正文、`record.md` 正文、无空白/错位；调研 tab 4 项按名称升序（big.md、research-legacy.md、research.md、topic.md，覆盖根 `research.md`、根 `research-<slug>.md`、`research/` 第一层 `.md` 三来源）、KB、默认展开第一项、topic.md/research.md 正文正常、big.md 两条截断提示；tab 条含概览/PRD/设计/实施/记录/调研/审查；测试数据已清理。对应 AC 第 1/2 条主路径、AC 第 3 条 tab 条件正向路径与 AC 第 5 条实跑要求；AC 第 1/2 条的同名去重、短名兜底、畸形跳过、记录 1 MiB 截断由单测覆盖（`researchDirectoryWins`、`matchesShortName`、`skipsMalformed`、`keepsTruncation`），AC 第 3 条读取失败容错由 `toleratesListFailures` 覆盖数据层。收起路径由切换展开项（展开 topic.md 时 big.md 收起）覆盖；未单独记录「全部收起」动作，但 toggle 逻辑同一函数。无空白/错位描述与证据一致。
- **F2 minor：verified。** `prd.md:46` 已按裁决 B 改为「展开/收起多份文件」，不再写「切换排序」；AC 第 1–4 条与第 5 条其余验收点未降低。
- **F3 minor：verified。** `SpecRuneTasksView.swift:1086` 的截断提示用行内 `bytes` 显示「已截断：原始 \(bytes) 字节，仅显示前 1 MiB」；调研项取 `SpecRuneResearchFile.bytes`、记录项取 `SpecRuneSessionRecord.bytes`、`record.md` 项取 `docs.record.bytes`，无回归。
- **F4 minor：verified。** schema `SessionRecord.at`（第 122 行）注明 DSH 返回 mtime、iOS 用文件名 UTC 时间戳；`contracts/specrune/1.0/README.md:56` 与 `:77` 同步标注客户端差异；`manifest.json` 的 sha256 `ae061485…` 与实际 `shasum` 一致，5 个 schema 全量核对一致。
- **F5 nit：verified。** `SpecRuneClient.swift:406` 的 `recordDate` 在 `Calendar.date(from:)` 后用同一 UTC Calendar 反向核对年/月/日/时/分/秒（`:436-444`），`2026-02-30` / `2026-13-01` 返回空；`ResearchRecordTests.swift:321-355` 覆盖非法日期与闰日 `2024-02-29` 对照用例；41 tests 全绿，合法日期未被误拒。
- **F6 nit：verified。** `SpecRuneTasksView.swift:1048` 的 `accessibilityText` 在 `at` 非空时拼记录时间，`:1079` 的 `accessibilityLabel` 使用它；调研行 `at` 为空，播报内容与原来一致。
- **F7 minor：verified。** `prd.md:52` Deliverables 只补 `size`（`SpecRuneTextFile.size` / `SpecRuneDoc.bytes`）且不改 Connector 的 `fs.readDir` 字段；`:70` Coverage taxonomy 已删「排序开关」；`:72` 改为 Connector `fs.readDir` / `fs.readText` / `shell.exec` 既有端点、不改 Connector/Server。
- **F8 minor：verified。** `docs/specrune-mobile/README.md:56` 写「41 个测试全绿（7 suites，含调研聚合、会话记录解析、详情装配与展开区截断）」，与本轮 `swift test` 实测 41 tests / 7 suites 一致。
- **F9 nit：verified。** `Transport.swift:26` 只保留 `SpecRuneTextFile` 自身说明；协议注释整块移到 `:50-53` 的 `SpecRuneTransport` 声明前，并写明 `shell/exec`、`fs/readText`、`fs/readDir` 三条端点。
- **F10 nit：verified。** `docs/specrune-mobile/README.md:10` 与 `SpecRuneConnectorTransport.swift:6` 均已改为三条端点（`shell/exec`、`fs/readText`、`fs/readDir`）。
- **F11 blocker：verified。** `SpecRuneDocClamp.maxCharacters = 16_000`（`SpecRuneDocClamp.swift:14`）；`SpecRuneDocMarkdown` 只用于调研展开区（`SpecRuneTasksView.swift:670`）与记录展开区（`:697`）；`ChatMarkdownView` 通用组件与其它文档 tab 的 `docBody` 未改；两条提示并存（clamp 提示 `:1010`、1 MiB 提示 `:1086`）。`SpecRuneDocClampTests.swift` 覆盖短文本/超长截到 16000/空文本/恰好阈值四个用例；`swift test` 41 tests / 7 suites 全绿；`docs/specrune-mobile/README.md:36` 的 16000 说明与实现一致。主会话 05:04 实跑复验：展开 `research/big.md`（1934 KB）显示正文与两条提示，app 未崩溃；崩溃日志 05:04 之后无新增（04:41 的 64000 字符旧版崩溃在修复前）。证据充分，F11 收口。

### 新 findings

#### F12 minor docs/specrune-mobile/README.md:60

- evidence: 「验证状态」仍写「**未做**：真机 / iPhone Duo 模拟器实跑（含「调研」「记录」清单的展开与截断提示）」；但 `review.md` 的「实跑」（04:00–04:18）与「实跑复验」（05:04）已记录 iPhone Duo 模拟器上的调研/记录清单实跑，F1/F11 均据此 verified。该句的「未做」已过期；同句后半「折叠态、竖向 toolbar 摆放」仍可能未复核。
- status: deferred（reason: 本轮只写 review.md，不改文档；属文档同步，建议主会话在归档前把「未做」改为已完成的实跑说明，并保留仍未复核的折叠态/toolbar 项；不影响代码行为与 AC 验收）。

#### F13 minor ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:581,883

- evidence: `docBody`（PRD/设计/实施/审查）与 `specRow`（规范展开）仍直接把 `doc.content` / `file.content`（最多 1 MiB）交给 `ChatMarkdownView`，没有经过 `SpecRuneDocClamp`。F11 的崩溃根因是 1 MiB / 大量短段落触发 SwiftUI `Text.resolve` 递归爆栈（04:01、04:15 日志），这两条路径与调研/记录展开区同形；本次实跑的 PRD/设计/实施/审查与规范正文都较小，未触发。属既有路径，不在本任务 AC 的调研/记录范围内。
- status: deferred（reason: 既有路径、非本任务引入；本次实跑未触发；建议后续统一用 `SpecRuneDocMarkdown` 或同等字符数保护，避免同类大文档崩溃）。

#### F14 minor ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1010,1086

- evidence: 超过 1 MiB 的调研/记录正文会同时显示两条提示：`:1010` 的「正文过大，仅显示前 16000 字符（原始 N 字节）」与 `:1086` 的「已截断：原始 N 字节，仅显示前 1 MiB」。UI 实际只显示前 16000 字符，第二条「仅显示前 1 MiB」对用户是误导（1 MiB 是 Connector 的读取上限，不是当前展示上限）；「实跑复验」记录 big.md 两条提示同时出现。
- status: deferred（reason: 文案级问题，不影响崩溃修复与 AC 验收；本轮不改 UI。建议主会话把第二条改为「原文超过 1 MiB，仅读取前 1 MiB」或在 clamp 时隐藏第二条，避免两条上限互相矛盾）。

#### F15 nit .specrune/spec/ios/markdown-rendering.md:19-32,61

- evidence: 规范只写了非流式全文的 `ChatMarkdownView(blockSpacing: 0, reservesStreamingHeight: false)` 调用形状与实跑验证，没有记录 F11 的新教训：1 MiB / 大量短段落会让 `Text.resolve` 递归爆栈，清单展开区需先按字符数 clamp。该教训目前只在代码注释、`review.md` 与 `docs/specrune-mobile/README.md` 中，后续会话读规范时可能重新引入同类崩溃。
- status: deferred（reason: 本轮只写 review.md，不改规格；建议主会话用 specrune-update-spec 把「大文本渲染需 clamp」补进 `ios/markdown-rendering.md`，或在后续任务跟进）。

### 新 blocker/major 排查

- 未发现新的 blocker/major：调研聚合（三来源、大小写不敏感、同名 `research/` 优先、文件名升序、单文件失败跳过）符合 Requirements 1/4；记录解析（frontmatter 匹配、短名兜底、畸形跳过、CRLF、meta 空值省略、文件名 UTC 转本地、按文件名倒序、每批 6 并发）符合 Requirements 2/5；详情装配与 tab 条件符合 Requirements 3/6；非流式 Markdown 参数正确；契约 schema/manifest/README 三者一致；`connector/`、`server/`、`android/`、`desktop-workbench/`、`web-next/` 无改动。
- `CHANGELOG.md:37` 的未发布 iOS 条目描述了用户可感知结果（任务详情新增「调研」「记录」两个维度、清单、展开正文/大小/截断提示），符合 CHANGELOG 写法；PR 链接待开 PR 后补，与同节相邻条目一致。
- `docs/specrune-mobile/README.md` 的测试数（41/7 suites）与取数说明（`fs.readDir`/`fs.readText`、逐个文件读取、1 MiB 截断、16000 字符 clamp）与本轮实测一致；仅「验证状态」的「未做」句过期（F12）。
- `review.md` 前文未改动，本轮只在末尾追加；格式为 finding id / severity / file:line / evidence / status。

### Candidate

Candidate: green（F1–F11 全部 verified；新 F12–F15 为 minor/nit，已按 workflow 允许的方式 deferred 并写明理由；本轮只写 review.md，未改代码/规格/任务产物。）

Verdict: green
