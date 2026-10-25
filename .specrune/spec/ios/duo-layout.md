# Duo（折叠屏）机型判断与宽屏布局契约

来源：2026-10-24 "Duo 内屏横屏内容列宽度"五轮修复复盘。分支
`feat/ios/foldable-compact-tabs`（9eb1e23d / 53698fdc / 4cad46af）。

## 机型判断：`isDuoFoldableIPhone`

位置：`ios/Agents Anywhere/Agents Anywhere/Views/Chat/Composer/ChatControlMetrics.swift`

```swift
let isDuoFoldableIPhone: Bool = {
    #if targetEnvironment(simulator)
    ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"
    #else
    // utsname().machine == "iPhone19,4"
    #endif
}()
```

契约：
- **真机**读 `utsname().machine`；**模拟器**必须走
  `SIMULATOR_MODEL_IDENTIFIER`——模拟器的 machine 只返回宿主架构
  （arm64），机型判断永远 false，Duo 模拟器将无法复现折叠屏分支。
- ~~iOS 27.1 SDK 没有任何折叠姿态/形态公开 API~~（2026-10-25 修正：
  Xcode 27.1 (27A9275) SDK 实证，**UIKit 公开了完整的折叠 API**，此前
  "没有任何公开 API"的结论只对 SwiftUI 成立）。可用符号（头文件已验证，
  均 iOS 27.1+）：
  - `UIArrangementViewController`（`setViewController(_:for:)` /
    `updateArrangement(_:)`，primary/secondary 两个 placement）
  - `UISplitArrangement`（竖屏高>宽自动上下堆叠）/ `UIOverlayArrangement`
  - `UIHinge`（closed/partiallyOpen/fullyOpen + angle）、
    `UIHingeInteraction`（这就是"折叠姿态 API"）
  - `UIViewReservedRegion`（division=折叠带 / occlusion=摄像头遮挡，
    带 `isActive`，须现查不能缓存）
  - **SwiftUI 无对应符号**（swiftinterface 0 匹配；外部文章声称的
    SwiftUI `ArrangementView` 系 AI 辅助写作失实）。SwiftUI 接入用
    UIViewControllerRepresentable 包装，见
    `Views/Chat/DuoArrangementHost.swift`。
  机型 id 判断仍保留：它回答"这台设备是不是折叠屏"（布局分支启用条件），
  arrangement/hinge API 回答"屏幕当前怎么折"——两者职责不同，都要用。
- 新折叠机型落地时**只改这一个常量判断**，布局分支不动。

## 三层宽度约束（宽屏聊天内容）

聊天 detail 列的内容宽度由三层独立约束叠加，分居三个文件。宽屏
（detail 列 > 760pt，如 Duo 内屏横屏 951pt、隐藏侧栏）时三层全部生效，
文字列明显窄于输入框；列宽 < 760pt（竖屏 669pt、开侧栏 651pt）时均不
触发——**症状只在特定形态出现是条件性约束的直接特征**。

| # | 约束 | 文件 | Duo 值 | 其他机型 |
|---|------|------|--------|----------|
| 1 | 内容列上限 | `ChatPageContentColumn.swift` `.frame(maxWidth:)` | 2200 | 760 |
| 2 | ScrollView 系统阅读边距 | `ChatTimelineView.swift` `.contentMargins(.horizontal, 0, for: .scrollContent)` | 0（全局） | 系统默认 |
| 3 | composer/内容上限 | `ChatControlMetrics.maximumContentWidth` | 2000 | 780 |

已知取舍：约束 2 是全局的——普通机型竖屏文字边距从 ~32-40pt 变为
~16-20pt（列 padding 兜底），18 Pro 模拟器人工验收通过（2026-10-24）。

## 错误模式（会再犯的）

- **逐层猜限宽**：修掉一层还有下一层；正确动作是
  `grep -rn "maxWidth: [0-9]\|contentMargins\|maximumContentWidth" --include='*.swift' ios/`
  全量穷举（别 head 截断——第一次就是被 head -15 吞掉了 760 那行）。
- **用 padding/offset 精确平移 SwiftUI 内容**：`contentMargins`、
  `padding` 与 safe area 叠加后偏移非线性（实测 margins 0/16/36 →
  实际 0/16/74pt）；`offset` 是纯平移但会裁掉溢出侧、每行可视文字变少。
  宽度问题的正解是找到并修改约束本身，不是在其外围补偿。
- **双产物目录**：`Debug-iphonesimulator` 与 `Debug-iphoneos` 独立；
  只为真机构建的改动在模拟器上不存在。换环境复现前先确认构建产物。
