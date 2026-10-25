# iOS 客户端支持 iPhone Duo 上下双屏

## Goal

在 iOS 客户端接入 iPhone Duo（2026-10-23 上市，折叠屏 iPhone）的展开/半折叠形态：
内屏在竖屏完全展开或半折叠（笔记本姿态）时，上下两个区域分别显示**不同的内容**，
实现类 3DS 双屏体验。价值：新形态设备上的差异化体验，抢先覆盖 Duo 早期用户。

## Confirmed Facts

### 外部调研结论（2026-10-25，来源见任务 research）

- iPhone Duo：外屏 5.4"（合盖）+ 内屏 7.6" 连续屏（展开），中间铰链；iOS 27.1 出厂。
- 内屏展开后**不是两块独立屏幕**，是一块连续屏 + 折叠区（fold region，保留区的一种）。
  "上下双屏"是布局概念，不是两个 window/display。
- 核心布局 API（均 iOS 27.1+）：
  - SwiftUI `ArrangementView { primary } secondary: { ... }`，split/overlay 两种样式；
    竖屏（高>宽）split 自动上下堆叠，primary 在上；半折叠时自动避开折叠带。
  - `GeometryProxy.reservedRegions(kind:options:)` 查询分割/遮挡区，带 `isActive`，
    需现查不能缓存。
  - `onHingeChange` 拿铰链角度/状态（closed/partiallyOpen/fullyOpen），
    Apple 明确只用于效果，不用于布局。
- Apple 规则：布局用 size class 不用 idiom/方向；`UIScreen.main` 弃用；
  不自建 bar；竖向 bar 条目必须有 symbol。

### 仓库事实（ios/，2026-10-25 核查）

- 客户端纯 SwiftUI，主壳 `Views/RootView.swift` → `ChatShellView`
  （`Views/ChatShell/`），内含 NavigationSplitView（compact 折叠为单栈）。
  会话详情在 `Views/Chat/SessionChatView`，输入区在 `Views/Chat/Composer`。
- 部署目标 **iOS 26.5**，Swift 5 → 所有 27.1 API 必须 `#available(iOS 27.1, *)`
  门控，26.5–27.x 走现有回退布局（功能等价于普通 iPhone）。
- 本机工具链已就绪：Xcode 27.1 (27A9275) + iOS 27.1 SDK + iPhone Duo 模拟器
  （Device Type `iPhone-Duo`），可开发、可模拟器验证折叠姿态。
- CI 不覆盖 iOS（AGENTS.md 明确），验证靠本地 build/test。

## Requirements

1. iPhone Duo 内屏（iOS 27.1+，竖屏完全展开或半折叠）下，会话详情页呈上下双区域：
   上=消息流 Timeline（只读浏览），下=输入区 ChatComposerDock（用户已确认：
   下屏只放输入区，不加审批卡片/快捷操作/命令面板）。
2. 非 Duo 设备、iOS < 27.1、合盖外屏：保持现有单屏布局，行为与现状一致。
3. 布局由 ArrangementView（split 样式）自动响应竖屏/折叠姿态；
   不使用铰链 API 计算布局。
4. 范围：仅会话详情页（SessionChatView）。列表/登录/设置等页面不动。
5. 跨端契约、数据模型零改动。

## Acceptance Criteria

- [ ] Duo 模拟器完全展开竖屏：上=Timeline、下=Composer，内容不被折叠带遮挡
- [ ] Duo 模拟器半折叠（笔记本姿态）：两区域分居铰链两侧
- [ ] 合盖外屏：现有 compact 单屏布局不变
- [ ] Composer 聚焦弹键盘不破下屏布局，上屏不跳动
- [ ] 开合往返：Composer 草稿、已加载历史、滚动位置不丢
- [ ] 普通无铰链设备（iOS 27.1 模拟器）行为可接受，否则按 design.md contingency 收紧
- [ ] iOS 26.x 模拟器走回退路径，与现状一致
- [ ] ios 本地构建 + 测试通过

## Out of Scope

- 相机方向/capture accessory（外屏拍照预览）——本任务不动相机
- 多窗口（inner display 多 scene）
- Android/Web/Desktop 端

## Open Questions

（无阻塞项。已决策：上屏=消息流、下屏=输入区（仅输入区）；
范围仅会话详情页——列表页无可分的两种内容，属工程判断；
验收以模拟器为准——无 Duo 真机，客观限制已记录。）

## Coverage taxonomy

- Goal & scope: covered（双屏内容、范围已决策）
- Domain & data: covered（不新增数据模型，复用现有 session/chat 状态）
- Interaction & states: covered（布局切换由 ArrangementView 自动响应；开合状态保持为验收项）
- Non-functional quality: covered（性能沿用现有基线；键盘行为列入验收）
- Integration & dependencies: covered（iOS 27.1 SDK，#available 门控，回退安全）
- Edge cases & failure handling: covered（合盖/半折叠/开合往返/Split View 均为验收项）
- Constraints & trade-offs: covered（无真机→模拟器验证，已记录）
- Completion signals: covered（验收标准可观察）

## Implicit requirements sweep

- 崩溃不丢数据：applied（沿用现有本地存储，双屏不新增持久化）
- 敏感数据：not-applying（不涉及新数据类型；沿用 Keychain/本地存储规则）
- 权限：not-applying（不新增权限）
- 审计：not-applying（纯 UI 形态变化）
- 失败时用户所见：applied（非 Duo 设备与 26.5 回退必须显示现有单屏 UI，不得白屏）
- 依赖兼容：applied（部署目标 26.5，27.1 API 全部 #available 门控）
- 无障碍/本地化：applied（新 UI 文案走 String(localized:)，VoiceOver 标签随布局）
