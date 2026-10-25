# 实现计划：iOS 客户端 iPhone Duo 上下双屏

## 完成情况（2026-10-25）

- [x] 步骤 1-3：抽取 `timelinePane` / `bottomDock`，新增
      `DuoArrangementHost.swift`（实现期修正：SwiftUI 无 ArrangementView，
      改用 UIViewControllerRepresentable 包 UIKit API，见 design.md 修正节），
      `SessionChatView` 接入 `DuoArrangementGate.embedIfSupported`
      （启用条件 `isDuoFoldableIPhone && #available(iOS 27.1, *)`）。
- [x] 步骤 4：`xcodebuild build`（iPhone Simulator）**BUILD SUCCEEDED**
- [x] 步骤 6：`swift test --package-path ios` **247 tests passed**
- [x] Duo 模拟器：app 安装、启动、持续运行无崩溃日志
      （pid 稳定，launchctl 在列，log show 无 crash/exception）
- [ ] 步骤 5 视觉清单 **未完成**：headless 模拟器帧缓冲不渲染（截图全黑，
      Device Hub 需人工开窗）；且无登录凭据进不了 SessionChatView。
      剩余项需 GUI 人工验证：完全展开竖屏上下分区 / 半折叠两侧分区 /
      键盘弹起 / 开合状态保持 / Split View / 26.x 回退对比。
- 修正记录：`.specrune/spec/ios/duo-layout.md` 中"iOS 27.1 SDK 无折叠
  姿态公开 API"的旧结论已修正（UIKit API 真实存在，仅 SwiftUI 缺席）。


- [x] Xcode 27.1 + iOS 27.1 SDK 已装（2026-10-25 核查）
- [ ] `xcrun simctl list devicetypes | grep Duo` 确认模拟器设备类型可用

## 步骤

1. **抽取子树**
   - 在 `SessionChatView.swift` 中把 `safeAreaInset(edge:.bottom)` 内的
     `SessionInteractionDock + ChatComposerDock` 组合抽为私有子视图
     `ChatBottomDock`（同文件或 Components），保证单屏路径行为不变。
   - Timeline 分支同样抽为可复用子结构 `ChatTimelinePane`。

2. **新增 `Views/Chat/DuoArrangementHost.swift`**
   - `@ViewBuilder` 适配器：`#available(iOS 27.1, *)` 时返回
     `ArrangementView { timeline } secondary: { dock }`（默认 split 样式）；
     否则返回 `timeline.safeAreaInset(edge:.bottom) { dock }`。
   - Composer 高度上限 `min(160, max(72, geometry.size.height * 0.30))` 的
     geometry 来源改为各自 pane 内的 GeometryReader（避免引用全屏高度）。

3. **SessionChatView 接入**
   - body 中 timeline+dock 部分替换为 `DuoArrangementHost`；
     toolbar / sheet / overlay / toast 层保持在外层不动。

4. **构建与静态检查**
   - `xcodebuild -project ... -scheme ... -destination 'generic/platform=iOS Simulator' build`
     （确认 scheme 名后替换；沿用仓库 ios/scripts 既有构建脚本，如有）。

5. **iPhone Duo 模拟器验证**（逐项记录截图或结果）
   - [ ] 完全展开竖屏：上=Timeline、下=Composer，中缝无内容被折叠带遮挡
   - [ ] 半折叠笔记本姿态：两区域自动分居铰链两侧
   - [ ] 合盖（外屏）：现有 compact 单屏布局不变
   - [ ] Composer 聚焦弹键盘：下屏布局不破、上屏 Timeline 不跳动
   - [ ] 开合往返：草稿文本、已加载历史、滚动位置保持
   - [ ] 普通iPhone 27.1 模拟器：无铰链设备上行为可接受（否则触发 design.md
         contingency：收紧启用条件）
   - [ ] Split View 50/50：布局不破
   - [ ] 26.x 模拟器（如 iPhone + iOS 26.5 runtime）：走回退路径，与现状一致

6. **回归**
   - `cd ios && 现有测试命令`（查 ios/scripts 与 AGENTS.md 指引，iOS 无 CI，
     本地 test 必跑）

