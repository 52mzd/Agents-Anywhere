# Implement — compact 两 Tab 会话区

## 有序清单

1. [x] 探测 Xcode scheme / target 名与可用的 headless 构建命令（`xcodebuild -list`）。
2. [x] 新建 `Views/ChatShell/CompactSessionListView.swift`：会话列表（复用 `ChatSidebarSession` 与 pinned→recent 排序、状态角标、未读点），toolbar 新建入口。
3. [x] 新建 `Views/ChatShell/CompactMoreView.swift`：账号卡（含服务器地址）、设备入口（`sidebarDevices` 数据）、设置入口、退出登录。
4. [x] 新建 `Views/ChatShell/CompactChatShellView.swift`：TabView 两 Tab + 会话详情 push（selection 驱动）+ 新建会话 sheet（`NewSessionView` 复用）。
5. [x] 改 `ChatShellView.swift`：compact 分支替换为 `CompactChatShellView`，regular 分支不动；selection 双向兼容。
6. [ ] 验证：iPhone 模拟器（compact）Tab 布局与四屏 mockup 一致；iPad 模拟器（regular）双栏不回归；形态切换选中会话保持。

## 验证命令

```bash
cd ios/"Agents Anywhere"
xcodebuild -list                                    # step 1 确认 scheme
xcodebuild build -scheme <scheme> -destination 'generic/platform=iOS Simulator'
# 测试（存在 ios/Tests）：
xcodebuild test -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 风险文件 / 回滚点

- `Views/ChatShell/ChatShellView.swift` 是唯一改动的既有文件，回滚点：compact 分支恢复 `sidebarLayout(.drawer)`。
- 新增三个视图文件独立无牵连，可整体删除回滚。
- 风险：SessionChatView 以 selection 驱动 push 时的导航栈管理（现有 drawer 模式是内容区切换而非 push），需在 step 4 对齐现有 `openSession` 行为，不新造路由状态。

## pre-start 检查

- [x] design.md 含备选方案节
- [x] PRD Q1 已定案
- [ ] implement/check manifest 已加 context（specrune task add-context）
