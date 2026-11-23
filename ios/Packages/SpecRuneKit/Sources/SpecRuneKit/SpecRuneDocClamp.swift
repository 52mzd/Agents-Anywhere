import Foundation

/// 清单展开区的正文字符数保护。
///
/// Connector 只按字节截断到 1 MiB，1 MiB 的中文/ASCII 正文可能有近百万字符、
/// 数万段落；整篇交给 `ChatMarkdownView` 会让 SwiftUI 递归解析爆栈
/// （2026-11-24 实跑 `research/big.md` 触发 SIGSEGV）。
/// 先按 64 000 字符截断后实跑仍崩溃（递归深度 16301）：短段落约 8000 段
/// × 2 层嵌套即接近 SwiftUI `Text` 的递归上限（约 16300）。因此收紧到
/// 前 16 000 个——正常调研报告通常远小于此，短段落约 2000 段 × 2 = 4000 层，
/// 留出安全余量，其余由 UI 提示。
public nonisolated enum SpecRuneDocClamp {
    /// 默认上限：16 000 字符；64 000 字符对短段落仍会爆栈，实测后收紧。
    public static let maxCharacters = 16_000

    /// 超过 `maxCharacters` 时截到前 `maxCharacters` 个字符；否则原样返回。
    ///
    /// - Returns: `text` 为可交给渲染器的文本；`clamped` 表示是否发生截断。
    public static func clamp(
        _ content: String,
        maxCharacters: Int = SpecRuneDocClamp.maxCharacters
    ) -> (text: String, clamped: Bool) {
        let limit = max(0, maxCharacters)
        guard content.count > limit else { return (content, false) }
        return (String(content.prefix(limit)), true)
    }
}
