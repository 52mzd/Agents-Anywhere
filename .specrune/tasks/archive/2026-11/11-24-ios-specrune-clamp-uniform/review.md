# Review 第 1 轮

审查基线：2026-11-24 12:20:29 的 `ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift`（审查期间该文件在 12:07:55、12:20:29 被修改两次；本轮 finding 以 12:20:29 版本为准）。其余文件未在审查期间变化。

独立复跑：

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` → 54 tests / 8 suites 全绿（exit 0）。
- `cd ios/Packages/SpecRuneKit && swift build --disable-sandbox` → Build complete（exit 0）。
- `cd "ios/Agents Anywhere" && xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**（exit 0；构建的是 12:07:55 版本，12:20:29 新增 `ScrollView`/`frame(height:)` 后未重新构建）。
- `git diff --check` → exit 0。
- `git status --short connector/ server/ android/ desktop-workbench/ web-next/` → 空。

## F1 major ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1007-1016

evidence: `SpecRuneChunkedMarkdown` 当前用 `ScrollView { LazyVStack { ... } }.frame(height: 480)`，在任务详情页已有的 `ScrollView` 内再嵌套一层滚动容器。这与设计/实施约束直接冲突：`design.md:40` 写「外层已有 `ScrollView` 时只替换内部渲染，不嵌套滚动容器」，`implement.md:20` 同；`.specrune/spec/ios/specrune-board.md:59` 已把「外层详情页已有 `ScrollView`，容器内不再嵌套滚动」写成契约。代码注释也仍写着「容器内不再嵌套滚动」（同文件 581、995 行），与实现相反。审查清单第 2 条明确要求核对「docBody/specRow 是否避免嵌套 ScrollView」。垂直嵌套滚动会拦截手势：用户在正文内层滚动到底前无法继续滚动外层详情页，且短文档也被包进内层滚动区。

status: open

- fix: 不适用——基线更新（12:44:51）已把 F1 标记 superseded：`ScrollView` 与 `.frame(height:)` 已从 `SpecRuneChunkedMarkdown` 移除。

## F2 major ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1016

evidence: `.frame(height: 480)` 给所有文档正文强制 480 高度：82 字节的记录正文、短 PRD 也会占满 480 高度并留下大块空白；长文档则退化为内层 480 高度滚动。AC 第 2 条只要求 `LazyVStack` 懒加载与非流式参数不变，没有固定高度要求；`design.md:29-40` 的容器片段也没有 `frame`。这一改动同时改变了 `docBody`/`specRow` 原有的整页滚动行为，而 docs 第 61 行说明分块改动后的实跑复验尚未完成，短文档留白与嵌套滚动手感均未验证。

status: open

- fix: 不适用——基线更新（12:44:51）已把 F2 标记 superseded：`.frame(height: 480)` 已移除。

## F3 major ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1017-1023

evidence: `.task(id: text)` 在 `text` 变化时取消旧任务，但 `Task.detached { SpecRuneDocChunks.split(text) }` 不响应取消；旧闭包在 `await .value` 返回后仍会执行 `chunked = Chunked(text: text, chunks: chunks)`（闭包捕获的是旧 `text`）。若旧任务（大文档切分，注释称 Debug 下需数百毫秒）在新任务（小文档）之后完成，`chunked.text` 被写回旧值，body 的 `if chunked.text == text` 守卫失败，所有块都不渲染；`.task(id:)` 不会因同一 id 再次触发，正文会永久空白。触发路径正是 spec 验证清单要求的「按块数减少的方向再切一次（长文档 → 短文档），确认正文跟着换」（`.specrune/spec/ios/markdown-rendering.md:85-87`），也是 CHANGELOG 已记录过的「切换产物标签后正文不更新」同类回归。需要在赋值前检查取消/当前 `text`，或在取消时终止旧切分。

status: open

- fix: 本轮未改——`SpecRuneTasksView.swift:1029-1036` 的 `.task(id:)` 竞态仍在；本轮只处理块大小、初始块数、自动追加与注释/文档同步，留待下一轮。

## F4 minor ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/SpecRuneDocChunksTests.swift:67-109

