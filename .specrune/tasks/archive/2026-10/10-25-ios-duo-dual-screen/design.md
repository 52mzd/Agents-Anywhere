# 设计：iOS 客户端 iPhone Duo 上下双屏

## 实现期修正（2026-10-25，SDK 实证）

对 Xcode 27.1 (27A9275) SDK 头文件与 swiftinterface 的实证推翻了调研的一个关键假设：

- **SwiftUI 没有公开的 ArrangementView**（swiftinterface 0 匹配；ecorpIT 文章的
  SwiftUI 符号系 AI 辅助写作失实，SwiftUI 侧 API 全部不存在）。
- **UIKit API 真实存在且完整**：`UIArrangementViewController`（setViewController(_:for:)
  / updateArrangement(_:)）、`UISplitArrangement.splitArrangement()`、`UIOverlayArrangement`、
  `UIHinge`、`UIHingeInteraction`、`UIViewReservedRegion`（division/occlusion，均 27.1+）。
- `.specrune/spec/ios/duo-layout.md` 契约：机型判断用既有 `isDuoFoldableIPhone`
  （iPhone19,4，模拟器走 SIMULATOR_MODEL_IDENTIFIER）——**双屏分支的启用条件
  = isDuoFoldableIPhone && #available(iOS 27.1, *)**，普通 iPhone 不受影响，
  天然满足"普通设备不劣化"的 contingency。

修正后的方案：`DuoArrangementHost` 改为 **UIViewControllerRepresentable**，
内部用 `UIArrangementViewController` + 两个 `UIHostingController` 分别承载
Timeline（primary，上屏）与现有 bottom dock VStack（secondary，下屏），
`updateArrangement(.splitArrangement())`。审批卡 InteractionDock 随 dock 放
下屏顶部（仅阻断性通知出现时可见，保留审批可达性；平时即"全屏输入区"）。

## 目标形态

iPhone Duo 内屏（竖屏完全展开或半折叠笔记本姿态）下，会话详情页变为上下双区域：

- **上区域（primary）**：消息流 `ChatTimelineView`（只读浏览）
- **下区域（secondary）**：输入区 `ChatComposerDock`（用户已确认：下屏只放输入区，
  审批卡片/快捷操作/命令面板不加）

非 Duo 设备与 iOS < 27.1 环境：保持现有单屏布局，行为不变。

## 架构与边界

改造集中在 `Views/Chat/SessionChatView.swift` 一层，新增一个薄适配层：

```
SessionChatView
  └─ DuoArrangementHost（新文件，Views/Chat/DuoArrangementHost.swift）
       ├─ iOS 27.1+：ArrangementView { timeline } secondary: { composerDock }
       └─ 其他/回退：现有 safeAreaInset 布局原样保留
```

要点：

1. **拆分布局，不拆模型**。`SessionChatModel`、Composer 草稿、滚动状态全部复用；
   只是同一组子视图换容器。开合切换瞬间草稿与已加载历史不丢（模型层本就与视图分离）。
2. **门控方式**：`if #available(iOS 27.1, *)` 包裹 ArrangementView 分支；
   else 分支保留现有 `safeAreaInset` 代码路径，逐字不动。
3. **导航包裹方向**：`.modifier(ChatPageToolbar(...))` 与 `.toolbar` 保持在
   ArrangementView **外层**（符合 Apple 规则：导航容器包 arrangement，不反过来）。
4. **不主动检测铰链**：布局交给 ArrangementView 自动响应竖屏/折叠；
   `onHingeChange` 与 `reservedRegions` 第一期都不用（无角度驱动效果需求）。
   若模拟器验证发现 split 未按预期避开折叠带，再引入
   `reservedRegions(kind: .division)` 做微调——作为 contingency 写进 implement。
5. **sheet/toast 层不变**：SessionSheet、ChatErrorToasts、toolbar 均在容器外，
   ArrangementView 只接管 timeline 与 bottom dock 两个子树。

## 数据流与契约

无新数据模型、无 API/协议改动。跨端契约（contracts/）不受影响。
本地化：新增文案暂无（复用现有 placeholder 等）；VoiceOver 顺序由容器自动推导，
验证项里确认。

## 兼容与迁移

- 部署目标 26.5 不变；27.1 符号全部 `#available` 门控，旧系统编译/运行不受影响。
- 普通iPhone/iPad（无铰链、非 Duo）：iOS 27.1 上 ArrangementView split 也会生效
  （竖屏上下分）——这不是退化而是同一自适应行为的自然延伸；如模拟器验证发现普通
  大屏 iPhone 上下分体验劣于现有 safeAreaInset 布局，则收紧为仅检测到 division
  region 或 Duo 尺寸类时启用（contingency，implement 中列为验证分支）。

## 风险与回滚

- 改动单文件为主 + 一个新文件，回滚 = revert 该 commit。
- 最大不确定性：键盘行为（下屏 Composer 聚焦时键盘占据下屏的布局表现）与
  Composer 最大高度 `min(160, ...)` 在双区域下的适配，均列为模拟器验证项，
  发现问题在本层内修，不外溢。

## 备选方案

1. **UIHingeInteraction + reservedRegions 手工计算上下分割**——拒绝：Apple 明确
   布局应交给 ArrangementView，铰链 API 只做效果；手工算会重复造轮子且易错。
2. **NavigationSplitView 样式复用（上 detail 下 content）**——拒绝：语义不符，
   split view 是导航容器，放 Composer 进 sidebar 语义错乱，且 HIG 已有 arrangement
   专用容器。
3. **在 ChatShell 层（列表+详情）做双屏，上=详情下=会话列表**——拒绝：用户已决策
   上=消息流下=输入区；列表侧内屏横屏已有 NavigationSplitView 承载。
4. **overlay 样式（primary 盖 secondary，半折叠才分开）**——拒绝：完全展开竖屏时
   overlay 会叠在一起，不满足"上下分别显示不同内容"的常态需求；split 才是默认形态。
