# 设计：分块渲染替代 16000 字符截断

## 架构与边界

改动只落在 iOS：

- `ios/Packages/SpecRuneKit/Sources/SpecRuneKit/`：新增分块切分纯函数（可测）。
- `ios/Agents Anywhere/Agents Anywhere/Views/SpecRune/SpecRuneTasksView.swift`：新增分段容器（`VStack` + 「显示更多」显式追加），替换调研/记录展开区、`docBody`、`specRow` 的正文渲染。
- `ios/Packages/SpecRuneKit/Tests/SpecRuneKitTests/`：切分用例。
- 文档：`docs/specrune-mobile/README.md`、`CHANGELOG.md`、`.specrune/spec/ios/specrune-board.md`。

不改 `ChatMarkdownView`、Connector、Server；聊天流式路径完全不动。

## 数据流与契约

### 1. 分块切分

`SpecRuneDocChunks.split(_ content: String, maxCharacters: Int = 16_000) -> [String]`（SpecRuneKit）：

- 按行扫描，累计字符；跟踪 ``` / ~~~ 围栏状态，围栏内不切。
- 切点优先级：空行 > 标题行（`#`）前 > 行尾；切后块 ≤ `maxCharacters`（围栏内可短暂超过，直到围栏闭合或达到硬上限，避免切断代码块）。
- 单段（无空行）超长时按行切；每块仍按顺序拼接后与原文完全一致（不丢字符）。
- 空正文返回空数组；正文 ≤ `maxCharacters` 返回单块。

### 2. 分块容器

`SpecRuneChunkedMarkdown`（View）：

```swift
VStack(alignment: .leading, spacing: 8) {
    ForEach(chunks.prefix(visibleChunks).indices, id: \.self) { i in
        ChatMarkdownView(text: chunks[i], blockSpacing: 0, reservesStreamingHeight: false)
    }
    if visibleChunks < chunks.count {
        Button("显示更多（剩余 \(chunks.count - visibleChunks) 段）") {
            visibleChunks = min(chunks.count, visibleChunks + 1)
        }
    }
}
```

- `LazyVStack` 在本详情页的嵌套滚动上下文里不渲染正文（2026-11-24 实跑，VStack 版本正常显示）；一次性 `VStack` 铺开几十段在真机上又会卡死/闪退（同日真机实录），因此改用 `VStack` + 「显示更多」显式追加：初始只渲染第 1 段，点按钮每次追加 1 段。
- 每块独立 `ChatMarkdownView`；块大小用 `SpecRuneDocChunks` 默认 16 000 字符（1 MiB ≈ 60 块），不覆盖上限。
- 调研/记录展开区、`docBody`、`specRow` 统一使用；`docBody`/`specRow` 外层已有 `ScrollView` 时只替换内部渲染，不嵌套滚动容器。
- 数据层 1 MiB 截断提示保留，文案改为「原文超过 1 MiB，仅读取前 1 MiB」；单段解析失败时静默空白，段与段独立。

### 3. 提示文案

- 删除「正文过大，仅显示前 16000 字符」。
- 保留「原文超过 1 MiB，仅读取前 1 MiB」（说明这是读取上限，不是展示上限）。
- 单段异常：`ChatMarkdownView` 解析失败直接返回，该段静默空白（不为罕见情况加双解析成本）。

## 兼容性与迁移

- `SpecRuneDocClamp` 保留为段大小常量来源（不再单独截断渲染）；`SpecRuneDocClampTests` 继续通过。
- 现有文档 tab 的可见性、默认展开第一项、meta 行、accessibility 不变。
- 不改 `ChatMarkdownView`，聊天消息/流式渲染零影响。
- 不新增权限、不改 Connector 端点。

## 取舍与风险

- **LazyVStack 实测不渲染、全量铺开会卡死**：嵌套 `ScrollView`/`VStack` 上下文里 `LazyVStack` 不渲染正文（实跑），而 `VStack` 一次性铺开几十段在真机上卡死/闪退（同日真机实录）；改用 `VStack` + 「显示更多」显式追加。段大小保持默认 16 000；真实调研文件平均 8 KB、最大约 30 KB，绝大多数一段看完。
- **块边界切断表格**：表格跨空行切分会断；调研/记录/PRD 中表格较少，必要时在表格行内不切（实现时按行判断）。
- **60 块解析性能**：1 MiB / 16000 ≈ 60 块，未加载的块不创建、不解析；滚动到末尾逐块追加解析，可能有短暂延迟。实跑 1.9 MB 夹具验证。
- **无兜底提示**：单段解析失败时该段静默空白，其余段照常；Markdown 解析失败极罕见。
- 用显式「显示更多」按钮追加，不做滚动自动追加（自动追加需哨兵可见性触发，在嵌套滚动上下文不稳定）；全部内容可逐段查看。

## 回滚

删除 `SpecRuneDocChunks` / `SpecRuneChunkedMarkdown`，恢复 `SpecRuneDocMarkdown` 的 clamp 接入；`ChatMarkdownView`/Connector 未改，无跨端回滚。

## 备选方案

- **A. 分段 + 「显示更多」（已选）**：每段 ≤16000 字符，`VStack` + 显式追加，点按钮加下一段；`LazyVStack` 实测不渲染、全量铺开真机卡死，故都不采用。
- **B. 滚动自动追加**：哨兵 `onScrollVisibilityChange` 触发追加；实测在嵌套滚动上下文不稳定（展开后正文空白），未采用。
- **C. TextKit / WKWebView 渲染**：可一次显示全文，但换渲染器、回归面大，且与现有 Textual 样式不一致，不做。
- **D. 保留 16000 clamp**：改动最小，但用户明确要求全部显示，否决。