evidence: AC 第 1 条与审查清单第 1 条要求「```/~~~ 围栏不被切断」。实现 `SpecRuneDocChunks.fenceMarker` 同时支持 `~`（SpecRuneDocChunks.swift:157），但测试只覆盖 ```：`keepsCodeFenceWhole`、`ignoresFenceLikeLinesInsideFence`、`splitsOversizedFenceAtHardLimit` 都没有 `~~~` 开围栏/闭合围栏，也没有 `~~~` 围栏内 ``` 行的用例。「闭合只能空白」由 `ignoresFenceLikeLinesInsideFence` 覆盖，`~~~` 路径无断言。

status: open

- fix: 本轮未改——`ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/SpecRuneDocChunksTests.swift:67-109` 未新增 `~~~` 用例。

## F5 minor ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneDocClamp.swift:12-27

evidence: `SpecRuneDocClamp.clamp` 现在只在 `SpecRuneDocClampTests` 中被调用；`SpecRuneTasksView` 已无调用（`SpecRuneDocMarkdown` 被删除），`SpecRuneDocChunks` 只引用 `SpecRuneDocClamp.maxCharacters`。注释声称「保留作兜底（未接入分块的路径或切分失败时）」，但 `SpecRuneDocChunks.split` 不抛错、不返回 nil，所有文档路径都已接入分块，这个兜底状态不可达。审查清单第 6 条要求核对「SpecRuneDocClamp 是否仅保留兜底且无死引用」；若保留，应说明它只是 API 兼容/测试基线，或删除 `clamp` 只保留 `maxCharacters`。

status: open

- fix: 本轮未改——`ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneDocClamp.swift:12-27` 仍保留 `clamp`。

## F6 minor ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1047-1073

evidence: 每个可见块先由 `SpecRuneMarkdownProbe.fails` 在 `Task.detached(priority: .utility)` 完整解析一遍，随后 `ChatMarkdownView` 再解析一遍（注释自己承认「可视块因此会被解析两遍」）。1.9 MB 文档滚动时可见块反复双解析，AC 第 4 条要求滚动到底的性能，`design.md:60` 只评估了「滚动时逐块解析」，没有双解析成本。注释还称「块离开可视区时取消试解析，解析器会在检查点响应取消」，但 Textual 的 `AttributedStringMarkdownParser.parse` 是否检查 `Task.isCancelled` 没有证据；若不检查，滚出视区的 probe 仍会跑完。

status: open

- fix: 部分——`SpecRuneTasksView.swift:1069-1071` 注释改为「已加载的块会被解析两遍」，去掉「块只在进入可视区时才做」与「解析器会在检查点响应取消」的断言；双解析成本本身未改。

## F7 minor CHANGELOG.md:37

evidence: 未发布 iOS 条目写成「大文件正文改为分块按需加载，可以完整滚动查看，不再只显示前 16000 字符。PRD、设计、实施、审查与规范正文同样分块加载，大文件可以完整滚动查看。」——「分块按需加载」「分块加载」是实现方式，项目 AGENTS.md 的更新日志规则要求「不写实现方式」；「大文件可以完整滚动查看」在同一句重复两次。建议合并为一条用户可感知的结果。

status: open

- fix: `CHANGELOG.md:37`——合并为一句用户可感知描述（「大文件正文不再只显示前 16000 字符，全部内容都能滚动查看，PRD、设计、实施、审查与规范正文同样完整显示」），去掉「分块按需加载」等实现用语与重复的「完整滚动查看」。

## F8 nit .specrune/tasks/11-24-ios-specrune-clamp-uniform/task.json:4-5

evidence: `title` 仍是「统一 SpecRune 文档渲染的 clamp 与提示文案」，`description` 仍是「统一走 16000 字符 clamp」，与已改为分块懒加载的 `prd.md`、`design.md`、`implement.md` 不一致。任务产物应描述最终方案。

status: open

- fix: 本轮未改——`task.json:4-5` 的 title/description 仍描述 clamp；按指示本轮只同步 `prd.md`/`design.md`/`implement.md`。

## F9 nit .specrune/tasks/archive/2026-11/11-21-fix-specrune-board-picker-drawer-shift/research/big.md

evidence: 实跑夹具 `research/big.md`（2,070,087 字节）、`research.md`、`research/topic.md` 仍以未跟踪状态留在归档任务目录；`implement.md:35` 要求实跑后「清理夹具」。若主会话还要用它做 1.9 MB 实跑，收尾前应删除，避免进入提交。

status: open

- fix: 本轮未改——`research/big.md` 等夹具按主会话指示保留、未清理；它们仍是未跟踪文件，收尾前由主会话决定是否删除。

## F10 nit ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneDocChunks.swift:10-11

evidence: 切分只跟踪 ```/~~~ 围栏，表格与列表在行尾切点会被拆到两块：第二块表格缺少表头、有序列表可能重新编号。`design.md:59` 把「表格跨空行切分会断；必要时在表格行内不切（实现时按行判断）」列为风险，实现未处理。AC 第 1 条没有要求表格，故只记 nit，需在 1.9 MB 实跑时观察调研/PRD 中的表格与列表。

status: open

- fix: 本轮未改——`SpecRuneDocChunks.swift:10-11` 未处理表格/列表切点。

