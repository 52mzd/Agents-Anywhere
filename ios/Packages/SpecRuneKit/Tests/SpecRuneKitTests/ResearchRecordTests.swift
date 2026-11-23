import Foundation
import Testing

@testable import SpecRuneKit

/// 调研清单聚合：对齐 DSH 面板 `readResearchFiles`（iOS 按文件名升序）。
@Suite("调研清单")
struct ResearchFilesTests {
    private let taskDir = ".specrune/tasks/11-23-demo"
    private let researchDir = ".specrune/tasks/11-23-demo/research"

    @Test("聚合任务根 research.md、research-<slug>.md 与 research/ 第一层 .md，按名称升序")
    func aggregatesThreeSources() async {
        let transport = FakeTransport(
            files: [
                "\(taskDir)/research.md": "# 根报告",
                "\(taskDir)/research-old.md": "# 旧命名",
                "\(researchDir)/alpha.md": "# alpha",
                "\(researchDir)/beta.md": "# beta",
            ],
            directories: [
                taskDir: [.file("research.md"), .file("research-old.md")],
                researchDir: [.file("alpha.md"), .file("beta.md")],
            ]
        )

        let files = await SpecRuneClient(transport: transport)
            .researchFiles(repo: "/repo", taskDir: taskDir)

        #expect(files.map(\.name) == ["alpha.md", "beta.md", "research-old.md", "research.md"])
        #expect(files.first { $0.name == "research-old.md" }?.content == "# 旧命名")
        #expect(files.first { $0.name == "alpha.md" }?.content == "# alpha")
    }

    @Test("大小写不敏感；非 .md、子目录与无关文件排除")
    func filtersEntries() async {
        let transport = FakeTransport(
            files: [
                "\(taskDir)/Research.MD": "# 大写",
                "\(taskDir)/notes.md": "notes",
                "\(taskDir)/research.txt": "txt",
                "\(researchDir)/UPPER.MD": "# upper",
                "\(researchDir)/readme.txt": "txt",
                "\(researchDir)/nested/deep.md": "# deep",
            ],
            directories: [
                taskDir: [.file("Research.MD"), .file("notes.md"), .file("research.txt")],
                researchDir: [.file("UPPER.MD"), .file("readme.txt"), .folder("nested")],
            ]
        )

        let files = await SpecRuneClient(transport: transport)
            .researchFiles(repo: "/repo", taskDir: taskDir)

        #expect(files.map(\.name).sorted() == ["Research.MD", "UPPER.MD"])
        #expect(files.allSatisfy { $0.content != "txt" })
    }

    @Test("同名文件去重时 research/ 内版本优先")
    func researchDirectoryWins() async {
        let transport = FakeTransport(
            files: [
                "\(taskDir)/research.md": "# 根版本",
                "\(researchDir)/research.md": "# 目录版本",
            ],
            directories: [
                taskDir: [.file("research.md")],
                researchDir: [.file("research.md")],
            ]
        )

        let files = await SpecRuneClient(transport: transport)
            .researchFiles(repo: "/repo", taskDir: taskDir)

        #expect(files.count == 1)
        #expect(files.first?.name == "research.md")
        #expect(files.first?.content == "# 目录版本")
    }

    @Test("1 MiB 截断沿用 readText 的 truncated 与真实字节数")
    func keepsTruncation() async throws {
        let path = "\(researchDir)/big.md"
        let transport = FakeTransport(
            files: [path: "# 前 1 MiB"],
            directories: [researchDir: [.file("big.md")]],
            sizes: [path: 2_097_152],
            truncatedPaths: [path]
        )

        let files = await SpecRuneClient(transport: transport)
            .researchFiles(repo: "/repo", taskDir: taskDir)

        let file = try #require(files.first)
        #expect(files.count == 1)
        #expect(file.truncated)
        #expect(file.bytes == 2_097_152)
    }