- **用 `verticalSizeClass == .compact` 判断"横屏矮空间"**：Duo 横屏展开
  高 669pt 是 regular（同 iPad），判断永不成立——浮层面板照常 240 高、
  顶部顶进消息流标题栏玻璃下（2026-10-26 真机翻车一轮）。尺寸类看不见
  "键盘要吃掉大半高度"这件事；矮空间判断用实测几何：面板高度 =
  `min(240, 可视高度 − dock 实测高度 − 60)`（SessionChatView 传
  `geometry.size.height`，dock 用 onGeometryChange 采自身高度）。
- **SwiftUI 手势只在不透明内容上命中**：HStack 中间的 `Spacer` 空白区
  不参与 DragGesture 命中，手势会缩到角落文字处。挂手势前补
  `.contentShape(Rectangle())`（指令面板标题行整行可拖，2026-10-26）。

## 双栏侧栏顶部偏移

`SidebarDrawer.swift` `SidebarDrawerNativeSidebar.topLift`：
竖屏（safe area top ≥ 40pt）上移 -56pt（抵消 Liquid Glass 容器额外顶部
inset ~21pt + 竖屏收紧 35pt，实测验收值）；横屏不下移为负——固定上移
会把 logo 推出屏幕（横屏改为 +14pt 微调）。这些是测量值不是推导值，
调整前先截图量化。

## 表格/滚动内容的视口宽度（2026-10-24 表格修复，b7d1d4f7）

横向 `ScrollView` 给内容的宽度提案是 **nil**（内容可无限宽），布局期
从 proposal/bounds 都拿不到视口宽。任何需要"视口宽"做自适应的滚动
内容，只能用 `onGeometryChange` 从 ScrollView 自身 frame 发布进
`@State` 再传入布局（见 `ChatMarkdownTable.viewportWidth`）。

表格列宽契约：列宽 = clamp(单行理想宽, 76, min(260, max(76, 视口/列数)))，
表格窄于容器时富余均分拉伸（拉伸阶段不设上限），宽于容器保持横向滚动。

## 文字断行（已调查，非 bug，别再追）

SwiftUI `Text` 对 CJK+西文混排的断行与 CoreText 理想排版存在每行
±1~2 字的确定性偏差（字体回退与行尾计算差异）。同宽度下断点确定性
复现（旋转实验验证），无缓存泄漏、Textual 无责、上游无同款报告。
用户观感差异多来自段落内半角字符占比（半角 ≈9pt vs 中文 17pt，同宽
度行字符数差可达 12）。

**判别手法（下次直接用）**：

1. 旋转实验分流：横→竖→横断点**复原** = 确定性排版（平台行为，非
   缓存 bug）；断点**变化** = 布局固化在过渡宽度（真 bug，查缓存链）。
2. CoreText 权威复算（`swift /tmp/wrap.swift`，命令行即可跑）：

```swift
import CoreText
// width = 布局日志拿到的块提案宽度（如 803）
let attr = NSAttributedString(string: 段落原文,
    attributes: [kCTFontAttributeName as NSAttributedString.Key:
        CTFontCreateWithName("PingFangSC-Regular" as CFString, 17, nil)])
let setter = CTFramesetterCreateWithAttributedString(attr)
let frame = CTFramesetterCreateFrame(setter, CFRange(),
    CGPath(rect: CGRect(x: 0, y: 0, width: 803, height: 10000), transform: nil), nil)
let line = (CTFrameGetLines(frame) as! [CTLine])[0]
// CTLineGetStringRange + CTLineGetTypographicBounds → 第一行尾字与宽度
```

3. 块提案宽度用临时布局日志拿（`MarkdownBlockLayout.sizeThatFits`
   打 proposal），日志代码带 `AA-DIAG:` 标记，完事 grep 清理。

## 双屏（半折叠）契约（2026-10-25 任务 10-25-ios-duo-dual-screen）

- 布局：`DuoArrangementHost`（UIKit 桥）+ `.split` 最简配置；**不要**给
  arrangement 加 axes/viewProperties（真机实测 primary 会被挤成窄条）。
- 输入 dock 永远做浮层 + `keyboardLayoutGuide` 锚定，**不要**放进 pane
  （pane 布局被 arrangement 截断，键盘下 dock 跳位）；
  **不要**用 keyboard frame 通知算抬升量（lift 实测波动 395↔495）。
- dock 浮层容器必须 `hitTest` 穿透（否则消息流无法滑动）；
  hosting 必须 `[.intrinsicContentSize]`（否则指令面板被裁）。
