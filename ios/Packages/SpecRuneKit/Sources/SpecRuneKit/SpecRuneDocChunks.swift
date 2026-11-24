import Foundation

/// 把文档正文切成可独立渲染的多块，每块交给一个 `ChatMarkdownView`。
///
/// `ChatMarkdownView` 会把整篇文本一次解析成 blocks；1 MiB / 数万短段落会让
/// SwiftUI `Text.resolve` 递归爆栈（2026-11-24 实跑 SIGSEGV）。16 000 字符是
/// 单次渲染的安全上限（见 `SpecRuneDocClamp`），但不应是全文的展示上限：
/// 这里按 Markdown 行边界切成多块，顺序拼接后与原文完全一致。
///
/// 切点优先级：空行之后 > 标题行之前 > 行尾。``` / ~~~ 围栏内不切，可短暂
/// 超过 `maxCharacters`，直到围栏闭合或达到硬上限
/// （`maxCharacters * fenceOverflowFactor`），避免把代码块拆成两半。
public nonisolated enum SpecRuneDocChunks {
    /// 默认每块上限：16 000 字符（实测 `ChatMarkdownView` 单次渲染的安全上限）。
    public static let maxCharacters = SpecRuneDocClamp.maxCharacters

    /// 围栏未闭合时允许超过上限的倍数；超过后强制在行边界（必要时按字符）切开。
    public static let fenceOverflowFactor = 2

    /// 按行把 `content` 切成每块 ≤ `maxCharacters` 的正文块。
    ///
    /// - Returns: 空正文返回空数组；正文不超过上限时返回单块；所有块按顺序
    ///   拼接后与 `content` 完全一致。
    public static func split(
        _ content: String,
        maxCharacters: Int = SpecRuneDocChunks.maxCharacters
    ) -> [String] {
        let limit = max(1, maxCharacters)
        guard !content.isEmpty else { return [] }
        guard content.count > limit else { return [content] }

        let lines = splitLines(content)
        let counts = lines.map(\.count)
        var prefix = [Int](repeating: 0, count: lines.count + 1)
        for index in counts.indices {
            prefix[index + 1] = prefix[index] + counts[index]
        }
        let infos = lineInfos(lines)
        let factor = max(1, fenceOverflowFactor)
        let hardLimit = limit > Int.max / factor ? Int.max : limit * factor

        // 行边界 p（0...lines.count）表示「前 p 行」。
        // safe[p]：在第 p 行前切不会把围栏拆开（第 p-1 行结束时不在围栏内）。
        var safe = [Bool](repeating: true, count: lines.count + 1)
        for p in 1...lines.count { safe[p] = !infos[p - 1].inFence }
        var lastSafe = [Int](repeating: -1, count: lines.count + 1)
        var lastBlank = [Int](repeating: -1, count: lines.count + 1)
        var lastHeading = [Int](repeating: -1, count: lines.count + 1)
        for p in 0...lines.count {
            lastSafe[p] = safe[p] ? p : (p > 0 ? lastSafe[p - 1] : -1)
            let blankHere = p > 0 && safe[p] && infos[p - 1].isBlank
            lastBlank[p] = blankHere ? p : (p > 0 ? lastBlank[p - 1] : -1)
            let headingHere = p < lines.count && safe[p] && infos[p].startsHeading
            lastHeading[p] = headingHere ? p : (p > 0 ? lastHeading[p - 1] : -1)
        }
        var nextSafe = [Int](repeating: -1, count: lines.count + 1)
        for p in stride(from: lines.count, through: 0, by: -1) {
            nextSafe[p] = safe[p] ? p : (p < lines.count ? nextSafe[p + 1] : -1)
        }

        var chunks: [String] = []
        var start = 0
        while start < lines.count {
            let fit = lastBoundary(prefix, atMost: prefix[start] + limit, atLeast: start)
            if fit == start {
                // 单行本身就超过上限：围栏内允许到硬上限，否则按字符切开。
                if infos[start].inFence, counts[start] <= hardLimit {
                    chunks.append(String(lines[start]))
                } else {
                    appendCharacterSplit(lines[start], limit: limit, into: &chunks)
                }
                start += 1
                continue
            }

            let safeEnd = lastSafe[fit]
            var end = fit
            if safeEnd > start {
                if lastBlank[safeEnd] > start {
                    end = lastBlank[safeEnd]
                } else if lastHeading[safeEnd] > start {
                    end = lastHeading[safeEnd]
                } else {
                    end = safeEnd
                }
            } else {
                // fit 落在未闭合围栏内：等到围栏闭合；闭不上就到硬上限强制切。
                let close = nextSafe[start + 1]
                if close > start, prefix[close] - prefix[start] <= hardLimit {
                    end = close
                } else {
                    end = lastBoundary(prefix, atMost: prefix[start] + hardLimit, atLeast: start + 1)
                }
            }

            chunks.append(lines[start..<end].joined())
            start = end
        }
        return chunks
    }

    /// 按 `\n` 切行，保留行尾换行符，使各块拼接后与原文逐字符一致。
    private static func splitLines(_ content: String) -> [Substring] {
        var lines: [Substring] = []
        var lineStart = content.startIndex
        while lineStart < content.endIndex {
            if let newline = content[lineStart...].firstIndex(of: "\n") {
                let next = content.index(after: newline)
                lines.append(content[lineStart..<next])
                lineStart = next
            } else {
                lines.append(content[lineStart...])
                lineStart = content.endIndex
            }
        }
        return lines
    }

    /// 每行的围栏状态、空行与标题判定；围栏按行首 ``` / ~~~ 开闭。
    private static func lineInfos(_ lines: [Substring]) -> [LineInfo] {
        var infos: [LineInfo] = []
        infos.reserveCapacity(lines.count)
        var fenceCharacter: Character?
        var fenceLength = 0
        for line in lines {
            let trimmed = trimmedLine(line)
            if let marker = fenceMarker(trimmed) {
                if let open = fenceCharacter {
                    // 闭合围栏只能带空白；围栏内的 ```swift 示例行是正文，不是闭合。
                    if marker.character == open, marker.length >= fenceLength, marker.isBare {
                        fenceCharacter = nil
                        fenceLength = 0
                    }
                } else {
                    fenceCharacter = marker.character
                    fenceLength = marker.length
                }
            }
            infos.append(LineInfo(
                inFence: fenceCharacter != nil,
                isBlank: trimmed.isEmpty,
                startsHeading: isHeading(trimmed)
            ))
        }
        return infos
    }

    private static func trimmedLine(_ line: Substring) -> Substring {
        var slice = line[...]
        while let first = slice.first, first.isWhitespace { slice = slice.dropFirst() }
        while let last = slice.last, last.isWhitespace { slice = slice.dropLast() }
        return slice
    }

    /// 行首的围栏标记；`isBare` 表示标记后只有空白（可作闭合围栏）。
    private static func fenceMarker(_ trimmed: Substring) -> (character: Character, length: Int, isBare: Bool)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix { $0 == first }
        guard run.count >= 3 else { return nil }
        let rest = trimmed.dropFirst(run.count)
        return (first, run.count, rest.allSatisfy { $0.isWhitespace })
    }

    private static func isHeading(_ trimmed: Substring) -> Bool {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return false }
        let rest = trimmed.dropFirst(hashes)
        return rest.isEmpty || rest.first == " "
    }

    /// 返回 `[atLeast, prefix.count - 1]` 中满足 `prefix[p] <= cap` 的最大 p。
    /// 调用方保证 `prefix[atLeast] <= cap`。
    private static func lastBoundary(_ prefix: [Int], atMost cap: Int, atLeast lower: Int) -> Int {
        var low = lower
        var high = prefix.count
        while low < high {
            let mid = (low + high) / 2
            if prefix[mid] <= cap { low = mid + 1 } else { high = mid }
        }
        return low - 1
    }

    /// 单行超过上限时按字符切开（只在围栏硬上限也容不下时发生）。
    private static func appendCharacterSplit(_ line: Substring, limit: Int, into chunks: inout [String]) {
        var pieceStart = line.startIndex
        while pieceStart < line.endIndex {
            let pieceEnd = line.index(pieceStart, offsetBy: limit, limitedBy: line.endIndex) ?? line.endIndex
            chunks.append(String(line[pieceStart..<pieceEnd]))
            pieceStart = pieceEnd
        }
    }

    private struct LineInfo {
        /// 处理完这一行后是否仍在围栏内。
        let inFence: Bool
        let isBlank: Bool
        let startsHeading: Bool
    }
}
