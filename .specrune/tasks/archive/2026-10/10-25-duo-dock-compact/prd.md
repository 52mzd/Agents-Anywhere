# Duo 双屏输入区视觉精简

## Goal

半折叠双屏（输入框浮层贴键盘顶）时，dock + 键盘叠加会遮挡上屏消息流
下部视线。在不改键盘本身（系统不可控）的前提下，降低 dock 对上屏的
视觉遮挡。

## Confirmed Facts（代码证据，2026-10-25）

- 当前 dock 高度构成（ChatComposer.swift:84-86）：
  padding.top 8 + 输入行(≈52pt) + padding.bottom 10 ≈ 70pt（无附件时），
  外加毛玻璃背景（.glassEffect(.regular)）。
- 多行输入时 editor 可长到 maximumEditorHeight（双屏当前传
  min(160, max(72, 屏高*0.30))，约 160pt）——多行是遮挡大头。
- 附件托盘（attachmentTray）有附件时再加一行。
- 遮挡主体是键盘本体（~350pt 越过中线），dock 只占小头；
  dock 可压缩空间：padding 18pt + 多行上限 + 附件行。
- dock 已是单行紧凑布局，无多余工具行。

## Requirements（用户已定：紧凑 + 透明组合）

1. 紧凑（仅 Duo 双屏 && `draft.isFocused` 聚焦时生效）：
   - dock 上下 padding 8/10 → 4/6；
   - `maximumEditorHeight` 聚焦时压到 72（单行档），多行仍可输入但上限低；
   - 附件托盘聚焦时隐藏，"+"按钮带数量角标（附件管理走选项面板，不变）。
2. 透明：聚焦时玻璃背景 `.regular` → `.clear`，消息流从 dock 下透出。
3. 失焦/非双屏：外观与现状逐字节一致。

## Acceptance Criteria

- [ ] 双屏聚焦：dock 明显变矮（至少省 18pt padding + 多行压缩）、背景更透
- [ ] 双屏失焦：恢复现有外观
- [ ] 非 Duo 设备：外观不变（普通聚焦也不变）
- [ ] 附件在聚焦时以角标计数，不占行高
- [ ] 构建 + swift test 通过

## Out of Scope

- 键盘高度（系统/输入法控制，App 无 API）
- 非 Duo 设备的 dock 外观

## Open Questions

（无）

## Coverage taxonomy

- Goal & scope: covered（紧凑+透明组合已定）
- Domain & data: covered（只动视觉层）
- Interaction & states: covered（聚焦/非聚焦状态已有）
- Non-functional quality: covered（纯视觉）
- Integration & dependencies: covered（复用 ChatComposer 参数）
- Edge cases: covered（附件/多行是仅有的可变高度源）
- Constraints: covered（幅度以代码常量为准，真机验收）
- Completion signals: covered（验收标准可观察）

## Implicit requirements sweep

- 崩溃/数据：not-applying（纯视觉）
- 敏感数据/权限/审计：not-applying
- 失败可见性：not-applying（无失败路径）
- 兼容：applied（非 Duo 不受影响，双屏分支内改）
- 无障碍/本地化：applied（按钮标签保留，仅尺寸/间距变化）

## 结局（2026-10-25 深夜）

本任务方向被推翻：用户领悟到系统默认键盘避让（内容上推）已覆盖半折叠
场景，自建 arrangement 双屏与系统打架。紧凑/透明模式随双屏一起 revert
（透明化另因 Glass 无透明档位、if/else 背景切换重建子树丢焦点而不可行）。

演变成的最终修复（已提交、真机验收通过）：
1. 键盘弹出（视口高度骤减>60pt）→ 直接 position.scrollTo(bottom)
   （scrolling 状态机的 pendingBottomRequest 在键盘动荡期拒绝发令，
   模拟器日志实证）
2. defaultScrollAnchor(.sizeChanges) 从 .top 改 .bottom
3. 侧栏头部 ignoresSafeArea(.keyboard) 不随键盘上移
4. NativeComposerEditor 焦点异步化（updateUIView 同步 becomeFirstResponder
   在聚焦触发布局变化时主线程死循环，栈采样实证）
