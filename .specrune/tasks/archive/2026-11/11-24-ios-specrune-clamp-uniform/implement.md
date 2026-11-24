# 实施：分块渲染替代 16000 字符截断

## 前置检查

- [ ] `git status --short` 确认只有任务目录与本任务要改的文件；不碰 `connector/`、`server/`、`android/`。
- [ ] 读 `.specrune/spec/ios/specrune-board.md`、`markdown-rendering.md`、`index.md`（实跑要求）。
- [ ] 读 `SpecRuneTasksView.swift` 的调研/记录展开区、`docBody`、`specRow`，确认现有 clamp 接入点。
- [ ] 读 `ChatMarkdownView.swift` 的 `.task` 解析与取消语义，确认多实例并发安全。
- [ ] 确认模拟器签名构建命令（`CODE_SIGN_IDENTITY="-"`）。

## 实施步骤

1. **切分纯函数（SpecRuneKit）**
   - 新增 `SpecRuneDocChunks.swift`：`split(_:maxCharacters:)` 按行扫描、跟踪 ```/~~~ 围栏、空行/标题优先切、单段超长按行切；返回 `[String]`，拼接后与原文一致。
   - 测试：短文本单块、超长多块、围栏不被切断、无空行长段、空正文、块拼接等于原文、每块 ≤ 上限（围栏块除外）。

2. **分块容器（SpecRuneTasksView）**
   - 新增 `SpecRuneChunkedMarkdown`：`VStack` + 「显示更多」显式追加（初始 1 段，点按钮每次加 1 段）+ 每段 `ChatMarkdownView(text:blockSpacing:0,reservesStreamingHeight:false)`；段大小用 `SpecRuneDocChunks` 默认 16 000（不覆盖上限）。
   - `LazyVStack` 在本详情页的嵌套滚动上下文里不渲染（2026-11-24 实跑），不要改回。
   - 接入调研/记录展开区（替换 `SpecRuneDocMarkdown` 的正文渲染；保留 `bytes` 提示逻辑）。
   - 接入 `docBody`（PRD/设计/实施/审查）与 `specRow`（规范展开）；注意外层已有 `ScrollView` 时不要嵌套。
   - 删除「正文过大，仅显示前 16000 字符」提示；保留 1 MiB 提示并改文案为「原文超过 1 MiB，仅读取前 1 MiB」。

3. **失败处理与可访问性**
   - 单段解析失败时静默空白（段与段独立）；保留清单行的 accessibilityLabel。
   - 空正文/单块路径与现有空态一致。

4. **文档与变更记录**
   - `docs/specrune-mobile/README.md`：验证状态改为已实跑（保留未复核项）；说明分块渲染与 1 MiB 读取上限。
   - `.specrune/spec/ios/specrune-board.md`：把「clamp 16000」改为分块渲染契约（`SpecRuneDocClamp` 保留为段大小常量来源）。
   - `CHANGELOG.md` 未发布 iOS 条目：改为「大文件正文可完整滚动查看」的用户可感知描述。
   - ios spec 的 markdown-rendering.md 大文本节同步（clamp → 分块）。

5. **测试与实跑**
   - `swift test --disable-sandbox`（新增切分用例 + 既有 54 tests）。
   - 签名构建并安装到 iPhone Duo；在归档任务 `11-21-fix-specrune-board-picker-drawer-shift` 下重建 1.9 MB 调研夹具，展开确认不崩溃、首段出现、点「显示更多」可逐段看完、无「仅显示前 16000」提示；夹具收尾前清理。
   - 顺带验证 `docBody`（PRD/设计/实施/审查）与规范展开。

## 验证命令

```bash
cd ios/Packages/SpecRuneKit && swift test --disable-sandbox
cd ios/Packages/SpecRuneKit && swift build --disable-sandbox
cd "ios/Agents Anywhere" && xcodebuild -project "Agents Anywhere.xcodeproj" -scheme "Agents Anywhere" -destination 'platform=iOS Simulator,id=138A5F69-4F9D-4FE2-A215-E1DAB226A92F' -derivedDataPath /tmp/aa-dd5 -packageCachePath /tmp/aa-pkgcache5 OTHER_SWIFT_FLAGS="-disable-sandbox" CODE_SIGN_IDENTITY="-" build
git status --short connector/ server/ android/ desktop-workbench/ web-next/
```

## 风险文件与回滚点

- `SpecRuneTasksView.swift`：`docBody`/`specRow` 接入时注意已有 `ScrollView`，避免嵌套滚动；调研/记录展开区的默认展开状态与 meta 行不能回归；「显示更多」保持初始 1 段、每次 +1，段大小用默认 16 000。
- `SpecRuneDocChunks.swift`：围栏跟踪必须覆盖 ``` 与 ~~~；切分拼接必须等于原文（单测钉住）。
- `ChatMarkdownView` 不改；若多实例出现解析互相覆盖，检查 `activeParseText`/`MarkdownPublishRule`（每实例独立，理论上安全）。
- 回滚：删除 `SpecRuneDocChunks`/`SpecRuneChunkedMarkdown`，恢复 `SpecRuneDocMarkdown` 的 clamp 接入；无跨端回滚。

## 未决/后续

- `LazyVStack` 在本详情页的嵌套滚动上下文里不渲染、全量 `VStack` 铺开在真机会卡死（2026-11-24 实跑+真机），已改为 `VStack` + 「显示更多」；真机验收通过。
- 表格跨块切断风险：实现时尽量在表格行外切；实跑观察。
