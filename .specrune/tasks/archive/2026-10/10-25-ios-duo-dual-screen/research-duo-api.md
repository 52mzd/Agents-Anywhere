# iPhone Duo 双屏开发调研（2026-10-25）

来源：Apple HIG "Designing for iPhone Duo"、ecorpIT iPhone Duo SDK 指南
（2026-09-18 更新）、GitHub Codelaby/IphoneDuo。外部内容均已交叉核对。

## 设备与 SDK

- iPhone Duo：外屏 5.4"（合盖，compact width）+ 内屏 7.6" 连续屏（展开，
  regular width + regular height），中间铰链，双前摄。2026-10-23 上市，iOS 27.1 出厂。
- 本机已装 Xcode 27.1 (27A9275) + iOS 27.1 SDK + iPhone Duo 模拟器（2026-10-25 核查）。

## 核心认知

内屏展开后**不是两块独立屏幕**，是一块连续屏 + 折叠区（fold region）。
"上下双屏"是布局概念（一个 window 内的两个区域），不是两个 display/window。

## 关键 API（全部 iOS 27.1+，需 #available 门控）

| 能力 | SwiftUI | 说明 |
|---|---|---|
| 双区域布局容器 | `ArrangementView { primary } secondary: { ... }` | split/overlay 样式；竖屏（高>宽）split 自动上下堆叠 primary 在上；自动避开折叠带 |
| 折叠/遮挡区查询 | `GeometryProxy.reservedRegions(kind:options:)` | `.division`（折叠分割）/ `.occlusion`（摄像头）；带 `isActive`，须现查不能缓存 |
| 铰链状态 | `onHingeChange` | closed/partiallyOpen/fullyOpen + 角度；只用于效果，不用于布局（Apple 明确） |

SwiftUI 示例：

```swift
ArrangementView {
    TopContent()
} secondary: {
    BottomContent()
}
// 默认 .automatic 即 split；竖屏自动上下分
```

## Apple 规则（禁止项）

1. 布局禁止用 `userInterfaceIdiom` / 方向判断，只用 size class + 容器 bounds。
2. `UIScreen.main` 在双屏设备上歧义（iOS 26 已弃用），用 window scene / trait。
3. 不要用裸 UIToolbar/UINavigationBar/UITabBar 拼 bar；竖向 bar 条目必须有 symbol。
4. ArrangementView 外面套导航容器（NavigationStack 等），不要放里面；也不要放进
   list/scroll view。
5. SDK 分层：只有 iOS 27.1 SDK 构建才铺满全屏并获得竖向 bar；旧 SDK 走兼容布局。
6. 多窗口只在内屏；所有 App 强制参与 Split View 50/50 分屏，需测试该尺寸。

## 与本仓库的关系

- iOS 客户端部署目标 26.5 → 27.1 API 必须门控，26.5–27.0 走现有布局回退。
- 客户端是纯 SwiftUI → 直接用 ArrangementView，无需 UIKit 侧。
- 现有 SessionChatView 用 `safeAreaInset(edge:.bottom)` 挂 Composer，
  双屏形态下需把 Timeline/Composer 拆进 ArrangementView 两个区域。
- CI 不覆盖 iOS，验证靠本地 xcodebuild + iPhone Duo 模拟器。
