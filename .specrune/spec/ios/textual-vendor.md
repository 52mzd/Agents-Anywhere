# Textual vendor 状态（2026-10-24 对照）

上游：<https://github.com/gonzalezreal/textual>（gonzalezreal，MIT，
swift-markdown-ui 的继任者）。本地 `ios/Packages/Textual/` 是 vendor
拷贝 + 团队定制，**不是** SwiftPM 依赖——上游更新不会自动到达。

## 与上游 0.5.0（01b5187）的对照

- 31 个文件有差异，集中在 `TextInteraction/TextLayout`（选择与布局
  收集）与 `TextFragment`。
- 本地**领先**上游的部分：`LiveTextLayoutCollection` 判等已含 size
  （上游 PR #88 描述的"Text 首排布局固化"问题，本地已修一半）；
  `overlayTextLayoutCollection` 有 `isEnabled` 按需开关（本地性能定制）。
- 本地另有性能定制：行级解析结果缓存（fe9952de）、流式只重解析尾部
  （54932159）、附件/链接预扫描（TextBuilder）。

## 升级决策注意

- 升级 = 手动 diff 合并，且必须保留上述本地定制（性能回归风险）。
- 上游 PR #88（未合并）含 3 个选择/布局修复 + 快照测试修正，若遇到
  选择相关崩溃可参考其 diff。
- 已知无关问题：大文档布局循环崩溃（上游 #23，本地未见）、数学上标
  渲染（#94）。
