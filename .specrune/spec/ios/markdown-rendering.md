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

## 取消不能丢结果

`.task(id:)` 解析完成后一度写成 `guard !Task.isCancelled, ...`。视图身份稳定时
`.task` 只跑一次，那一次若被取消（布局重建、页面切换），`blocks` 永远是空数组
——**整块正文空白且不再恢复**，不是「短暂加载」。

现在：取消仍写结果；结果是否属于当前正文由**解析请求的文本**判定——
`activeParseText == request.text` 才接受（`activeParseText` 在 task 开头写入）。
块数保护 `parsed.blocks.count >= blocks.count` **只在 `isStreaming` 时保留**：
流式是同一段文本追加，块数只增不减；非流式是整段替换，新文档块数可以比旧文档少。

**不能用块数判非流式的新旧**（2026-11-22 实录）：SpecRune 任务详情从「设计」切到
「实施」，实施块数更少，新结果被当成旧快照丢弃——标签高亮切了、正文停在设计；
从「PRD」切「设计」块数变多则正常，所以表现为「点两个标签后才失效」。

## 验证

- 纯逻辑：`cd ios/Packages/SpecRuneKit && swift test`（树 / 归档分组 / 错误分类 / jsonl）
- 渲染：模拟器实跑，**从概览切到长文档标签**（不是默认打开），确认无空白、无大间距
- 非流式文档标签切换：按块数**减少**的方向再切一次（长文档 → 短文档），确认正文跟着换
