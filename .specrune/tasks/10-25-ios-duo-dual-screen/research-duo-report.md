# iPhone Duo 双屏开发调研报告

> 调研日期：2026-10-25 · 用途：Agents Anywhere iOS 客户端双屏功能前期调研
> 结论已支撑任务 `10-25-ios-duo-dual-screen` 的规划

## 一句话结论

**iPhone Duo 展开后不是两块独立屏幕，而是一整块 7.6 英寸连续内屏 + 中间一条"折叠区"（fold region）**。所谓"3DS 上下双屏"不是两个 window、也不是两个 display，而是一种**布局形态**：苹果为此专门提供了 `ArrangementView`（SwiftUI）/ `UIArrangementViewController`（UIKit）容器，竖屏时自动上下分屏，半折叠（笔记本姿态）时自动把两个视图分到铰链两侧——这正是目标模式。设备 2026-10-23 已上市，SDK 为 iOS 27.1（随 Xcode 27.1）。

---

## 1. 设备与 SDK 事实

| 项目 | 内容 |
|---|---|
| 设备形态 | 外屏 5.4"（合盖用）+ 内屏 7.6"（展开用），**相同宽高比**，中间铰链，各有一颗前摄（内摄为屏下、激活才可见） |
| 发布/上市 | 2026-09-09 发布，2026-10-23 上市（iOS 27.1 出厂），10-30 扩展至 28 个国家 |
| SDK | iOS 27.1 SDK，随 Xcode 27.1（含 iPhone Duo 模拟器，在 Device Hub 中，控制按钮可开合/折叠/旋转） |
| 尺寸类 | 外屏 = compact width（和普通 iPhone 一样）；内屏 = regular width + regular height（类 iPad） |
| 强制要求 | 用 iOS 27 SDK 构建必须已迁移 **UIScene 生命周期**，否则应用不启动 |
| 本机环境 | 开发机已装 Xcode 27.1 (27A9275) + iOS 27.1 SDK + iPhone Duo 模拟器（2026-10-25 核查） |

## 2. "上下双屏、两边不同内容"的三种实现路径

核心 API 是 **Arrangement View（编排视图）**：装一个 primary + 一个 secondary 视图，按屏幕尺寸、方向、保留区自动组织，有 split 和 overlay 两种样式。

| 场景（想要的效果） | 用法 | 行为 |
|---|---|---|
| **竖屏完全展开，上下两块内容** | `ArrangementView` 默认 split 样式 | 容器"高大于宽"时**自动上下堆叠，primary 在上**——就是 3DS 布局 |
| **半折叠立起来（笔记本姿态），铰链上下各一块** | split 或 overlay 均可，overlay 更贴切 | 部分展开时折叠区把内屏切成两个可用区域；overlay 会**自动把 primary 放下半、secondary 放上半**，中间折叠带被避开 |
| 只想左右分（横屏） | `.arrangementViewStyle(.split.axes(.horizontal))` | 宽大于高时左右分；限制轴不匹配时只显示 primary |

SwiftUI 最小示例（上下双屏）：

```swift
ArrangementView {
    TopScreenContent()      // 上屏：如消息流
} secondary: {
    BottomScreenContent()   // 下屏：如输入面板
}
// 默认 .automatic 即 split；竖屏自动上下分，折叠区自动避开
```

UIKit 等价：

```swift
let vc = UIArrangementViewController()
vc.setViewController(topVC, for: .primary)
vc.setViewController(bottomVC, for: .secondary)
vc.updateArrangement(.split)  // 可选 .overlay
```

配合的关键 API：

- **`reservedRegions(kind:options:)`**（SwiftUI 在 `GeometryProxy` 上，UIKit 在 `UIView` 上）——查询保留区，分 `division`（折叠分割线）和 `occlusion`（摄像头遮挡）两类，带 `frame` 和 `isActive`。**铰链只有半折叠时 division 才 active**，全展平时 inactive 且宽度为零，所以每次都要现查、别缓存。
- **`onHingeChange`** / **`UIHingeInteraction`**——实时拿铰链角度和状态（closed / partiallyOpen / fullyOpen）。苹果明确说：这个只用来做**交互效果**（如折叠角度驱动视觉），**布局一律走 ArrangementView + reserved regions**。

### iOS 27.1 API 速查表

| 功能 | SwiftUI | UIKit/AVFoundation/AVKit | 可用性 |
|---|---|---|---|
| 双 pane 布局 | `ArrangementView`、`arrangementViewStyle(_:)` | `UIArrangementViewController`、`updateArrangement(_:animated:)` | 27.1 beta |
| Split 尺寸 | `splitArrangementLayoutRatio(_:)`、`splitArrangementFixedLayoutSize` | `UISplitArrangement` 尺寸区间 | 27.1 beta |
| 折叠/遮挡区 | `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` | `UIView.reservedRegions(kind:options:)` | 27.1 beta |
| 竖向 bar 退出 | `toolbarVerticalBehavior(_:)` | `preferredVerticalBarBehavior` | 27.1 beta |
| 竖向 bar 侧边 | `toolbarVerticalEdge` 环境值 | `verticalBarEdge` trait | 27.1 beta |
| 工具条目轴向 | `axisBehavior(_:)` | `UIBarButtonItem.axisBehavior` | 27.1 beta |
| 溢出顺序 | `visibilityPriority(_:)`、`ToolbarOverflowMenu` | `UIBarButtonItem.visibilityPriority` | 27.0，非 Duo 专属 |
| 铰链状态 | `onHingeChange(isEnabled:_:)` | `UIHingeInteraction`、`UIHinge` | 27.1 beta |
| 相机方向 | —（无 SwiftUI 专属） | `AVCaptureDeviceDirectionCoordinator`（AVKit） | 27.1 beta |
| 独立前摄 | — | `.builtInOuterUltraWideCamera`、`.builtInInnerUltraWideCamera` | 27.1 beta |
| 外屏内容 | `sceneAccessory(content:)` + `CameraCaptureAccessory` | `UISceneAccessory.cameraCapture(...)`、`registerSceneAccessory` | 27.0/27.1 beta |

