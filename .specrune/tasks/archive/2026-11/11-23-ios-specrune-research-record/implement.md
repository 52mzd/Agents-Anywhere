# 实施：补齐 iOS SpecRune 面板的调研与记录维度

## 前置检查

- [ ] `git status --short` 确认只有任务目录与本任务要改的文件；不碰 `connector/`、`server/`、`android/`。
- [ ] `swift --version` / `xcodebuild -version` 确认工具链可用（本机 Swift 6.4.2、Xcode 27.2）。
- [ ] 读 `ios/Packages/SpecRuneKit/Package.swift` 与 `docs/specrune-mobile/README.md`，确认验证命令。
- [ ] 读 `.specrune/spec/ios/markdown-rendering.md` 与 `.specrune/spec/connector/local-rpc.md`，确认非流式 Markdown 参数与 64k/4MiB 边界。

## 实施步骤

1. **契约先行（只读字段形状）**
   - 更新 `contracts/specrune/1.0/schemas/task-detail.response.schema.json`：
     - `researchFiles` 描述改为三来源聚合（任务根 `research.md`、根 `research-<slug>.md`、`research/` 第一层 `.md`；同名去重 `research/` 优先）。
     - 新增 `sessionRecords` 数组与 `$defs/SessionRecord`（`name`/`at`/`bytes`/`truncated`/`content`/`body`/`meta`），`meta` 定义 `title`/`status`/`created`/`developer`/`platform`/`branch`。
     - `ResearchFile` 保留 `at` 可选；iOS 端不取 mtime 时可为空/省略。
   - 更新 `contracts/specrune/1.0/manifest.json` 中 task-detail schema 的 sha256（`shasum -a 256`）。
   - 更新 `contracts/specrune/1.0/README.md`：补充调研三来源、记录清单、iOS 按文件名排序的替代说明。
   - 校验：`python3 -m json.tool` 两个 JSON；如可用，跑 README 的 jsonschema 校验。

2. **SpecRuneKit 传输层**
   - `Transport.swift`：`SpecRuneTextFile` 加 `size: Int`。
   - `SpecRuneConnectorTransport.readText`：填 `response.size`。
   - `DTO.swift`：`SpecRuneDoc` 加 `bytes: Int`；`SpecRuneTaskDetail` 加 `researchFiles`/`sessionRecords`（默认空数组）。
   - 更新包内所有 `SpecRuneTextFile` / `SpecRuneDoc` / `SpecRuneTaskDetail` 构造点。

3. **调研聚合**
   - `SpecRuneClient.researchFiles(repo:taskDir:)`：
     - 列任务目录，筛 `^research(?:-[^/]+)?\.md$`（大小写不敏感、文件）。
     - 列 `research/`，筛 `.md`（大小写不敏感、文件）。
     - 同名去重（`research/` 优先）；按文件名升序。
     - 逐个 `readText`，构造 `SpecRuneResearchFile { name, bytes, truncated, content }`；失败跳过。
   - `taskDetail` 调用并容错（失败返回空数组）。

4. **会话记录**
   - `SpecRuneClient.sessionRecords(repo:taskRef:)`：
     - 列 `.specrune/sessions`，筛 `.md`；目录不存在返回空。
     - 分批并发（每批 6）读文件；解析 frontmatter（`^---\r?\n([\s\S]*?)\r?\n---`）。
     - `id`/`task` 用 `^key:[ \t]*(.*)$`；空值跳过；`task` 匹配任务目录名或短名（去 `^\d{2}-\d{2}-`）。
     - 解析 `meta`（6 个键，空值省略）与 `body`（去 frontmatter 段与后续空行）。
     - `at` 从文件名 `^(\d{8})T(\d{6})-` 解析 UTC 并格式化本地 `yyyy-MM-dd HH:mm:ss`。
     - 按文件名倒序；单文件失败跳过。
   - `record.md` 末尾项：复用 `docs.record` 的 content/bytes/truncated，`at` 空、`meta` 空、`body = content`。
   - `taskDetail` 调用并容错（失败返回空数组）。

