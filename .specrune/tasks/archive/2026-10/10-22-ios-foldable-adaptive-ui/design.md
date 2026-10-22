# Design — compact 两 Tab 会话区

## 现状与改造点

`ChatShellView`（`Views/ChatShell/ChatShellView.swift`）已按 `horizontalSizeClass` 分流：

- regular → `SidebarDrawer(presentation: .nativeSidebar)`，双栏已存在，**零改动**
- compact → `SidebarDrawer(presentation: .drawer)`，本任务将其替换为两 Tab

## 结构

```text
ChatShellView
 ├─ regular：现有 sidebarLayout(.nativeSidebar)（不动）
 └─ compact：CompactChatShellView（新）
     └─ TabView
         ├─ Tab「会话」 NavigationStack
         │   ├─ root: CompactSessionListView（新，未归档会话 pinned→recent）
         │   └─ push: SessionChatView（复用，selection 驱动）
         │   └─ toolbar ✏️ → sheet: NewSessionView（复用）
         └─ Tab「更多」 NavigationStack
             ├─ root: CompactMoreView（新：账号卡 + 设备入口列表 + 设置/退出）
             └─ push: DeviceManagementView（复用）/ Settings
```

## 关键决策

1. **分流位置在 ChatShellView 内部**，不动 RootView 与登录流。`appState.chatSelection` 是两个形态共享的选中态：regular 侧栏选中、compact push 详情读同一个值，形态切换选中会话天然保持。
2. **列表数据复用**：`sidebarSessions`（pinned→recent 排序）与 `ChatSidebarSession` 模型直接复用；行视图新写（侧栏行嵌在 ChatSidebarView 内部，抽出会牵动大文件，不划算）。
3. **状态无缝由架构保证**：WebSocket/草稿/投影都在 `Repositories/Models` 层，Tab 与形态切换不触碰；验收项 4 以验证为主。
4. **drawer 分支保留不删**：`SidebarDrawer` 组件与 drawer 代码路径保留（组件可能他处引用），compact 分支不再调用；清理留给后续任务。
5. 外屏不提供终端入口（PRD out of scope）；附件维持会话详情内现有行为。

## 数据流与契约

- 无新 API、无 schema 变化、无持久化新增。Tab 选中态放 `@State`（进程内即可，重启恢复由现有会话恢复逻辑负责）。
- 文案沿用 `String(localized:)`，中文为主。

## 备选方案

- **保留抽屉、默认展开列表**：改动最小，但打开 App 仍先进「新会话」页，不满足"秒进会话区"的核心诉求，拒绝。
- **按设备型号只给折叠屏新 UI**：违反项目约定（ChatShellView 注释明确禁止设备型号/屏宽判断，只用系统 trait），且无法可靠识别外屏，拒绝。
- **等苹果折叠屏专属 API 再做**：交付无限期推迟，且 size class 方案在任何新 API 下都不作废，拒绝。

## 兼容与回滚

- regular 路径零改动，iPad 不受影响。
- compact 行为变化即产品决策 Q1，已确认。
- 回滚：恢复 ChatShellView compact 分支调用 `sidebarLayout(.drawer)` 即可，新视图文件独立、删除无牵连。
