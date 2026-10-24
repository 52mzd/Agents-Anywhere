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
- iOS 27.1 SDK **没有**任何折叠姿态/形态公开 API（UIKit 头文件已验证，
  2026-10 归档任务 `10-23-duo-laptop-posture` 的 R0 探测结论相同）。
  机型 id 是唯一可靠信号；上游 "never a device model" 规则在"折叠外屏
  与直板机 trait 完全等价"的场景下无法表达，属正当破例（使用处注释
  需说明）。
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
