import Foundation

@testable import SpecRuneKit

/// 内存文件树：测试里模拟 Connector 的 `fs.readDir` / `fs.readText`。
///
/// 只放测试需要的能力：按相对路径查文件、按目录返回条目，并可按路径模拟
/// 读取失败（单文件或整目录）。`shell` 返回固定 stdout，供详情装配用例。
nonisolated struct FakeTransport: SpecRuneTransport {
    struct Failure: Error {}

    var files: [String: String] = [:]
    var directories: [String: [SpecRuneDirectoryEntry]] = [:]
    /// 这些路径的 `readText` 抛错（模拟单文件读取失败）。
    var unreadable: Set<String> = []
    /// 这些目录的 `listDirectory` 抛错（模拟目录读取失败）。
    var unlistable: Set<String> = []
    /// 覆盖真实字节数（默认按内容 UTF-8 长度）。
    var sizes: [String: Int] = [:]
    /// 这些路径的 `readText` 返回 `truncated=true`。
    var truncatedPaths: Set<String> = []
    var shellOutput: String = ""

    func shell(repo: String, command: String) async throws -> SpecRuneShellResult {
        SpecRuneShellResult(
            stdout: shellOutput,
            stderr: "",
            exitCode: 0,
            timedOut: false,
            stdoutTruncated: false
        )
    }

    func readText(repo: String, path: String) async throws -> SpecRuneTextFile? {
        if unreadable.contains(path) { throw Failure() }
        guard let content = files[path] else { return nil }
        return SpecRuneTextFile(
            content: content,
            size: sizes[path] ?? content.utf8.count,
            truncated: truncatedPaths.contains(path)
        )
    }

    func listDirectory(repo: String, path: String) async throws -> [SpecRuneDirectoryEntry] {
        if unlistable.contains(path) { throw Failure() }
        return directories[path] ?? []
    }
}

extension SpecRuneDirectoryEntry {
    static func file(_ name: String) -> SpecRuneDirectoryEntry {
        SpecRuneDirectoryEntry(name: name, isDirectory: false)
    }

    static func folder(_ name: String) -> SpecRuneDirectoryEntry {
        SpecRuneDirectoryEntry(name: name, isDirectory: true)
    }
}