## F11 nit ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1059-1073

evidence: AC 第 3 条说「单块渲染异常时给兜底提示」；`SpecRuneMarkdownProbe` 只捕获 `AttributedStringMarkdownParser.parse` 的 throw。本次 SIGSEGV 属于 SwiftUI 渲染崩溃，无法被捕获，兜底文案「这一段渲染失败」的实际覆盖范围比字面窄；建议文案或注释限定为「解析失败」。

status: open

- fix: 本轮未改——`SpecRuneTasksView.swift:1050` 兜底文案仍为「这一段渲染失败」；probe 注释已在 `:1069-1071` 改为「已加载的块会被解析两遍」。

Candidate: red

---

## 基线更新（2026-11-24 12:44:51，追加）

审查期间 `SpecRuneTasksView.swift` 在 12:44:51 再次变化：F1（嵌套 `ScrollView`）与 F2（`.frame(height: 480)`）针对的代码已被移除，标记 **superseded**；当前 `SpecRuneChunkedMarkdown` 改为 `VStack` + `prefix(visibleChunks)`（初始 3 块）+「加载更多」按钮（每次 +3 块）。以下 findings 以 12:44:51 版本为准；F3（`.task(id:)` 竞态，行号更新为 1027-1034）与 F4-F11 在新版本仍成立。`swift test`/`swift build` 复跑对应 SpecRuneKit（11:21 版本，未变）仍有效；`xcodebuild` 复跑成功但构建的是 12:07 版本，12:20/12:44 版本未经独立构建。

## F12 blocker ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1001-1021

evidence: 当前实现用 `VStack` + `chunked.chunks.prefix(visibleChunks)`（初始 3 块）+「加载更多（剩余 N 块）」按钮，每次 `visibleChunks += 3`。这正是 `prd.md:44` 列为 Out of Scope 的「分页「加载更多」交互」，也是 `design.md:71` 已否决的备选方案 B（「能看全但操作繁琐，不做」）。同时 AC 第 2 条要求 `LazyVStack` 懒加载，当前是 `VStack`；`VStack` 中已加载的块全部创建并解析，不满足「块只在进入可视区时解析」。注释 999-1000 行承认「LazyVStack 在本详情页的嵌套滚动上下文里不渲染，改为显式分批」，但这是实跑发现，尚未更新设计/规格或重新裁决方案，直接用被否决的 B 方案落地。1.9 MB 正文约 130 块，需要点 40 多次「加载更多」才能看完，与 AC 第 3 条「正文可滚动到底」不符。

status: open

- fix: 方案与 AC 已按实测重裁决：`prd.md:28` AC 第 2 条改为「`VStack` + 分批自动追加（哨兵触发），`LazyVStack` 实测不渲染」；`design.md:43,63,75` 记录实测原因并选 A 方案（VStack + 哨兵自动追加，不做「加载更多」）；`implement.md:18-19` 同步。代码已无「加载更多」按钮。

## F13 major ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1012-1021

evidence: AC 第 3 条要求 1.9 MB 夹具展开后「正文可滚动到底」；当前只渲染前 3 块，其余必须逐次点「加载更多」追加 3 块。用户不点就永远看不到后续内容，滚动到底无法到达全文；这与「全部显示」的目标和 docs/CHANGELOG/spec 的「全部内容可连续滚动查看」声明矛盾。加载更多是显式分页，不是连续滚动。

status: open

- fix: `SpecRuneTasksView.swift:1004` 初始 1 块、`:1018-1025` 哨兵每次自动追加 1 块（无按钮），滚动到已渲染块末尾即加载下一块；文档表述同步（见 F14）。

## F14 major docs/specrune-mobile/README.md:36, .specrune/spec/ios/markdown-rendering.md:44-46, .specrune/spec/ios/specrune-board.md:59, CHANGELOG.md:37

evidence: 这些文档仍声称「`LazyVStack` + 每块独立 ChatMarkdownView」「全部内容可连续滚动查看」「全文可连续滚动查看」「容器内不再嵌套滚动」。当前实现是 `VStack` + 加载更多，不是 LazyVStack，也不是连续滚动。AC 第 5 条要求 ios spec 与 docs 同步，当前文档描述的是 12:20 之前的 LazyVStack 版本，与最终代码不一致。

status: open

- fix: 文档已同步为「VStack + 分批自动追加」：`docs/specrune-mobile/README.md:36`、`.specrune/spec/ios/specrune-board.md:59`、`.specrune/spec/ios/markdown-rendering.md:41-48`、`CHANGELOG.md:37`、`.specrune/spec/ios/index.md:38`；并补实测原因「`LazyVStack` 在嵌套滚动上下文不渲染（2026-11-24 实跑）」。

