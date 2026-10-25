# iOS Layer Spec

> 该层记录 iOS 客户端（`ios/`）的代码契约。无单测设施（scheme 无 test
> action），验证 = 双 destination 构建 + 模拟器/真机人工验收。

## Files

| File | Topic |
|------|-------|
| [duo-layout.md](./duo-layout.md) | 折叠屏（iPhone Duo）机型判断与宽屏布局契约 |
| [textual-vendor.md](./textual-vendor.md) | Textual 库 vendor 状态与上游对照 |

## Quick Rules

- 机型判断统一用 `isDuoFoldableIPhone`（ChatControlMetrics.swift），
  不要再写第二份 utsname/SIMULATOR_MODEL_IDENTIFIER 判断。
- 改宽度前先读 duo-layout.md 的"三层宽度约束"清单。
- 动 Textual 前先读 textual-vendor.md——本地是 vendor 定制版，
  升级须手动合并并保留性能定制。
- 改 `SessionChatView` 这类大体量 SwiftUI body 前注意：body 表达式再加
  任何内容就可能触发 "unable to type-check in reasonable time"。对策是把
  子树/修饰链提取为私有方法或 ViewModifier（现有 timelinePane/bottomDock/
  applyBehaviors 即为此拆分），不要往 body 里内联新表达式。
- Duo/折叠屏相关改动先读 duo-layout.md（机型判断、双屏契约、
  arrangement Swift 化名、真机部署命令）。
- 图标一律用 `AppSymbol`（资产映射）：本项目环境 `Image(systemName:)`
  完全不渲染（2026-10-26 两轮实测空白，全仓无先例）。
