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