## F15 minor ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:993-1000

evidence: 容器文档注释仍写「`LazyVStack` 只在块进入可视区时才创建并解析」（993 行），与实现的 `VStack` 不符；999-1000 行的新注释才说明改为显式分批。同一类型里两条注释互相矛盾，`995` 行「容器内不再嵌套滚动」现在成立但 993 行已失效。

status: open

- fix: `SpecRuneTasksView.swift:990-1000` 容器注释改为「`VStack` + 显式分批 + 哨兵自动追加」，明确「`LazyVStack` 在本详情页嵌套滚动上下文不渲染（2026-11-24 实跑）」；`:1002-1004` 状态注释同步；`:576`、`:580-581` 去掉「懒加载」「块只在进入可视区时解析」表述。

## F16 nit ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1015-1021

evidence: 「加载更多」按钮无分页记忆：`.task(id: text)` 完成时 `visibleChunks = 3`，切换文档/重新展开后回到前 3 块，用户已加载的进度丢失。若保留加载更多方案需要产品决策，但方案本身已被 F12 判定为越界。

status: open

- fix: 不适用——「加载更多」按钮已移除，改为哨兵自动追加；`visibleChunks` 在正文变化时重置为 1，不需要分页记忆。

---

## 基线更新（2026-11-24 13:11:52，追加）

`SpecRuneTasksView.swift` 在 13:11:52 再次变化：F12 描述的「加载更多」按钮已移除，改为 `VStack` + `prefix(visibleChunks)`（初始 2 块）+ `Color.clear` 哨兵 `onScrollVisibilityChange` 自动追加（每次 +2 块）；切分改为 `SpecRuneDocChunks.split(text, maxCharacters: 4_000)`。F13（必须点击才能看全）不再成立（自动追加，理论上可滚动到底，但需实跑验证）；F16（分页记忆）缓解。F12 仍成立：仍是 `VStack` + 显式分批，不是 AC 第 2 条要求的 `LazyVStack`，注释承认「LazyVStack ... 不渲染」但设计/规格未更新。F14/F15 仍成立。新增：

## F17 major ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1026-1033

evidence: `.task` 调用 `SpecRuneDocChunks.split(text, maxCharacters: 4_000)`，UI 把每块上限从默认 16 000 降到 4 000。AC 第 1 条写「每块 ≤16000」（4 000 仍满足上限），但 `.specrune/spec/ios/specrune-board.md:59` 与 `.specrune/spec/ios/markdown-rendering.md:44-46` 写「默认每块 16 000 字符」，未说明 UI 覆盖为 4 000。1.9 MB 正文约 500 块，哨兵每次只追加 2 块，滚动到底需要触发约 250 次追加，AC 第 4 条「滚动到底」的滚动稳定性与性能需实跑验证，当前无证据。

status: open

- fix: `SpecRuneTasksView.swift:1032` 改回 `SpecRuneDocChunks.split(text)`（默认 16 000，不覆盖）；`:1004` 初始 `visibleChunks = 1`、`:1024` 哨兵每次 +1（1 MiB ≈ 60 块）；滚动稳定性仍由主会话实跑验证。

## F18 minor ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1015-1023

evidence: 哨兵用 `Color.clear.frame(height: 1).onScrollVisibilityChange(threshold: 0.01)`（iOS 18+ API，部署目标 26.3 可用）。它依赖外层任务详情页 `ScrollView` 的可见性：容器初始渲染时若前 2 块不足一屏，哨兵可见会连续追加直到填满或全部加载；记录展开区有多个折叠项时，屏幕外的哨兵不会触发，符合预期。但自动追加的触发频率、追加时滚动位置是否跳动需实跑确认。

status: open

- fix: 哨兵保留在 `SpecRuneTasksView.swift:1018-1025`；触发频率与滚动位置跳动由主会话实跑确认（本轮未安装/实跑）。

Candidate: red

---

## 验证更新（2026-11-24 13:37，追加）

`xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**（exit 0），构建的是 13:11:52 版本；`SpecRuneTasksView.swift` 自 13:11:52 未再变化。`swift test --disable-sandbox` 复跑仍为 54 tests / 8 suites 全绿（SpecRuneKit 文件 11:21 后未变）。本轮未改任何代码/规格/任务产物，只写 `review.md`；未 commit/push。

Candidate: red

---

## Review 第 2 轮（2026-11-24 19:27，最终方案：VStack + 「显示更多」）

审查基线：当前工作区（`feat/ios/specrune-research-record`，16 项未提交改动）。代码以 `ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1001-1047` 的 `SpecRuneChunkedMarkdown` 为准；文档以当前工作区为准。

独立复跑：

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` → **54 tests / 8 suites 全绿**（exit 0）。
- `cd ios/Packages/SpecRuneKit && swift build --disable-sandbox` → **Build complete**（exit 0）。
- `cd "ios/Agents Anywhere" && xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**（exit 0），构建的是当前工作区版本。
- `git diff --check` → exit 0。
- `git status --short connector/ server/ android/ desktop-workbench/ web-next/` → 空。

真机验收采用主会话证据（用户确认「正常了，验收通过」：1 KB 文件立即显示；2022 KB 夹具显示第一段 + 「显示更多」，不卡死/闪退；长→短切换不空白），本轮未重复安装。代码核对：`SpecRuneChunkedMarkdown` 为 `VStack` + `prefix(visibleChunks)` + 「显示更多（剩余 N 段）」（`:1013-1035`），初始 1 段（`:1005`）、每次 +1（`:1025`）；`ChatMarkdownView(text:blockSpacing:0,reservesStreamingHeight:false)`（`:1017-1021`）；四处接入完整（`docBody` `:582`、调研 `:669`、记录 `:696`、`specRow` `:881`），SpecRune 视图中再无直接调用 `ChatMarkdownView` 的正文路径；`Task.isCancelled` 守卫在 `:1042`。`ChatMarkdownView` 零改动（无 diff、无 status）。

### 旧 findings 结论

- **F1 superseded**——基线更新已移除 `ScrollView`/`.frame(height:)`；当前容器无嵌套滚动（`SpecRuneTasksView.swift:1013-1035`）。
- **F2 superseded**——`.frame(height: 480)` 已移除，正文高度自适应。
- **F3 verified**——`.task(id: text)`（`:1036-1045`）在 `await Task.detached` 之后 `guard !Task.isCancelled`（`:1042`）才写回 `chunked` 与 `visibleChunks = 1`，旧切分不会再覆盖新正文；长→短切换已由真机验收确认。
- **F4 仍 open（minor）**——`SpecRuneDocChunksTests.swift:67-109` 仍只有 ``` 用例，无 `~~~` 开/闭围栏或围栏内 ``` 的断言；实现支持 `~`（`SpecRuneDocChunks.swift:157`）。
- **F5 仍 open（minor）**——非测试代码对 `SpecRuneDocClamp.clamp` 零调用（grep 仅命中 `SpecRuneDocClampTests`）；`SpecRuneDocClamp.swift:12-13` 仍称「保留作兜底（未接入分块的路径或切分失败时）」，但所有路径已接入且 `split` 不失败，兜底状态不可达。
- **F6 verified**——`SpecRuneMarkdownProbe` 已删除（`grep Probe ios/` 只剩无关的 `ViewModelLifetimeProbe` 等），不再有每块双解析。
- **F7 verified**——`CHANGELOG.md:37` 已改为用户可感知描述：「正文较长时分段显示，点「显示更多」继续看后面的内容，不再只显示前 16000 字符」，无实现用语与重复。
- **F8 仍 open（nit）**——`task.json:4-5` 的 title/description 仍写「clamp 与提示文案」「统一走 16000 字符 clamp」。
- **F9 verified**——归档任务 `11-21-fix-specrune-board-picker-drawer-shift` 只剩 7 个原始文件（check.jsonl/design.md/implement.jsonl/implement.md/prd.md/review.md/task.json），`research/`、`research.md`、`big.md` 已清理。
- **F10 仍 open（nit）**——`SpecRuneDocChunks.swift` 仍只跟踪围栏，表格/列表切点未处理；`design.md:64` 仍列为风险。
- **F11 verified**——probe 删除后「兜底文案覆盖范围窄」的对象已不存在；兜底提示本身缺失另记 F19。
- **F12 verified（按现状）**——AC 第 2 条（`prd.md:28`）已重裁决为「`VStack` + 「显示更多」显式追加，`LazyVStack` 实测不渲染」，代码 `:1013-1033` 符合；原「用被否决的 B 方案越界」不再成立。残留的文档自相矛盾见 F20。1.9 MB ≈ 130 段，点「显示更多」约 129 次才能看全，属用户已验收的交互。
- **F13 仍 open（minor）**——「连续滚动」的文档矛盾已消除，但 AC 第 3 条（`prd.md:29`）仍写「1.9 MB 夹具展开后…正文可滚动到底」，与「初始 1 段、需点按钮」字面不符；真机验收接受按钮交互。
- **F14 仍 open（部分，minor）**——主段落已改为「`VStack` + 分段渲染 + 显示更多」（`README.md:36`、`specrune-board.md:59`、`markdown-rendering.md:44-50`、`CHANGELOG.md:37`）；仍残留旧「自动追加/自动加载」：`index.md:38`「分批自动追加」、`markdown-rendering.md:90`「滚动到末尾自动加载后续块」、`specrune-board.md:70`「交给自动追加容器」、`README.md:61`「分块自动追加改动后的实跑复验由主会话执行」。
- **F15 仍 open（部分，minor）**——容器注释 `:990-1000` 已改好；`:581` 仍写「滚动到已渲染块末尾时自动追加下一块」，`SpecRuneDocClamp.swift:12` 仍写「分块懒加载」，与按钮方案不符。
- **F16 verified（不适用）**——`visibleChunks` 在 `.task(id: text)` 完成时重置为 1（`:1044`），切换文档从第 1 段开始，符合预期。
- **F17 verified**——`:1039` 用 `SpecRuneDocChunks.split(requested)` 默认 16 000，无 4 000 覆盖；与 spec 一致。
- **F18 verified（不适用）**——哨兵 `Color.clear` + `onScrollVisibilityChange` 已随最终方案移除。

### 新 findings

## F19 major ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift:1001-1047

evidence: 单块解析失败的兜底提示在最终方案里被静默删除。`prd.md:21` Requirements 3 明确要求「单块渲染异常时给兜底提示」，`design.md:46`、`specrune-board.md:62`、`docs/specrune-mobile/README.md:37` 都声称「单块解析失败时该块退回纯文本并提示「这一段渲染失败，其余内容不受影响」」。实际代码中 `SpecRuneMarkdownProbe` 与「这一段渲染失败」文案已全删（`grep -rn "渲染失败\|Probe" ios/` 零命中），`SpecRuneChunkedMarkdown`（`:1013-1035`）只渲染 `ChatMarkdownView`；而 `ChatMarkdownView.swift:58` 解析失败时 `guard case .success(let parsed) = result else { return }`，该块保持空数组、静默空白，既没有退回纯文本也没有提示。用户无法区分「空正文」与「渲染失败」，文档与规格描述的是不存在的行为。

status: open

## F20 minor .specrune/tasks/11-24-ios-specrune-clamp-uniform/prd.md:44, design.md:65-67, design.md:76, implement.md:36, implement.md:50

evidence: 任务产物内部仍保留旧方案（哨兵自动追加 / 不做「加载更多」）的表述，与最终「显示更多」按钮矛盾。`prd.md:44` 的 Out of Scope 仍列「分页「加载更多」交互」，而 AC 第 2 条（`prd.md:28`）要求「显示更多」按钮；`design.md:67` 仍写「不做分页「加载更多」按钮；滚动到已渲染块末尾自动追加」，`design.md:76` 备选 B 仍写「不做」，但最终 A 方案就是按钮；`design.md:65` 写「滚动到末尾逐块追加解析」；`implement.md:36` 写「滚动到已渲染块末尾会自动加载下一块」，`implement.md:50` 写「自动追加保持初始 1 块、每次 +1」。后续会话按这些产物会误以为存在自动追加、或以为按钮被否决。

status: open

本轮只写 `review.md`，未改代码/规格/任务产物；未 commit/push。F19 需代码与文档二选一：补回兜底提示（并在 probe 已删除的前提下用可捕获的解析失败判定），或从 PRD/design/spec/README 删掉该承诺；F20 与 F13/F14/F15 的措辞统一属于同一批文档收口，建议交给主会话的 fix pass。

Candidate: red

---

## Review 第 3 轮（2026-11-24 19:58，收口轮）

审查基线：当前工作区（`feat/ios/specrune-research-record`，16 项未提交改动）。代码以 `SpecRuneTasksView.swift:1001-1047` 的 `SpecRuneChunkedMarkdown` 为准；文档与任务产物以当前工作区为准。最终方案为「`VStack` + `prefix(visibleChunks)` + 「显示更多（剩余 N 段）」按钮，初始 1 段、每次 +1」，用户已真机验收通过（「正常了，验收通过」）。

独立复跑（本轮全部 exit 0）：

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` → **54 tests / 8 suites 全绿**。
- `cd ios/Packages/SpecRuneKit && swift build --disable-sandbox` → **Build complete**。
- `cd "ios/Agents Anywhere" && xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**（`CODE_SIGNING_ALLOWED=NO` 只用于编译验证；模拟器实跑签名证据沿用 README 的 `CODE_SIGN_IDENTITY="-"` 与主会话真机验收）。
- `git diff --check` → exit 0。
- `git status --short connector/ server/ android/ desktop-workbench/ web-next/` → 空。

代码核对（逐项符合最终方案）：

- 容器：`VStack` + `ForEach(chunked.chunks.prefix(visibleChunks).indices)` + 「显示更多（剩余 N 段）」按钮（`:1013-1035`），无 `ScrollView`/`frame`/`LazyVStack`/哨兵。
- 初始 1 段（`:1005`），每次 +1（`:1025`），按钮在末段后消失（`:1023`）。
- `.task(id: text)`（`:1036-1045`）在 `await Task.detached` 之后 `guard !Task.isCancelled`（`:1042`）才写回 `chunked` 与 `visibleChunks = 1`。
- 四处接入完整：`docBody` `:582`、调研展开 `:669`、记录展开 `:696-698`、`specRow` `:881`；SpecRune 视图内只有容器内一处 `ChatMarkdownView(`（`:1017`）。
- 非流式参数 `blockSpacing: 0, reservesStreamingHeight: false`（`:1017-1021`）。
- 无死引用：`grep` `SpecRuneMarkdownProbe` / `SpecRuneDocMarkdown` / `SpecRuneDocChunk`（单数）零命中。
- `ChatMarkdownView` 零改动（`git status`/`git diff` 均无）。
- 归档任务 `11-21-fix-specrune-board-picker-drawer-shift` 只剩 7 个原始文件，`research/`、`research.md`、`big.md` 已清理。

### 旧 findings 结论

第 1 轮：

- **F1 verified（superseded）**——`SpecRuneChunkedMarkdown` 已无 `ScrollView`/`.frame(height:)`，容器内不再嵌套滚动（`:1013-1035`）。
- **F2 verified（superseded）**——`.frame(height: 480)` 已移除，正文高度自适应。
- **F3 verified**——`.task(id:)`（`:1036-1045`）在 `await` 后先 `guard !Task.isCancelled`（`:1042`）再写回；旧切分不会覆盖新正文，长→短切换已由真机验收确认。
- **F4 仍 open（minor，deferred）**——`SpecRuneDocChunksTests.swift:67-109` 仍只有 ``` 用例，无 `~~~` 开/闭围栏或围栏内 ``` 的断言；实现支持 `~`（`SpecRuneDocChunks.swift:157`）。deferred 理由：`~` 与 `` ` `` 共用同一 `fenceMarker` 分支，无独立逻辑，补一个用例即可，不阻塞收口。
- **F5 仍 open（minor，deferred）**——非测试代码对 `SpecRuneDocClamp.clamp` 零调用（grep 仅命中 `SpecRuneDocClampTests`）；`SpecRuneDocClamp.swift:12-13` 仍称「保留作兜底（未接入分块的路径或切分失败时）」，但所有路径已接入且 `split` 不失败，兜底状态不可达。deferred 理由：保留 `clamp` 不影响行为，spec 也写「保留作兜底」；后续可只留 `maxCharacters`。
- **F6 verified**——`SpecRuneMarkdownProbe` 已删除，无每块双解析。
- **F7 verified**——`CHANGELOG.md:37` 为用户可感知描述：「正文较长时分段显示，点「显示更多」继续看后面的内容，不再只显示前 16000 字符；PRD、设计、实施、审查与规范正文同样适用」，无实现用语。
- **F8 仍 open（nit，deferred）**——`task.json:4-5` 的 title/description 仍写「clamp 与提示文案」「统一走 16000 字符 clamp」；deferred 理由：任务元数据不影响行为，建议主会话 fix pass 顺手改成最终方案。
- **F9 verified**——归档夹具已清理（见上）。
- **F10 仍 open（nit，deferred）**——`SpecRuneDocChunks.swift` 仍只跟踪围栏，表格/列表切点未处理；`design.md:64` 仍列为风险。deferred 理由：真实调研文件平均 8.3 KB、最大 29.7 KB，绝大多数一段看完；表格跨块需正文超过 16 000 字符才触发。
- **F11 verified**——probe 删除后「兜底文案覆盖范围窄」的对象不存在。
- **F12 verified**——AC 第 2 条（`prd.md:28`）为「`VStack` + 「显示更多」显式追加，`LazyVStack` 实测不渲染」，代码 `:1013-1035` 符合；`SpecRuneDocChunks.split(requested)` 默认 16 000，无覆盖。
- **F13 verified**——`prd.md:29` 已改为「首段立即显示、点「显示更多」可逐段看完全部内容」，不再要求「正文可滚动到底」；spec 验证段残留另记 F21。
- **F14 verified**——旧「自动追加/自动加载」已清：`index.md:38`「「显示更多」逐段追加」、`markdown-rendering.md:90`「点「显示更多」能逐段看完全文」、`specrune-board.md:70`「交给「显示更多」容器」、`docs/specrune-mobile/README.md:61`「长正文点「显示更多」逐段查看亦经真机验收」；grep「自动追加/自动加载/哨兵/加载更多/连续滚动」在 spec/docs/代码注释中零命中（唯一「懒加载」残留见 F15）。
- **F15 仍 open（nit）**——`:581` 已改为「长正文靠「显示更多」逐段追加」；`SpecRuneDocClamp.swift:12` 仍写「分块懒加载」，与按钮方案不符，建议改「分块渲染」。
- **F16 verified（不适用）**——无「加载更多」分页按钮，`visibleChunks` 在 `.task` 完成时重置为 1（`:1044`），切换文档从第 1 段开始。
- **F17 verified**——`SpecRuneDocChunks.split(requested)`（`:1039`）用默认 16 000，无 4 000 覆盖，与 spec 一致。
- **F18 verified（不适用）**——哨兵 `Color.clear` + `onScrollVisibilityChange` 已随最终方案移除。

第 2 轮：

- **F19 仍 open（降为 minor）**——代码与 spec/docs 已如实描述「静默空白」：`specrune-board.md:62`「单段解析失败时该段静默空白（`ChatMarkdownView` 解析失败直接返回，不做兜底）」、`markdown-rendering.md` 无兜底声称、`docs/specrune-mobile/README.md:37`「正文按段渲染，段与段互不影响」；代码 `ChatMarkdownView.swift:58` `guard case .success(let parsed) = result else { return }` 静默空白，`grep "渲染失败"` 零命中。但任务产物仍声称兜底提示：`prd.md:21`「单块渲染异常时给兜底提示」、`prd.md:54`「加载/失败兜底」、`prd.md:67`「单块异常兜底提示」、`design.md:46`「单块渲染异常时显示兜底提示」、`design.md:52`「`Text("这一段渲染失败，其余内容不受影响")`」、`design.md:66`「兜底提示」、`implement.md:25`「单块渲染异常时显示兜底提示」。`prd.md` Requirements 3 与 AC 第 3 条（`:29`，只要求保留 1 MiB 提示）内部也不一致。建议主会话 fix pass 把这几处改为「单段解析失败时该段静默空白」。
- **F20 仍 open（minor，部分）**——已修：`prd.md:44` Out of Scope 改为「自动追加/无限滚动（改为显式「显示更多」按钮…）」、`design.md:67`「用显式「显示更多」按钮追加，不做滚动自动追加」、`design.md:76` 备选 B 改为「未采用」、`implement.md:36`「点「显示更多」可逐段看完」、`implement.md:50`「「显示更多」保持初始 1 段、每次 +1」。残留：`design.md:29-41` 的容器伪代码仍是 `Color.clear` + `onScrollVisibilityChange(threshold: 0.01)` 哨兵版本（`:36`），与同文件 `:43` 的「点按钮每次追加 1 段」矛盾；`design.md:65` 仍写「滚动到末尾逐块追加解析」。后续会话按伪代码实现会回到已否决的自动追加方案。

### 新 findings

## F21 nit .specrune/spec/ios/markdown-rendering.md:54-55

evidence: 验证段仍写「确认分块正文出现、可滚动到底」，在「初始只渲染第 1 段、每次点「显示更多」加 1 段」的方案下，「可滚动到底」不再自动成立（1.9 MB ≈ 130 段需点约 129 次）；`prd.md:29` 的同类表述已改（见 F13），spec 这处是残留。建议改为「首段正文出现、点「显示更多」能逐段看完全文」。

status: open

## F22 nit .specrune/spec/ios/specrune-board.md:19, docs/specrune-mobile/README.md

evidence: 「调研文件大小」的实测事实只记在 `design.md:63` 与代码注释 `SpecRuneTasksView.swift:998-999`（「本仓库 65 份平均 8 KB、最大约 30 KB」），spec 与 docs 都没有记录「SpecRune 对调研文件大小无硬性约定，面板只有 1 MiB 读取截断」这一前提；后续会话可能把 30 KB 当成约定，或误以为需要按大小分页。建议在 `specrune-board.md:19` 附近补一句（统计取整为 8 KB / 30 KB 与实测 8.3 KB / 29.7 KB 一致，无需改代码注释）。

status: open

### 本轮结论

- 代码、spec、docs、测试、边界均与最终方案一致；无 blocker/major 仍 open。
- 剩余 open 均为 minor/nit，集中在任务产物与两处文档措辞（F19/F20/F21/F22）以及可 deferred 的测试补强（F4）、兜底常量清理（F5）、任务元数据（F8）、表格切点（F10）、一处注释用词（F15）；不改变行为，建议主会话 fix pass 一并收口后再归档。
- 本轮只写 `review.md`，未改代码/规格/任务产物；未 commit/push。

Candidate: green

Verdict: green
