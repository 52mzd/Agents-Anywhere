# iOS 折叠屏适配：外屏会话区 + 内屏双栏工作台

## Goal

折叠屏 iPhone 双形态：外屏（compact）是「会话区」——秒进活跃会话、快速回复审批；内屏（regular 展开）是双栏工作台。普通 iPhone 的行为见 Open Questions Q1。

## Confirmed Facts（代码证据）

- 根路由：`Views/RootView.swift` 按 `appState.route` 分流（loading/signedOut/signedIn），登录流程与尺寸无关。
- **regular 双栏已存在**：`Views/ChatShell/ChatShellView.swift:7-24` 读取 `horizontalSizeClass`，regular 时 `SidebarDrawer` 用 `.nativeSidebar`（分栏侧栏），compact 时用抽屉；注释明确约定用系统 trait，禁止设备型号/屏宽判断。iPad 上已是双栏形态。
- 侧栏数据：`ChatSidebarView` 已有设备/置顶会话/最近会话/账号结构；排序 `pinned → recent`（`ChatSidebarSession.presentation.precedes`）。
- 状态层分离：会话状态、WebSocket、草稿在 `Repositories/Models` 层，UI 尺寸切换不影响连接。
- 会话详情 `SessionChatView`、设备管理 `DeviceManagementView`、新建会话 `NewSessionView` 均为可复用独立视图。

## Requirements

- **R1 外屏会话区（compact 新形态）**：两 Tab——
  - 「会话」Tab：未归档会话列表（沿用现有 pinned/recent 排序），点开进 `SessionChatView` 详情；提供新建会话入口。
  - 「更多」Tab：设备管理（每设备入口）、设置、账号。
- **R2 内屏（regular）**：保持现有双栏骨架，验证栏宽与收起交互在 ~7.9" 内屏表现正常。
- **R3 状态无缝**：compact ↔ regular 切换时选中会话、输入草稿、WebSocket 会话不丢失（依赖现有状态层，主要验证）。

## Acceptance Criteria

- [ ] compact 模拟器：登录后默认「会话」Tab，列表按 pinned/recent 排序；进入会话可发消息、回复审批。
- [ ] 「更多」Tab 可达设备管理与设置/账号，功能与现有等价。
- [ ] regular（iPad 模拟器）双栏正常：侧栏常驻、选中会话右侧展示。
- [ ] compact ↔ regular 切换：选中会话保持、会话 WebSocket 不断。
- [ ] iOS target 构建成功；现有 `ios/Tests` 测试通过。

## Out of Scope

- ATS/HTTPS 改造（另行处理；公网 IPv6 需服务端上 HTTPS）。
- 外屏终端（窄屏不提供，附件只读预览维持现状）。
- App Store 发布、签名公证流程。
- 新增"按活跃度排序"算法（沿用现有排序）。

## Open Questions

- ~~Q1：普通 iPhone 是否也换成两 Tab？~~ **已定（2026-10-22，用户看过四屏 mockup 后确认）**：统一换成「会话 / 更多」两 Tab，普通 iPhone 与折叠外屏体验一致；现有 compact 抽屉侧栏布局退役。

## Implicit requirements sweep

- 崩溃数据保全：不新增持久化，沿用现有 — applied（无新增）
- 敏感数据：无新数据类型 — not-applying
- 权限模型：不变 — not-applying
- 审计：UI 改造无审计需求 — not-applying
- 失败可见性：沿用现有错误横幅与重试 — applied（复用）
- 兼容性：见 Q1；regular 路径零改动 — applied
- 无障碍/本地化：新 UI 文案沿用 `String(localized:)` — applied