## 风险文件 / 回滚点

- 主要改动：`ios/Agents Anywhere/Agents Anywhere/Views/Chat/SessionChatView.swift`
- 新增：`ios/Agents Anywhere/Agents Anywhere/Views/Chat/DuoArrangementHost.swift`
- 回滚：单 commit revert 即可，无数据/契约迁移。

## 验证命令

```bash
xcodebuild -project "ios/Agents Anywhere/Agents Anywhere.xcodeproj" \
  -list   # 确认 scheme
xcrun simctl list devicetypes | grep -i duo
# 构建与测试命令以 -list 结果和 ios/scripts 为准
```

## 真机迭代复盘（2026-10-25 下午，最终停在干净基线）

多轮真机迭代后代码回到 git 基线（SessionChatView/ChatTimelineView 原样，
DuoArrangementHost/DuoHinge 均已删除）。已验证可用的结论与失败教训：

**成功过的**：
- UIArrangementViewController 双屏容器在模拟器半折叠态视觉正确
  （上消息流/下输入/折叠带空白，截图量化验证过）
- 真机 UIHingeInteraction 回调正常（hidden 视图不激活 interaction，
  必须用 1x1 透明视图）
- 铰链监听挂在 arrangement VC 自身 view 上可避免切形态后收不到事件

**失败的（三次系统性失败，同一根源）**：
1. arrangement 容器内键盘避让：pane 按 intrinsic 收缩（host=119=dock 高），
   手动 padding 抬升与监测视图形成反馈循环（kb 值振荡）
2. 单屏 + ignoresSafeArea(.keyboard)：半折叠系统键盘变高，dock 被推过中线
3. 单屏内 frame+clipped 裁剪视口：0.5 系数时只显示半屏，1.0 系数时内容
   延伸进下屏——SwiftUI 视图绘制延伸无视 frame/clipped/safeArea 常规语义，
   且真机反馈随版本互相矛盾（测量链本身也被裁剪污染，H=186/win=268 数据
   无法自洽）

**下一步建议**（未验证）：放弃在 SwiftUI 布局层对抗，改纯 UIKit：
SessionChatView 的双屏形态整体交给 UIArrangementViewController + 两个
UIHostingController，键盘避让交给 UIKit keyboardLayoutGuide；或等苹果
SwiftUI 原生 API（当前 SDK 无）。

## 最终方案（2026-10-25 17:44 真机验收通过）

多轮真机迭代收敛到三层结构（`Views/Chat/DuoArrangementHost.swift`）：

1. **布局容器**：半折叠（UIHinge partiallyOpen）时挂 `UIArrangementViewController`
   （`.split` 最简配置，不加 axes/viewProperties——真机实测显式配置反而坏布局）；
   primary=消息流，secondary=固定高度占位（`geo.size.height * 0.45`，维持上下分区）。
   外层 `.ignoresSafeArea(.keyboard)`（否则键盘把 pane 重排挤进上屏右侧）。
2. **输入 dock 恒为浮层**（`DuoKeyboardDock`）：UIHostingController 底边约束到
   `keyboardLayoutGuide.topAnchor`——键盘弹出精确贴键盘顶、收起贴屏幕底。
   dock 实例恒定（pane↔浮层切换会换实例丢焦点，键盘秒收回）。
   sizingOptions=[.intrinsicContentSize] + top 边界仅下限（指令建议面板向上生长）。
3. **事件穿透**（`DuoPassthroughView.hitTest`）：浮层容器空白区不拦截触摸，
   消息流滑动/点击从浮层下方透传。

铰链监听双挂（fallback 的 background + 容器 VC 自身 view），nil/unknown 防抖。
展开/合盖/横屏走原 safeAreaInset 单屏布局，逐字节不变。

**验证**：真机逐项通过（分区/键盘/打字/指令面板/消息流交互）；
`swift test` 247 全过；模拟器与真机构建通过。未做：Split View 50/50、
外屏长驻、横屏半折叠细节（后续按需）。
