# SpecRune 看板数据层契约（iOS）

> 适用于 `ios/Packages/SpecRuneKit` 与主 app 的 SpecRune 视图。数据只经
> `SpecRuneTransport` 的三条能力（shell / readText / listDirectory）取，
> 对应 Connector 的 `shell.exec` / `fs.readText` / `fs.readDir`；不改 Server
> 或 Connector。字段形状权威见 `contracts/specrune/1.0/README.md`。

## 调研清单 `researchFiles` {#research-files}

**范围**：任务详情「调研」tab 的文件清单。

**签名**：`SpecRuneClient.researchFiles(repo:taskDir:) async -> [SpecRuneResearchFile]`（`ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneClient.swift`）；`SpecRuneResearchFile { name, bytes, truncated, content }`（`ios/Packages/SpecRuneKit/Sources/SpecRuneKit/DTO.swift`）。

**契约**
- 来源三类：任务根的 research 报告、根级 research-<slug> 报告（`^research(?:-[^/]+)?\.md$`，大小写不敏感）、research 目录第一层 `.md`（不递归子目录）。
- 同名去重：research 目录内版本优先于根版本。
- 排序：按文件名升序（`localizedStandardCompare`）。
- iOS 不取 mtime：Connector `fs.readDir` 不返回 `modifiedAt`；清单不显示修改时间、无时间排序开关（决策记录见 2026-11-23 会话记录）。
- 每项 `bytes` 取 `readText` 的 `size`（真实字节数）；正文 1 MiB 字节截断由 Connector `maxBytes` 保证。
- 调研文件大小没有约定：SpecRune 不限制 `research/<slug>.md` 的字节数，1 MiB 只是面板读取上限。实测本仓库 65 份调研文件平均 8.3 KB、最大 29.7 KB，所以 16 000 字符一段对绝大多数文件足够。
- 读取失败：单文件跳过；任务目录或 research 目录不可读返回空数组。

**校验与错误矩阵**

| 条件 | 结果 | 谁发现 |
| --- | --- | --- |
| 任务目录不可读 | `[]`，详情其他部分正常 | 调用方（空数组） |
| 单文件读失败 | 跳过该文件 | `researchFiles` |
| 同名根/目录并存 | 目录版本胜出 | 单测 `researchDirectoryWins` |

## 记录清单 `sessionRecords` {#session-records}

**范围**：任务详情「记录」tab 的会话记录清单。

**签名**：`SpecRuneClient.sessionRecords(repo:taskRef:) async -> [SpecRuneSessionRecord]`（`ios/Packages/SpecRuneKit/Sources/SpecRuneKit/SpecRuneClient.swift`）；`SpecRuneSessionRecord { name, at, bytes, truncated, content, body, meta }`（`ios/Packages/SpecRuneKit/Sources/SpecRuneKit/DTO.swift`）。

**契约**
- 扫 `.specrune/sessions/*.md`；frontmatter 段 `^---\r?\n([\s\S]*?)\r?\n---`，缺闭合跳过。
- `id` / `task` 用 `^key:[ \t]*(.*)$`（只吃水平空白）；空值视为缺失，跳过该条。
- 匹配：`task == 任务目录名` 或 `task == 去掉 ^\d{2}-\d{2}- 前缀的短名`。
- `meta` 取 title、status、created、developer、platform、branch 六个键，空值省略；`body` 为去掉 frontmatter 段及其后连续空行的正文。
- `at` 从文件名 `^(\d{8})T(\d{6})-` 解析 UTC，转本地 `yyyy-MM-dd HH:mm:ss`；非法日期（如 2026-02-30）返回空。
- 排序按文件名倒序；任务根的 record 文档固定附在末尾（`at` 空、`meta` 空、`body = content`）。
- 并发：每批 6 个文件；单文件失败跳过；目录不存在返回空数组。

**校验与错误矩阵**

| 条件 | 结果 | 谁发现 |
| --- | --- | --- |
| `.specrune/sessions` 不存在 | `[]` | `sessionRecords` |
| 缺闭合 / 缺 id / 空 id / 空 task | 跳过该条 | 单测 `skipsMalformed` |
| 任务目录名带 `NN-MM-` 前缀 | 短名兜底匹配 | 单测 `matchesShortName` |
| CRLF frontmatter | body 前导换行剥净 | 单测（CRLF 用例） |

## 详情装配与渲染 {#assembly}

**契约**
- `SpecRuneTaskDetail` 带 `researchFiles` / `sessionRecords`；两个聚合各自容错，失败返回空数组，不拖垮详情。
- tab 条件：`research` = `researchFiles` 非空或 `docs[.research]` 存在；`record` = `sessionRecords` 非空或 `docs[.record]` 存在。
- 正文统一分块渲染：清单展开区（调研/记录）、其他文档 tab（`docBody`）与规范展开（`specRow`）都交给 `SpecRuneChunkedMarkdown`——正文先经 `SpecRuneDocChunks.split`（默认每块 16 000 字符）切成多块，再由 `VStack` + 分段渲染：初始只渲染第 1 段，点「显示更多（剩余 N 段）」每次追加 1 段，全部内容可查看。一次性铺开几十段在真机上会卡死/闪退（2026-11-24 真机实录），必须显式追加。`LazyVStack` 在本详情页的嵌套滚动上下文里不渲染正文（2026-11-24 实跑），不要使用。外层详情页已有 `ScrollView`，容器内不再嵌套滚动。
- 切分按行扫描、跟踪 ``` / ~~~ 围栏：优先空行、其次标题行前、再行尾；围栏内不切（可短暂超过 16 000，直到闭合或硬上限 32 000 = 2 倍上限）；所有块顺序拼接必须与原文完全一致。段大小上限只在 `SpecRuneDocChunks.maxCharacters` 定义一处，`SpecRuneDocChunksTests` 钉住它不超过 16 000。
- 数据层 1 MiB 截断提示保留，文案「原文超过 1 MiB，仅读取前 1 MiB（原始 N 字节）」——1 MiB 是读取上限，不是展示上限。
- 单段解析失败时该段静默空白（`ChatMarkdownView` 解析失败直接返回，不做兜底）；段与段独立，其他段照常渲染。Markdown 解析失败极罕见，不为它增加双解析成本。

**Wrong vs Correct**

```swift
// 错误：把 1 MiB 正文整篇交给渲染器（大量短段落 → Text.resolve 递归爆栈）
ChatMarkdownView(text: item.content, blockSpacing: 0, reservesStreamingHeight: false)

// 正确：先分段，交给「显示更多」容器（每段 ≤ 16 000 字符）
SpecRuneChunkedMarkdown(text: item.content)
```

```swift
// 错误：用 \s* 匹配 frontmatter 空值（可跨行，吞掉下一行）
// 正确：只吃水平空白
^id:[ \t]*(.*)$
```

## 测试 {#tests}

- `cd ios/Packages/SpecRuneKit && swift test --disable-sandbox`
- 断言点：调研三来源/排除项/同名去重/文件名升序/1 MiB 截断/读失败跳过；记录匹配/短名兜底/CRLF/meta 空值省略/畸形跳过/文件名倒序/时间解析（含非法日期）/截断；clamp 短文本/超长/空/阈值上限；分块 空正文/短正文单块/多块上限/围栏不切断/围栏超硬上限/无空行长段/标题前切/空行后切/单行超长/拼接等于原文。