5. **UI 装配（`SpecRuneTasksView.swift`）**
   - tab 可见性：`research` = `detail.researchFiles` 非空或 `docs[.research]` 存在；`record` = `detail.sessionRecords` 非空或 `docs[.record]` 存在；其它 kind 不变。
   - 调研清单视图：标题「调研报告」+ 计数；每项箭头 + 文件名 + KB；默认展开第一项（`nil`/`""` 语义）；展开 `ChatMarkdownView(blockSpacing: 0, reservesStreamingHeight: false)`；截断提示。
   - 记录清单视图：标题「记录」+ 计数；每项箭头 + 文件名 + 记录时间 + KB；展开先 meta 行（title · status · created · branch）再 body Markdown；默认展开第一项；截断提示；`record.md` 在末尾。
   - 单文件 `research.md` 兜底：`researchFiles` 为空且 `docs[.research]` 存在时构造一项同名清单。
   - 保持现有动画、`accessibilityReduceMotion`、可访问性语义。

6. **测试（`ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/`）**
   - 新增 `FakeTransport`（实现 `SpecRuneTransport`，内存文件树；`shell` 可返回固定 JSON）。
   - 调研用例：三来源入选、子目录/非 md/无关文件排除、同名去重 `research/` 优先、按名称升序、1 MiB 截断、读失败跳过。
   - 记录用例：task 匹配、短名兜底、CRLF、meta 空值省略、畸形（缺闭合/缺 id/空 id/空 task）跳过、按文件名倒序、body 去 frontmatter、文件名时间解析、截断。
   - 运行 `swift test`（见验证命令）。

7. **文档与变更记录**
   - 更新 `docs/specrune-mobile/README.md`：取数路径补 `fs.readDir`、调研/记录清单说明、iOS 排序替代。
   - 更新 `CHANGELOG.md` 的「未发布」→「iOS」分类：一句用户能感知的话（任务详情新增「调研」「记录」两个维度）。
   - 契约变更不写 CHANGELOG（开发文档，用户不可感知）。

8. **验证与收尾**
   - `cd ios/Packages/SpecRuneKit && swift test`（必须全绿）。
   - `cd ios/Packages/SpecRuneKit && swift build`。
   - `xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO`（exit=0）。
   - `git status --short connector/ server/` 必须为空。
   - 模拟器/真机实跑：打开 SpecRune → 任务详情 → 调研/记录 tab，展开多份、确认无空白/错位（若无法实跑，在 review.md 记录未做项）。

## 验证命令

```bash
cd ios/Packages/SpecRuneKit && swift test
cd ios/Packages/SpecRuneKit && swift build
cd "ios/Agents Anywhere" && xcodebuild build -scheme "Agents Anywhere" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
cd /Users/Dae/Downloads/codes/Agents-Anywhere && git status --short connector/ server/
shasum -a 256 contracts/specrune/1.0/schemas/task-detail.response.schema.json
python3 -m json.tool contracts/specrune/1.0/schemas/task-detail.response.schema.json >/dev/null
python3 -m json.tool contracts/specrune/1.0/manifest.json >/dev/null
```

## 风险文件与回滚点

- `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/DTO.swift`：新增字段会牵动构造点，先全局搜索 `SpecRuneTextFile(` / `SpecRuneDoc(` / `SpecRuneTaskDetail(`。
- `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneClient.swift`：详情加载新增两个聚合调用；任何一处抛错都必须被捕获成空数组，不能拖垮详情。
- `ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift`：tab 可见性改动要保持其他文档 tab 与概览不变；Markdown 必须用非流式参数。
- `contracts/specrune/1.0/*`：schema/manifest/README 三者一致；sha256 必须重算。
- 回滚：删除新增 DTO/聚合/UI 分支并恢复构造参数即可；无 Connector/Server 迁移。

## 未决/后续

- 会话记录逐文件读取的耗时需实测；若明显拖慢详情，后续改为点击记录 tab 时懒加载（design.md 备选 C）。
- 调研清单无 mtime，不提供时间排序开关（用户裁决 B）。
