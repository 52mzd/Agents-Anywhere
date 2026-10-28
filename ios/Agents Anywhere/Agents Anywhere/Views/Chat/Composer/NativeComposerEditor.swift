import SwiftUI
import UIKit

/// Keep this controller and the underlying UITextView alive while the glass
/// container changes layout. Never derive submission from SwiftUI .onSubmit.
@MainActor @Observable
final class ComposerEditorController {
    @ObservationIgnored weak var textView: ComposerTextView?
    @ObservationIgnored weak var draft: ComposerDraft?

    func finishEditing() {
        guard let textView else { return }
        textView.resignFirstResponder()
        synchronize()
    }

    /// Check native marked text before ending editing. unmarkText() only removes
    /// the mark; it cannot select the user's intended Chinese candidate.
    func committedTextForSend() async -> String? {
        guard let textView else { return draft?.isComposing == false ? draft?.text : nil }
        guard textView.markedTextRange == nil else { synchronize(); return nil }
        let originalDraft = draft
        textView.resignFirstResponder()
        await Task.yield()
        guard !Task.isCancelled, draft === originalDraft, textView.markedTextRange == nil else { return nil }
        synchronize()
        return textView.text ?? ""
    }

    func synchronize() {
        guard let textView, let draft, draft.isValid else { return }
        if draft.text != textView.text { draft.text = textView.text ?? "" }
        draft.isComposing = textView.markedTextRange != nil
        draft.isFocused = textView.isFirstResponder
    }
}

final class ComposerTextView: UITextView {
    var commandSend: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let send = UIKeyCommand(title: String(localized: "发送"), action: #selector(sendWithCommandReturn), input: "\r", modifierFlags: .command)
        send.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [send]
    }

    @objc private func sendWithCommandReturn() {
        // Leave provisional text and the candidate bar intact. Return/Space or
        // a candidate tap remains owned by the IME; this shortcut never guesses.
        guard markedTextRange == nil else { return }
        commandSend?()
    }
}

struct NativeComposerEditor: UIViewRepresentable {
    @Bindable var draft: ComposerDraft
    let controller: ComposerEditorController
    let maximumHeight: CGFloat
    let onCommandSend: () -> Void
    var onTextChange: ((String, Bool) -> Void)? = nil

    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.tintColor = .label
        view.returnKeyType = .default
        view.enablesReturnKeyAutomatically = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.contentInset = .zero
        // scrollEnabled 必须关：开启时 UITextView.sizeThatFits 返回固定
        // frame 高，破坏自适应增高（2026-10-27 真机实证：输入满行不增
        // 高、文字溢出不可见）。副作用是系统不跟随光标横滚——由
        // Coordinator 手动 setContentOffset 补上（scrollEnabled=false
        // 只禁交互滚动，程序设置仍生效）。
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = true
        view.keyboardDismissMode = .none
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = String(localized: "消息")
        view.accessibilityHint = String(localized: "回车换行，Command 加回车发送。")
        view.accessibilityIdentifier = "chat.composer.editor"
        controller.textView = view; controller.draft = draft
        return view
    }

    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = view; controller.draft = draft
        view.commandSend = onCommandSend
        // Do not replace native pre-edit text or disrupt its selection/candidate bar.
        if view.markedTextRange == nil, view.text != draft.text {
            let selection = view.selectedRange
            view.text = draft.text
            let end = (draft.text as NSString).length
            view.selectedRange = NSRange(location: min(selection.location, end), length: 0)
        }
        // 焦点变更必须异步：updateUIView 里同步 becomeFirstResponder 会在
        // 聚焦触发布局变化（Duo 双屏紧凑模式）时与键盘 reload 形成同步
        // 重入死循环（updateUIView → becomeFirstResponder → 布局更新 →
        // updateUIView...，主线程假死）。异步后 isFirstResponder 判断在
        // 下一 runloop 已稳定，循环被打断。
        // 异步块必须读"执行时"的实时意图，不能用捕获快照：抽屉展开等
        // 转场中系统会短暂 resign（synchronize 已把 isFocused 写回
        // false），拿旧快照 true 去弹键盘会引发键盘/布局反复弹跳
        // （15PM 真机复现；上游同步版无此环）。
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            if draft.isFocused, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !draft.isFocused, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let minimum = ceil(uiView.font?.lineHeight ?? 24)
        let height = min(maximumHeight, max(minimum, ceil(measured)))
        let shouldScroll = measured > maximumHeight + 1
        if uiView.isScrollEnabled != shouldScroll { uiView.isScrollEnabled = shouldScroll }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeComposerEditor
        init(_ parent: NativeComposerEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            synchronize()
            textView.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ textView: UITextView) { synchronize() }
        func textViewDidBeginEditing(_ textView: UITextView) { synchronize() }
        func textViewDidEndEditing(_ textView: UITextView) { synchronize() }
        private func synchronize() {
            parent.controller.synchronize()
            parent.onTextChange?(parent.draft.text, parent.draft.isComposing)
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // UIKit owns IME candidate confirmation. A plain Return is always
            // accepted as text input, never interpreted as a send gesture.
            true
        }
    }
}
