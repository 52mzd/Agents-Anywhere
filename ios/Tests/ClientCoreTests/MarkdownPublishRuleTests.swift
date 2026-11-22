import Testing
@testable import ClientCore

@Suite struct MarkdownPublishRuleTests {
    @Test func rejectsAResultFromTextThatWasReplaced() {
        // A cancelled task may finish after the new one; its result belongs to the old text.
        #expect(!MarkdownPublishRule.accepts(
            requestText: "old document",
            currentText: "new document",
            resultBlockCount: 9,
            currentBlockCount: 2,
            isStreaming: false))
    }

    @Test func nonStreamingAcceptsAShorterReplacement() {
        // Non-streaming replaces the whole text: the new document can have fewer blocks.
        // Rejecting it here left the body on the previous document while the tab moved.
        #expect(MarkdownPublishRule.accepts(
            requestText: "short document",
            currentText: "short document",
            resultBlockCount: 3,
            currentBlockCount: 12,
            isStreaming: false))
    }

    @Test func streamingKeepsBlocksMonotonic() {
        // Streaming appends to one text, so a smaller block count is an earlier snapshot.
        #expect(!MarkdownPublishRule.accepts(
            requestText: "same text",
            currentText: "same text",
            resultBlockCount: 3,
            currentBlockCount: 5,
            isStreaming: true))
        #expect(MarkdownPublishRule.accepts(
            requestText: "same text",
            currentText: "same text",
            resultBlockCount: 5,
            currentBlockCount: 5,
            isStreaming: true))
        #expect(MarkdownPublishRule.accepts(
            requestText: "same text",
            currentText: "same text",
            resultBlockCount: 8,
            currentBlockCount: 5,
            isStreaming: true))
    }
}
