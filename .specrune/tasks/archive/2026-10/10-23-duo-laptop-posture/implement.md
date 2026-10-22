# Implement — Duo 半折笔记本模式

## 有序清单

1. [x] R0 探测：Duo 模拟器半折态（DeviceHub 切姿态），实测窗口 size class、safe area、
      有效高度（GeometryReader 诊断视图或现有 app 布局变化观察），结论写回 design.md。
      （结论：无系统信号，纯手动开关）
2. [x] 新建 `Views/Chat/LaptopModeContainer.swift`：折痕分隔线 + 底排快捷条；
      上下分区通过 SessionChatView 的 bottom safeAreaInset dock 设 minHeight（约 45% 屏高）实现，
      Timeline 自然被限制在折痕上方（卡片不跨线）。
3. [x] 下屏 Reactive Deck：输入框常驻（复用 ChatComposerDock）、审批卡复用现有
      SessionInteractionDock（pending 时已在输入框上方显示，卡片自带允许/拒绝操作）；
      底排快捷（打断/继续，复用 chat.interrupt / chat.send）。未做：审批卡下滑收起手势
      （现有卡片为内联布局，改为覆盖层收益低）；「更多」入口（工具栏 ellipsis 已有）。
4. [x] 上屏可滚动 + 「回到底部」按钮：ChatTimelineView 已有 chat.timeline.bottom 机制，直接复用。
5. [x] 挂载点：SessionChatView 会话菜单（ellipsis）内「笔记本模式」Toggle，
      @AppStorage("laptopModeEnabled") 持久化；几何自动触发按 R0 结论弃用。
6. [x] 验证：构建通过（Duo 模拟器 destination，exit 0）、`cd ios && swift test` 247 测试全过；
      半折态人工走查（验收 2-4）与普通 iPhone 回归留给用户在 DeviceHub 切姿态确认。

## 验证命令

```bash
xcodebuild build -project "ios/Agents Anywhere/Agents Anywhere.xcodeproj" -scheme "Agents Anywhere" \
  -destination 'platform=iOS Simulator,id=<Duo-UDID>'
cd ios && swift test
```

## 风险文件 / 回滚点

- 挂载点改动：CompactChatShellView / SessionChatView（各一处小改）
- 新增 LaptopModeContainer 独立，可整体删除回滚
- 风险：半折几何与模拟器表现的偏差（R0 后修正）；审批卡覆盖层与键盘的层级冲突

## pre-start 检查

- [x] design.md 含备选方案节
- [x] PRD 决策齐（输入优先 / 可滚动）
- [ ] implement/check manifest 加 context