- 视图实例稳定 > 一切：pane↔浮层切换会重建 SwiftUI 实例、丢输入焦点。
- 外层 `.ignoresSafeArea(.keyboard)` 必须加（否则键盘压缩容器重排 pane）。

## iOS 27.1 arrangement API 的 Swift 调用形态（2026-10-25 SDK 实证）

SwiftUI **无**任何 arrangement/hinge 公开符号（swiftinterface 0 匹配；外部
文章声称的 `ArrangementView` 系 AI 写作失实）。全部走 UIKit，Swift 化名与
ObjC 头文件差异如下（`@available(iOS 27.1, *)`）：

```swift
let vc = UIArrangementViewController()
vc.setViewController(host, for: .primary)      // NS_REFINED_FOR_SWIFT: forPlacement → for
vc.updateArrangement(.split)                    // UISplitArrangement.split 静态成员
// ❌ splitArrangement() 不存在（头文件 +splitArrangement 的 Swift 化）
// ❌ UISplitArrangement.ViewProperties() 无公开 init：
// ✅ var props = split.defaultViewProperties   // 拷贝默认值再改
```

`UIHostingController.sizingOptions` 赋值不能在 `[a, b]` 数组循环里做——
数组把类型擦成 `UIViewController`，编译报"no member"，必须逐个写。

## 真机构建/部署工作流（2026-10-25）

```bash
# Xcode 开着会锁 build.db，用独立 derivedDataPath：
xcodebuild -project "Agents Anywhere.xcodeproj" -scheme "Agents Anywhere" \
  -destination 'id=<UDID>' -allowProvisioningUpdates \
  -derivedDataPath /tmp/duo_dd_dev build
xcrun devicectl device install app --device <UDID> \
  "/tmp/duo_dd_dev/Build/Products/Debug-iphoneos/Agents Anywhere.app"
xcrun devicectl device process launch --device <UDID> com.dae.sr1023
```

- **bundle id 两套**：真机构建 `com.dae.sr1023`（签名配置），模拟器构建
  `com.agentsanywhere.app`——launch 时用错会 NotFound。
- 构建脚本必须以 `BUILD SUCCEEDED` 判定后再 install；grep 到 error 行返回
  0 会让 `&&` 链继续装旧产物（本轮实测踩坑）。
- 真机锁屏时 `devicectl launch` 报 `BSErrorCodeDescription = Locked`，
  解锁后手动打开或重试。

## 键盘跟随（2026-10-25 真机验收）

半折叠/展开下点输入框，消息流要滚到最新：
- 视口高度骤减（onGeometryChange，键盘 inset 不进 GeometryProxy.safeAreaInsets）
  直接 `position.scrollTo(edge: .bottom)`——**不要**走 scrolling.requestBottom
  状态机：pendingBottomRequest 计算属性在键盘布局动荡期因 viewport 样本
  失效返回 nil（begin 拿不到请求，日志实证）。
- 侧栏/非输入列控件用 `.ignoresSafeArea(.keyboard)` 固定。
- updateUIView 内**禁止同步** becomeFirstResponder（聚焦触发布局变化时
  与键盘 reload 同步重入，主线程假死；异步派发即可）。
- 根本心法：系统键盘避让本身就是"内容上推"设计，不要自建容器对抗。


## 输入行（ComposerLayout）多按钮排布契约（2026-10-26）

`Composer/ComposerLayout.swift` 是自定义 Layout，子视图按**声明顺序**定位：

| 索引 | 内容 | 位置 | 条件 |
|---|---|---|---|
| 0 | +（附件/选项） | 左缘 | 恒定 |
| 1 | 编辑器 | 中间 | 恒定 |
| 2 | 发送/停止 | 右缘 | 恒定 |
| 3 | 指令 ⌘ | 发送左一格 | `showsCommands` |
| 4 | 收起键盘 ⌄ | 指令左一格 | `draft.isFocused` |

- **声明顺序即视觉顺序**：往输入行加按钮时，在 ChatComposer 闭包里
  按目标位置声明；紧邻发送键的位置留给高频主操作（误触考量，
  2026-10-26 收起键曾放发送旁被用户要求挪到指令左侧）。
- `editorWidth` 的 `extra = (count-3) × touchTarget`：新增条件按钮
  自动收窄编辑器，无需逐处改宽度。
- 条件按钮组合（3/4/5 个子视图）由 count 判断放置，无法感知身份——
  无指令的 runtime 下收起键会落在发送旁（已知边缘，暂不修）。
- ChatComposerDock 的指令面板是**浮层**（overlay + dockHeight 偏移），
  不占布局流；新增弹出类 UI 照此模式（见 guides 铁律 16）。
