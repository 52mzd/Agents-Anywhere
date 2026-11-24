# ChatMarkdownView 渲染契约

`ChatMarkdownView`（`Views/Chat/Markdown/ChatMarkdownView.swift`）是聊天消息与文档
正文共用的 markdown 渲染器。它把整篇 markdown 按顶层 `presentationIntent.identity`
切成多个 block，每块交给 Textual 渲染。

三个默认行为是为**流式消息**调的；**非流式全文**（PRD / 实施 / 审查等一次性读入的
文档）必须显式改掉，否则会出现空白。2026-11-16 在 SpecRune 看板上连踩三个坑，
全部表现为「内容空白或大片留白」，且**编译与三轮代码评审都没发现**。

## 参数

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| `isStreaming` | `false` | 流式追加：逐字 reveal + 块高单调 |
| `blockSpacing` | `12` | block 之间的额外间距（`VStack(spacing:)`） |
| `reservesStreamingHeight` | `true` | 同宽度下块高只增不减 |

## 非流式全文的调用形状

```swift
ChatMarkdownView(text: doc, blockSpacing: 0, reservesStreamingHeight: false)
```

**`blockSpacing: 0`** —— Textual 自己已经给每个块加了 `blockSpacing`
（标题上 `1.25em` / 下 `0.55em`，见 `ChatHeadingStyle`）。外面再叠一层
`VStack(spacing: 12)`，标题与正文之间就出现远大于设计的空白。

**`reservesStreamingHeight: false`** —— 默认策略对**同一宽度**保留历史最大高度
（`MarkdownBlockSizing.size` 的 `max(...)`），这是流式追加防块高回缩用的。非流式
全文沿用它时，某个宽度下测出的偏大高度会被永久保留；**换宽度（开关侧栏、横竖屏）
等于换一组历史值，表现为间距随宽度变化**——这是最容易误判成「CSS/排版问题」的现象。

## 大文本必须分块（2026-11-24 实录）

`ChatMarkdownView` 把整篇文本切块后交给 Textual；**1 MiB / 大量短段落**会让
SwiftUI `Text.resolve` / `ConcatenatedTextStorage.resolve` 递归爆栈（SIGSEGV，
递归深度约 16 300 层）。实测：1 MiB（约 90 000 短段落）直接崩溃；先 clamp 到
64 000 字符仍崩溃（约 8 000 段 × 2 层 ≈ 16 000 层）；**单次渲染 16 000 字符**安全。

契约：SpecRune 文档正文（调研/记录展开区、PRD/设计/实施/审查的 `docBody`、
规范展开 `specRow`）不再截断展示，而是由 `SpecRuneKit` 的
`SpecRuneDocChunks.split` 按 Markdown 行边界切成每块 ≤ 16 000 字符的多块，交给
`SpecRuneChunkedMarkdown`（`VStack` + 分段渲染，每段独立
`ChatMarkdownView(blockSpacing: 0, reservesStreamingHeight: false)`）：初始只渲染
第 1 段，点「显示更多（剩余 N 段）」每次追加 1 段，全文可查看。一次性铺开
几十段在真机上会卡死/闪退（2026-11-24 真机实录），必须显式追加。`LazyVStack` 在本
详情页的嵌套滚动上下文里不渲染正文（2026-11-24 实跑），不要使用。切点优先空行、
其次标题行前、再行尾；``` / ~~~ 围栏内不切（可短暂超过 16 000，直到闭合或硬上限
32 000）；顺序拼接必须等于原文。`SpecRuneDocClamp` 保留作兜底。
数据层的 1 MiB 截断提示保留，但文案要说明「仅读取前 1 MiB」，不要暗示展示上限。
通用 `ChatMarkdownView` 组件不改，避免影响聊天流式渲染。

验证：模拟器实跑展开任务目录下的 1.9 MB 调研报告夹具，确认分块正文出现、可滚动
到底、只显示 1 MiB 读取提示、app 不崩溃；崩溃日志在改动后不再新增。

## 取消不能丢结果

`.task(id:)` 解析完成后一度写成 `guard !Task.isCancelled, ...`。视图身份稳定时
`.task` 只跑一次，那一次若被取消（布局重建、页面切换），`blocks` 永远是空数组
——**整块正文空白且不再恢复**，不是「短暂加载」。

现在：取消仍写结果；结果是否属于当前正文由 `MarkdownPublishRule.accepts`
（`Models/Chat/MarkdownPublishRule.swift`）判定，视图只调用它：

```swift
MarkdownPublishRule.accepts(
    requestText: request.text,      // 产生结果的解析请求
    currentText: activeParseText,   // task 开头写入的当前请求
    resultBlockCount: parsed.blocks.count,
    currentBlockCount: blocks.count,
    isStreaming: isStreaming
)
```

契约：文本不同 → 拒绝（旧任务晚到，不覆盖当前正文）；文本相同 → 流式要求块数
不减，非流式一律接受。回归测试 `ClientCoreTests/MarkdownPublishRuleTests.swift`
钉住三种情况：旧文本拒绝 / 非流式接受更少块数 / 流式保持单调。

**不能用块数判非流式的新旧**（2026-11-22 实录）：SpecRune 任务详情从「设计」切到
「实施」，实施块数更少，新结果被当成旧快照丢弃——标签高亮切了、正文停在设计；
从「PRD」切「设计」块数变多则正常，所以表现为「点两个标签后才失效」。

## 验证

- 纯逻辑：`cd ios/Packages/SpecRuneKit && swift test`（树 / 归档分组 / 错误分类 / jsonl）
- 渲染器逻辑：`swift test --package-path ios`（ClientCoreTests，含 `MarkdownPublishRuleTests`）
- 渲染：模拟器实跑，**从概览切到长文档标签**（不是默认打开），确认无空白、无大间距
- 非流式文档标签切换：按块数**减少**的方向再切一次（长文档 → 短文档），确认正文跟着换
- 大文本：用 1 MiB / 大量短段落夹具实跑展开，确认首段正文出现、点「显示更多」能逐段看完全文、只显示 1 MiB 读取提示、app 不卡死
- 模拟器构建必须签名（`CODE_SIGN_IDENTITY="-"`）：`CODE_SIGNING_ALLOWED=NO` 没有
  Keychain entitlement，登录会报 `-34018`，根本进不到渲染验证
