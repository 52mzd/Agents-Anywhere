import Foundation

/// Whether a parse result may replace the blocks a `ChatMarkdownView` shows.
///
/// `.task(id:)` restarts when the text changes, but a cancelled task can still
/// finish after the new one. A result therefore only belongs to the text that
/// produced it. Block count alone cannot tell newer from older: it only grows
/// while streaming appends to one text. A non-streaming view replaces the whole
/// text, and the replacement can have fewer blocks — SpecRune's document tabs
/// once dropped a shorter document as an "older snapshot", leaving the tab
/// highlighted while the body still showed the previous document.
nonisolated enum MarkdownPublishRule {
    /// Whether a result may publish over the blocks currently shown.
    /// - Parameters:
    ///   - requestText: the text the result was parsed from.
    ///   - currentText: the text the view renders now.
    ///   - resultBlockCount: blocks in the result.
    ///   - currentBlockCount: blocks already shown.
    ///   - isStreaming: whether the text grows by appending rather than being replaced.
    static func accepts(
        requestText: String,
        currentText: String,
        resultBlockCount: Int,
        currentBlockCount: Int,
        isStreaming: Bool
    ) -> Bool {
        guard requestText == currentText else { return false }
        return isStreaming ? resultBlockCount >= currentBlockCount : true
    }
}
