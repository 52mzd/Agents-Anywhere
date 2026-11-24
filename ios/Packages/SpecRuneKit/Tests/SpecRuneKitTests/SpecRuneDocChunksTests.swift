import Testing

@testable import SpecRuneKit

/// 正文分块：每块 ≤ 16 000 字符，优先 Markdown 边界，拼接后与原文一致。
@Suite("正文分块")
struct SpecRuneDocChunksTests {
    @Test("默认每块上限为 16 000 字符")
    func keepsSafeChunkLimit() {
        #expect(SpecRuneDocChunks.maxCharacters == 16_000)
        #expect(SpecRuneDocChunks.maxCharacters == SpecRuneDocClamp.maxCharacters)
    }

    @Test("空正文返回空数组")
    func splitsEmptyIntoNothing() {
        #expect(SpecRuneDocChunks.split("").isEmpty)
    }

    @Test("短正文返回单块")
    func keepsShortContentWhole() {
        let content = "# 调研报告\n\n正常段落。\n"
        #expect(SpecRuneDocChunks.split(content) == [content])
    }

    @Test("超长正文切成多块，每块不超上限且拼接等于原文")
    func splitsLongContentWithoutLosingCharacters() {
        let content = paragraphs(1200)
        let chunks = SpecRuneDocChunks.split(content)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 16_000 })
        #expect(chunks.joined() == content)
        // 空行切点落在行尾，块不会以半行结束。
        #expect(chunks.allSatisfy { $0.hasSuffix("\n") })
    }

    @Test("无空行的长段落按行尾切，不丢字符")
    func splitsParagraphWithoutBlankLines() {
        let content = (0..<3000).map { _ in "一行正文。\n" }.joined()
        let chunks = SpecRuneDocChunks.split(content)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 16_000 })
        #expect(chunks.joined() == content)
    }

    @Test("优先在标题行前切")
    func prefersHeadingBoundaries() {
        let content = (1...10).map { index in
            "## 第 \(index) 节\n" + (0..<20).map { _ in "一行正文。\n" }.joined()
        }.joined()
        let chunks = SpecRuneDocChunks.split(content, maxCharacters: 400)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 400 })
        #expect(chunks.joined() == content)
        #expect(chunks.dropFirst().allSatisfy { $0.hasPrefix("## ") })
    }

    @Test("优先在空行后切")
    func prefersBlankLineBoundaries() {
        let content = (0..<6).map { _ in String(repeating: "正", count: 48) + "\n\n" }.joined()
        let chunks = SpecRuneDocChunks.split(content, maxCharacters: 120)
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.count <= 120 })
        #expect(chunks.joined() == content)
        #expect(chunks.allSatisfy { $0.hasSuffix("\n\n") })
    }

    @Test("代码围栏不被切断（可短暂超过上限）")
    func keepsCodeFenceWhole() {
        let code = (0..<2000).map { _ in "let value = 1\n" }.joined()
        let content = "开头段落。\n\n```swift\n" + "# 围栏里的井号不是标题\n" + code + "```\n\n结尾段落。\n"
        let chunks = SpecRuneDocChunks.split(content)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == content)
        #expect(chunks.allSatisfy { fencesBalanced($0) })
        guard let fenceChunk = chunks.first(where: { $0.contains("```swift") }) else {
            Issue.record("没有找到包含围栏开头的块")
            return
        }
        #expect(fenceChunk.contains("```\n"))
        #expect(fenceChunk.components(separatedBy: "let value = 1").count - 1 == 2000)
        // 围栏块允许超过上限，但仍在硬上限（2 倍）以内。
        #expect(fenceChunk.count > 16_000)
        #expect(fenceChunk.count <= 16_000 * SpecRuneDocChunks.fenceOverflowFactor)
    }

    @Test("围栏内的 ``` 示例行不当作闭合围栏")
    func ignoresFenceLikeLinesInsideFence() {
        let examples = (0..<2000).map { _ in "```swift\n" }.joined()
        let content = "```markdown\n" + examples + "```\n\n结尾段落。\n"
        let chunks = SpecRuneDocChunks.split(content)
        #expect(chunks.joined() == content)
        guard let fenceChunk = chunks.first(where: { $0.contains("```markdown") }) else {
            Issue.record("没有找到包含围栏开头的块")
            return
        }
        #expect(fenceChunk.contains("```\n"))
        #expect(fenceChunk.components(separatedBy: "```swift").count - 1 == 2000)
        #expect(fenceChunk.count <= 16_000 * SpecRuneDocChunks.fenceOverflowFactor)
    }

    @Test("围栏超过硬上限时按上限切开，不丢字符")
    func splitsOversizedFenceAtHardLimit() {
        let code = (0..<4000).map { _ in "code line\n" }.joined()
        let content = "```\n" + code + "```\n"
        let chunks = SpecRuneDocChunks.split(content)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == content)
        #expect(chunks.allSatisfy { $0.count <= 16_000 * SpecRuneDocChunks.fenceOverflowFactor })
    }

    @Test("单行超长按字符切，每块不超上限")
    func splitsSingleLongLine() {
        let content = String(repeating: "字", count: 40_000)
        let chunks = SpecRuneDocChunks.split(content)
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.count <= 16_000 })
        #expect(chunks.joined() == content)
    }

    @Test("自定义上限同样按行切分")
    func respectsCustomLimit() {
        let content = paragraphs(40)
        let chunks = SpecRuneDocChunks.split(content, maxCharacters: 100)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 100 })
        #expect(chunks.joined() == content)
    }

    private func paragraphs(_ count: Int) -> String {
        (0..<count).map { _ in "一段正文，包含一些标点。\n\n" }.joined()
    }

    /// 块内 ``` / ~~~ 围栏成对出现（不把代码块拆成两半）。
    private func fencesBalanced(_ chunk: String) -> Bool {
        var markers = 0
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { markers += 1 }
        }
        return markers.isMultiple(of: 2)
    }
}
