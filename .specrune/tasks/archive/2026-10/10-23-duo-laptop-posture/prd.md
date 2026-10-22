# iPhone Duo 半折形态：上屏对话下屏操作的笔记本模式

## Goal

Duo 半折立在桌上（类 3DS/笔记本姿势）时：上屏只读对话流，下屏输入与操作区；与现有展开双栏（regular）、合盖两 Tab（compact）形成三形态一套状态。

## Confirmed Facts（技术侦察）

- **iOS 27.1 SDK 无公开折叠 API**：SwiftUI/UIKit 全部 swiftinterface 与头文件中 posture/fold/fascia/foldingState 等符号均为零命中。半折状态只能通过窗口几何间接感知（窗口有效高度骤减、safe area 变化、size class 保持 compact）。
- **探测是第一步**：Duo 模拟器 + DeviceHub 可切半折姿态；需要在半折时实测 GeometryReader/size class/safe area 的真实表现（也可能系统在半折时只渲染上半屏并自带输入区——行为未知）。
- 现有基础：ChatShellView 已按 horizontalSizeClass 分流 compact/regular；会话状态层与 UI 分离，形态切换状态保持已被上一个任务验证。
- Duo 内屏 2007×2853（半折后每半 ≈ 2007×1426 逻辑 669×475pt）。

## Requirements

- **R0 探测实验（前置）**：Duo 模拟器半折态实测窗口几何、size class、safe area、系统是否自带键盘区；结论决定后续设计走向。
- **R1 半折布局**：上屏 = 当前会话 Timeline 只读流（新消息自动滚动，卡片不跨折痕线）；下屏 = 操作区。
- **R2 下屏操作区**：输入框 + 上下文操作卡（有待审批时显示审批卡：允许/拒绝大按钮；空闲时显示快捷操作：打断/继续/模型切换入口）。
- **R3 触发机制**：自动感知半折（几何检测，以 R0 结论为准）+ 手动开关兜底（布局菜单项「笔记本模式」）。
- **R4 状态无缝**：三形态（合盖/半折/展开）切换时选中会话、草稿、WebSocket 不断。
- **R5 非折叠设备不受影响**：普通 iPhone 无半折几何，行为与现状一致。

## Acceptance Criteria

- [ ] R0 探测报告写入 design.md（半折时的几何/size class/safe area 实测数据）
- [ ] Duo 模拟器半折态：上屏显示当前会话 Timeline，下屏显示输入与操作区
- [ ] 有待审批会话：下屏出现审批卡，点击可完成批准/拒绝
- [ ] 合盖→半折→展开三形态来回切换：选中会话与连接保持
- [ ] 普通 iPhone 模拟器行为与现状一致（无回归）
- [ ] 构建通过、现有测试通过

## Out of Scope

- 外屏（合盖）形态调整（已定型两 Tab）
- 终端/文件管理在下屏的适配（后续）
- 真机验证（用户决定暂不重装真机）

## Open Questions

- ~~Q2 下屏优先级~~ **已定（2026-10-23）**：输入优先——输入框常驻主位，审批卡出现时覆盖上层、可划走。
- ~~Q3 上屏交互~~ **已定（2026-10-23）**：可滚动翻历史 + 「回到底部」按钮。
- Q1 触发机制的自动检测可行性：依赖 R0 探测结论，双轨设计（几何检测自动 + 菜单开关手动兜底）。

## Implicit requirements sweep

- 崩溃数据保全：无新增持久化 — not-applying
- 敏感数据：无 — not-applying
- 权限：无 — not-applying
- 审计：无 — not-applying
- 失败可见性：沿用现有错误横幅 — applied（复用）
- 兼容性：非折叠 iPhone 零影响（R5）；regular/compact 路径不动 — applied
- 无障碍/本地化：新 UI 沿用 String(localized:) — applied