    @Test("单个文件读取失败跳过；research/ 缺失时只保留根文件")
    func skipsUnreadableAndMissingDirectory() async {
        let broken = "\(researchDir)/broken.md"
        let transport = FakeTransport(
            files: [
                "\(taskDir)/research.md": "# 根",
                broken: "# 坏",
            ],
            directories: [
                taskDir: [.file("research.md")],
                researchDir: [.file("broken.md")],
            ],
            unreadable: [broken]
        )

        let files = await SpecRuneClient(transport: transport)
            .researchFiles(repo: "/repo", taskDir: taskDir)
        #expect(files.map(\.name) == ["research.md"])

        let missingDir = FakeTransport(
            files: ["\(taskDir)/research.md": "# 根"],
            directories: [taskDir: [.file("research.md")]]
        )
        let fallback = await SpecRuneClient(transport: missingDir)
            .researchFiles(repo: "/repo", taskDir: taskDir)
        #expect(fallback.map(\.name) == ["research.md"])
    }

    @Test("任务目录不可读时仍尝试 research/，都失败则返回空")
    func toleratesDirectoryFailures() async {
        let transport = FakeTransport(
            files: ["\(researchDir)/a.md": "# a"],
            directories: [researchDir: [.file("a.md")]],
            unlistable: [taskDir]
        )

        let files = await SpecRuneClient(transport: transport)
            .researchFiles(repo: "/repo", taskDir: taskDir)
        #expect(files.map(\.name) == ["a.md"])

        let allBroken = FakeTransport(unlistable: [taskDir, researchDir])
        let empty = await SpecRuneClient(transport: allBroken)
            .researchFiles(repo: "/repo", taskDir: taskDir)
        #expect(empty.isEmpty)
    }
}

/// 会话记录聚合：对齐 DSH 面板 `readSessionRecords`（时间为文件名中的 UTC 时间戳）。
@Suite("会话记录")
struct SessionRecordsTests {
    private let taskRef = "11-23-demo"
    private let sessions = ".specrune/sessions"

    /// 一条合法会话记录：frontmatter + 空行 + 正文。
    private func sessionText(
        task: String,
        id: String = "rec-1",
        meta: String = "",
        body: String = "正文"
    ) -> String {
        "---\nid: \(id)\ntask: \(task)\n\(meta)---\n\n\(body)"
    }