## 3. 重要的坑（Apple 明确禁止/规则）

1. **不要判断 idiom 和方向**：布局只看 `horizontalSizeClass` / `verticalSizeClass` 和容器 bounds，禁用 `userInterfaceIdiom`、`UIInterfaceOrientation`。
2. **`UIScreen.main` 歧义**：双屏设备上会被废弃，改用 window scene / trait collection。
3. **不要自建 bar**：`UIToolbar`/`UINavigationBar`/`UITabBar` 裸拼的 bar 不会获得竖向 bar 能力；要用导航容器 + `toolbar` 修饰符，系统才会把工具栏竖排到侧边（外屏和内屏横屏时 bar 在侧面）。
4. **图标规则**：竖排 bar 里的条目必须有 symbol，只有文字的按钮会留在横条里。每个条目 title + symbol 都给。
5. **SDK 分层行为**：不重编译也能跑（兼容布局，不能铺满屏）；iOS 27 SDK 构建延伸到状态栏左侧；**只有 iOS 27.1 SDK 构建才铺满全屏**并获得竖向 bar。
6. **多窗口只在内屏**：外屏不能开新 scene，请求 scene 要处理失败，推荐 `UIWindowScene.ActivationAction`（不可用时自动隐藏）。
7. **Split View 无法退出**：所有 App 都会参与内屏 50/50 分屏，必须测试该尺寸。
8. **ArrangementView 摆放**：导航容器（NavigationStack/NavigationSplitView/TabView）要包在 arrangement 外面，不要塞进去；也不要放进 list/scroll view。
9. **模拟器无相机**：相机流、方向协调器、capture accessory 只能真机测。

## 4. 相机专项（本次功能不涉及，留档）

- 旧前摄 API 不用改：`.front` 位置返回的是**虚拟前摄**（系统在两颗物理前摄间自动切换，1080p60，无深度）。
- 需要 4K 自拍或深度时用独立设备类型：外摄最高 4K/120fps，内摄（屏下）1080p60。
- `AVCaptureDeviceDirectionCoordinator`（AVKit）：按视图报告哪些相机朝前/朝后，开合翻转时方向可能变。
- **Camera capture accessory**：内屏拍后摄时，系统允许在外屏显示内容给被拍者看——系统决定何时出现/收回，别放关键内容，模拟器测不了。

## 5. 与现有 iPad 适配的关系

真正新的东西只有一小圈：ArrangementView、reserved regions、竖向 bar、铰链 API、方向感知相机、capture accessory、iPhone 上的多窗口。**其余全是既有的自适应布局纪律**（size class、safe area、可缩放）套用到新形状上。苹果原话：已经在 iPad/Mac 上良好缩放、或已适配 iPhone Mirroring 缩放的 App，"离支持 iPhone Duo 已经很近了"。

| 领域 | iPad/Mac 经验可复用 | Duo 上的新差异 |
|---|---|---|
| 尺寸类 | size class 驱动布局照旧 | 外屏 compact；内屏 regular×regular |
| 方向 | 用 size class 不用方向检查 | 支持的方向锁不住内屏，App 会缩放 |
| 全屏 | `UIRequiresFullScreen` 仍被尊重 | 开合时仍会 resize |
| 双 pane | ArrangementView 也适用 iPadOS | 自动绕折叠带 |
| 折叠/相机 | 全新 | division + 两个 occlusion |
| bar | 标准导航容器 | 竖向 bar + 图标规则 |
| 前摄 | 现有 discovery 代码可用 | 虚拟前摄 + 方向协调器 |
| 多窗口 | scene 代码可复用 | 仅内屏可开新窗口 |

## 6. 官方学习资源

- Technology Overview：**"Preparing your app for iPhone Duo"**（入口文档）
- HIG：**"Designing for iPhone Duo"**
- 六场 Tech Talks：Design / Prepare / Raise the bar（竖向 bar）/ Strike a pose（arrangement + reserved regions）/ Multiple displays and scenes / Camera
- 相关 WWDC：WWDC25 "Make your UIKit app more flexible"、WWDC26 "Modernize your UIKit app"

## 参考资料

- [Apple HIG — Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [ecorpIT — iPhone Duo SDK: New iOS 27.1 APIs and Xcode 27.1 Status](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/)（2026-09-18 更新，API 速查与时间线的主要来源）
- [Codelaby/IphoneDuo（GitHub 示例仓库）](https://github.com/Codelaby/IphoneDuo)
- [swiftprogramming.com — How to build apps for iPhone Duo with SwiftUI](https://swiftprogramming.com/apps-swiftui-iphone-duo/)
- [Apple Magazine — Developers Bring iPhone Duo Apps Beyond the Bigger Screen](https://applemagazine.com/developers-iphone-duo-apps/)

**调研未验证项**：GitHub 示例仓库 README 两次抓取超时，未核对示例代码细节；苹果官方 Technology Overview 为 JS 渲染页，要点转引自 ecorpIT 的逐条核对；iOS 27.1 beta 符号名以正式版文档为准，本机 Xcode 27.1 (27A9275) 已可交叉验证。
