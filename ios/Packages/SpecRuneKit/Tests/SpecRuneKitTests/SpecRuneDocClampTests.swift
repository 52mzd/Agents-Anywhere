import Testing

@testable import SpecRuneKit

/// 展开区正文的字符数保护：超长只渲染前 16 000 字符。
@Suite("展开区正文截断")
struct SpecRuneDocClampTests {
    @Test("短文本原样返回")
    func keepsShortText() {
        let result = SpecRuneDocClamp.clamp("# 调研报告\n\n正常段落。")
        #expect(!result.clamped)
        #expect(result.text == "# 调研报告\n\n正常段落。")
    }

    @Test("超长文本截到 16 000 字符")
    func clampsLongText() {
        let content = String(repeating: "段落\n", count: 30_000)
        let result = SpecRuneDocClamp.clamp(content)
        #expect(result.clamped)
        #expect(result.text.count == 16_000)
        #expect(result.text == String(content.prefix(16_000)))
    }

    @Test("空文本原样返回")
    func keepsEmptyText() {
        let result = SpecRuneDocClamp.clamp("")
        #expect(!result.clamped)
        #expect(result.text.isEmpty)
    }

    @Test("恰好等于阈值不截断")
    func keepsExactLimit() {
        let content = String(repeating: "a", count: 16_000)
        let result = SpecRuneDocClamp.clamp(content)
        #expect(!result.clamped)
        #expect(result.text == content)
    }
}