    @Test("只收 task 匹配当前任务的记录，按文件名倒序")
    func matchesTaskAndSorts() async {
        let transport = FakeTransport(
            files: [
                "\(sessions)/20261123T133000-new.md": sessionText(task: taskRef, body: "新"),
                "\(sessions)/20261122T090000-old.md": sessionText(task: taskRef, body: "旧"),
                "\(sessions)/20261121T000000-other.md": sessionText(task: "11-22-other", body: "无关"),
            ],
            directories: [
                sessions: [
                    .file("20261123T133000-new.md"),
                    .file("20261122T090000-old.md"),
                    .file("20261121T000000-other.md"),
                ],
            ]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        #expect(records.map(\.name) == ["20261123T133000-new.md", "20261122T090000-old.md"])
        #expect(records.map(\.body) == ["新", "旧"])
    }

    @Test("历史记录只写短名时按去掉 NN-MM- 前缀兜底")
    func matchesShortName() async {
        let transport = FakeTransport(
            files: [
                "\(sessions)/20261123T133000-short.md": sessionText(task: "demo"),
                "\(sessions)/20261122T090000-partial.md": sessionText(task: "23-demo"),
            ],
            directories: [
                sessions: [
                    .file("20261123T133000-short.md"),
                    .file("20261122T090000-partial.md"),
                ],
            ]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        #expect(records.map(\.name) == ["20261123T133000-short.md"])
    }

    @Test("CRLF frontmatter 正常解析，body 去掉 frontmatter 与后续空行")
    func handlesCRLF() async throws {
        let content = "---\r\nid: rec\r\ntask: 11-23-demo\r\ntitle: 标题\r\n---\r\n\r\n# 正文\r\n第二行"
        let transport = FakeTransport(
            files: ["\(sessions)/20261123T133000-crlf.md": content],
            directories: [sessions: [.file("20261123T133000-crlf.md")]]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.body == "# 正文\r\n第二行")
        #expect(record.meta.title == "标题")
    }

    @Test("meta 取六个键，空值省略")
    func parsesMetaAndOmitsEmpty() async {
        let meta = "title: 标题\nstatus: in_progress\ncreated: 2026-11-23\ndeveloper:\nplatform: ios\nbranch: main\n"
        let transport = FakeTransport(
            files: ["\(sessions)/20261123T133000-meta.md": sessionText(task: taskRef, meta: meta)],
            directories: [sessions: [.file("20261123T133000-meta.md")]]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        let metaValue = records.first?.meta
        #expect(metaValue?.title == "标题")
        #expect(metaValue?.status == "in_progress")
        #expect(metaValue?.created == "2026-11-23")
        #expect(metaValue?.developer == nil)
        #expect(metaValue?.platform == "ios")
        #expect(metaValue?.branch == "main")
    }

    @Test("畸形记录跳过：缺闭合、缺 id、空 id、空 task、无 frontmatter")
    func skipsMalformed() async {
        let transport = FakeTransport(
            files: [
                "\(sessions)/20261123T133001-missing-close.md": "---\nid: rec\ntask: 11-23-demo\n正文",
                "\(sessions)/20261123T133002-missing-id.md": "---\ntask: 11-23-demo\n---\n正文",
                "\(sessions)/20261123T133003-empty-id.md": "---\nid:\ntask: 11-23-demo\n---\n正文",
                "\(sessions)/20261123T133004-empty-task.md": "---\nid: rec\ntask:   \n---\n正文",
                "\(sessions)/20261123T133005-no-frontmatter.md": "正文",
            ],
            directories: [
                sessions: [
                    .file("20261123T133001-missing-close.md"),
                    .file("20261123T133002-missing-id.md"),
                    .file("20261123T133003-empty-id.md"),
                    .file("20261123T133004-empty-task.md"),
                    .file("20261123T133005-no-frontmatter.md"),
                ],
            ]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        #expect(records.isEmpty)
    }

    @Test("空值不吞下一行：空 id 后面的字段不会被当成 id")
    func emptyValueDoesNotConsumeNextLine() async {
        let transport = FakeTransport(
            files: [
                "\(sessions)/20261123T133000-a.md": "---\nid:\ntask: 11-23-demo\n---\n正文",
                "\(sessions)/20261122T090000-b.md": "---\ntitle: 标题\nid: rec\ntask:\n---\n正文",
            ],
            directories: [
                sessions: [.file("20261123T133000-a.md"), .file("20261122T090000-b.md")],
            ]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        #expect(records.isEmpty)
    }

    @Test("记录时间取自文件名中的 UTC 时间戳并转本地时区")
    func parsesRecordTime() async throws {
        let name = "20261123T133000-time.md"
        let transport = FakeTransport(
            files: ["\(sessions)/\(name)": sessionText(task: taskRef)],
            directories: [sessions: [.file(name)]]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.at == expectedLocalTime("20261123T133000"))
        #expect(record.at.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test("文件名不含时间戳时记录时间为空")
    func leavesTimeEmpty() async throws {
        let transport = FakeTransport(
            files: ["\(sessions)/notes.md": sessionText(task: taskRef)],
            directories: [sessions: [.file("notes.md")]]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.at.isEmpty)
    }

    @Test("文件名中的非法日期不解析：不被 Calendar 顺延成别的日期")
    func rejectsInvalidDates() async {
        let names = [
            "20260230T120000-feb30.md",
            "20261301T120000-month13.md",
        ]
        let transport = FakeTransport(
            files: Dictionary(uniqueKeysWithValues: names.map {
                ("\(sessions)/\($0)", sessionText(task: taskRef))
            }),
            directories: [sessions: names.map { .file($0) }]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.at.isEmpty })
    }

    @Test("闰日等合法日期仍按 UTC 解析")
    func acceptsLeapDay() async throws {
        let name = "20240229T000000-leap.md"
        let transport = FakeTransport(
            files: ["\(sessions)/\(name)": sessionText(task: taskRef)],
            directories: [sessions: [.file(name)]]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.at == expectedLocalTime("20240229T000000"))
    }

    @Test("1 MiB 截断沿用 readText 的 truncated 与真实字节数")
    func keepsTruncation() async throws {
        let path = "\(sessions)/20261123T133000-big.md"
        let transport = FakeTransport(
            files: [path: sessionText(task: taskRef)],
            directories: [sessions: [.file("20261123T133000-big.md")]],
            sizes: [path: 3_145_728],
            truncatedPaths: [path]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.truncated)
        #expect(record.bytes == 3_145_728)
    }

    @Test("单个文件读取失败跳过；非 .md 排除；sessions 目录不存在返回空")
    func skipsUnreadableAndMissingDirectory() async {
        let broken = "\(sessions)/20261123T133000-broken.md"
        let transport = FakeTransport(
            files: [
                "\(sessions)/20261123T133000-ok.md": sessionText(task: taskRef),
                broken: sessionText(task: taskRef),
                "\(sessions)/20261122T090000-note.txt": sessionText(task: taskRef),
            ],
            directories: [
                sessions: [
                    .file("20261123T133000-ok.md"),
                    .file("20261123T133000-broken.md"),
                    .file("20261122T090000-note.txt"),
                ],
            ],
            unreadable: [broken]
        )

        let records = await SpecRuneClient(transport: transport)
            .sessionRecords(repo: "/repo", taskRef: taskRef)
        #expect(records.map(\.name) == ["20261123T133000-ok.md"])

        let noDirectory = FakeTransport()
        let empty = await SpecRuneClient(transport: noDirectory)
            .sessionRecords(repo: "/repo", taskRef: taskRef)
        #expect(empty.isEmpty)
    }

    /// 独立的本地时间期望值：用 DateFormatter 按 UTC 解析、本地格式化，
    /// 与实现（Calendar 分量换算）交叉校验。
    private func expectedLocalTime(_ stamp: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyyMMdd'T'HHmmss"
        guard let date = parser.date(from: stamp) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 详情装配：清单失败不拖垮其它字段。
@Suite("任务详情装配")
struct TaskDetailAssemblyTests {
    private let repo = "/repo"
    private let taskDir = ".specrune/tasks/11-23-demo"
    private let sessions = ".specrune/sessions"

    private var summaryJSON: String {
        """
        {"dir":"11-23-demo","title":"演示任务","status":"in_progress",
         "hasPrd":true,"hasDesign":false,"hasImplement":false,
         "path":"/repo/.specrune/tasks/11-23-demo"}
        """
    }

    @Test("详情装配调研与记录清单，文档带真实字节数")
    func assemblesLists() async throws {
        let recordPath = "\(taskDir)/record.md"
        let prdPath = "\(taskDir)/prd.md"
        let researchPath = "\(taskDir)/research.md"
        let transport = FakeTransport(
            files: [
                prdPath: "# PRD",
                recordPath: "# 记录",
                researchPath: "# 调研",
                "\(sessions)/20261123T133000-a.md": "---\nid: rec\ntask: 11-23-demo\n---\n正文",
            ],
            directories: [
                taskDir: [.file("prd.md"), .file("record.md"), .file("research.md")],
                sessions: [.file("20261123T133000-a.md")],
            ],
            sizes: [prdPath: 2048, recordPath: 512, researchPath: 4096],
            shellOutput: summaryJSON
        )

        let detail = try await SpecRuneClient(transport: transport).taskDetail(repo: repo, ref: "11-23-demo")

        #expect(detail.researchFiles.map(\.name) == ["research.md"])
        #expect(detail.researchFiles.first?.bytes == 4096)
        #expect(detail.sessionRecords.count == 1)
        #expect(detail.docs[.prd]?.bytes == 2048)
        #expect(detail.docs[.record]?.bytes == 512)
    }

    @Test("清单目录读取失败时详情仍可打开，其它字段不受影响")
    func toleratesListFailures() async throws {
        let prdPath = "\(taskDir)/prd.md"
        let transport = FakeTransport(
            files: [prdPath: "# PRD", "\(taskDir)/record.md": "# 记录"],
            directories: [taskDir: [.file("prd.md"), .file("record.md")]],
            unlistable: [taskDir, sessions],
            shellOutput: summaryJSON
        )

        let detail = try await SpecRuneClient(transport: transport).taskDetail(repo: repo, ref: "11-23-demo")

        #expect(detail.docs[.prd]?.content == "# PRD")
        #expect(detail.docs[.record]?.content == "# 记录")
        #expect(detail.researchFiles.isEmpty)
        #expect(detail.sessionRecords.isEmpty)
    }
}
