# 统一 SpecRune 文档渲染：分块渲染替代 16000 字符截断

## Goal

把 SpecRune 任务详情的文档正文渲染从「超过 16000 字符只显示前 16000」改为「分块渲染、全部可滚动查看」：调研/记录清单展开区、`docBody`（PRD/设计/实施/审查）与 `specRow`（规范展开）统一走分块容器；同时收口截断提示文案与文档验证状态。

## Confirmed Facts

- 现有保护：`SpecRuneDocClamp.maxCharacters = 16_000`，只用于调研/记录清单展开区（`SpecRuneDocMarkdown`）；`docBody` 与 `specRow` 仍直接把最多 1 MiB 正文交给 `ChatMarkdownView`。
- 崩溃根因：`ChatMarkdownView` 把整篇文本解析成 blocks 后用 `VStack` 一次性创建所有 `MarkdownBlockView`；1 MiB / 约 90 000 个短段落会让 SwiftUI `Text.resolve` 递归约 16 300 层而 SIGSEGV。16000 字符是单次渲染的安全上限，不是全文应展示的上限。
- `ChatMarkdownView` 支持独立实例、异步 `.task` 解析、取消不丢结果；非流式全文参数为 `blockSpacing: 0, reservesStreamingHeight: false`。
- 两条提示并存矛盾（`SpecRuneTasksView.swift`）：clamp 提示「正文过大，仅显示前 16000 字符」与 Connector 截断提示「已截断：原始 N 字节，仅显示前 1 MiB」。
- `docs/specrune-mobile/README.md` 的「验证状态」仍写「未做实跑」，与 iPhone Duo 模拟器实跑记录矛盾。
- 测试：`cd ios/Packages/SpecRuneKit && swift test --disable-sandbox` 当前 42 tests / 7 suites 全绿。
- 模拟器实跑要求签名构建（`CODE_SIGN_IDENTITY="-"`），否则 Keychain 登录 `-34018`；1.9 MB 调研夹具已在归档任务下造过，可重建。

## Requirements

1. **分块切分（纯函数）**：把正文按 Markdown 边界切成每块 ≤16000 字符的多块；优先在空行/标题处切，跟踪 ``` 围栏避免切断代码块；单段超长时按行切，保证不丢字符、顺序不变。
2. **分段容器**：新增分段容器（`VStack` + 显式追加；`LazyVStack` 在本详情页的嵌套滚动上下文里实测不渲染），每段一个独立 `ChatMarkdownView`（非流式参数）；调研/记录展开区、`docBody`、`specRow` 统一使用；初始只渲染第 1 段，点「显示更多」每次追加 1 段（一次性铺开几十段在真机上卡死/闪退）。
3. **全部显示**：去掉「仅显示前 16000 字符」；保留数据层 1 MiB 截断提示（「原文超过 1 MiB，仅读取前 1 MiB」语义），单段解析失败时静默空白（段与段独立，不拖垮全文）。
4. **性能与稳定**：1.9 MB 夹具展开不卡死、不闪退，点「显示更多」可逐段看完；不一次性创建所有段。
5. **文案与文档**：修正两条提示矛盾；同步 `docs/specrune-mobile/README.md` 验证状态、`CHANGELOG` 与 ios spec；补切分逻辑测试。

## Acceptance Criteria

- [ ] 切分纯函数：每块 ≤16000 字符、优先空行/标题边界、``` 围栏不被切断、单段超长按行切、不丢字符且顺序不变；单测覆盖。
- [ ] 统一渲染：调研/记录展开、`docBody`、`specRow` 全部走分段容器；`VStack` + 「显示更多」显式追加，`LazyVStack` 实测不渲染；`blockSpacing: 0, reservesStreamingHeight: false` 不变。
- [ ] 全部显示：1.9 MB 夹具展开后没有「仅显示前 16000」提示，首段立即显示、点「显示更多」可逐段看完全部内容；只保留 1 MiB 数据层截断提示（语义不再声称「仅显示前 1 MiB」）。
- [ ] 稳定性：真机展开 1.9 MB 文件不卡死、不闪退（一次性铺开几十段会卡死，已由「显示更多」规避）；长→短文档切换正文不空白；`docBody`/`specRow` 正常。
- [ ] 文档与测试：`docs/specrune-mobile/README.md` 验证状态、`CHANGELOG` 与 ios spec 同步；`swift test` 全绿（含新增切分用例）。

## Deliverables

- SpecRuneKit/UI 分段切分纯函数、`VStack` + 「显示更多」容器与测试。
- 调研/记录、`docBody`、`specRow` 统一接入。
- 提示文案、文档、CHANGELOG、ios spec 同步。

## Out of Scope

- 改 `ChatMarkdownView` 通用组件（聊天流式路径不动）。
- 换 TextKit / WKWebView 渲染器。
- Connector / Server 改动。
- 自动追加/无限滚动（改为显式「显示更多」按钮，避免真机一次性布局过多段落）。

## Open Questions

- 无（分块方案已由用户裁决）。

## Coverage taxonomy

- Goal & scope：covered（只 iOS 文档渲染；聊天流式、Connector/Server out）。
- Domain & data：covered（Markdown 块边界、围栏、字符上限）。
- Interaction & states：covered（展开/收起、「显示更多」逐段加载、解析失败静默空白）。
- Non-functional quality：covered（分段渲染、内存、真机卡死/闪退、1.9 MB 夹具）。
- Integration & dependencies：covered（复用 ChatMarkdownView 实例，不改通用组件）。
- Edge cases & failure handling：covered（代码围栏、超长单段、空正文、块边界表格、渲染异常）。
- Constraints & trade-offs：covered（不改 ChatMarkdownView；LazyVStack 在嵌套滚动上下文不渲染）。
- Completion signals：covered（单测 + 模拟器实跑 + 文档同步）。

## Implicit requirements sweep

- 数据在崩溃后不丢失/不重复：not-applying（只读展示）。
- 敏感/个人数据：not-applying（只读任务产物）。
- 权限：not-applying（沿用 Connector 鉴权）。
- 审计：not-applying（只读）。
- 失败时用户看到什么：applied（单段解析失败只影响该段；数据层 1 MiB 截断有提示）。
- 兼容性：applied（聊天流式路径不改；现有文档 tab 行为保留）。
- 可访问性/本地化：applied（沿用现有清单与 tab 的 accessibility；文案中文）。
