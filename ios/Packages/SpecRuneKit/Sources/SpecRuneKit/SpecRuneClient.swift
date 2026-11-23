import Foundation

/// SpecRune 看板的取数层。
///
/// 只用官方 Server **既有**的两条能力，因此 Connector 与 Server 都无需改动：
/// - shell 跑 `specrune task list/show --json` 拿结构化摘要；
/// - 读文本文件拿任务目录下的文档正文与 `.runtime/sessions/*.json`。
///
/// 文档正文单独读而不是让 CLI 输出，是因为 `shell.exec` 的 stdout 上限
/// 64 000 字符——长文档会把 JSON 截断。
///
/// 错误语义：文件不存在返回 nil（文档可选），**其它错误照常抛出**——
/// 否则离线会被误判成「该项目未启用 SpecRune」。
public nonisolated struct SpecRuneClient: Sendable {
    private let transport: any SpecRuneTransport

    /// CLI 不在 PATH 时的回退路径（面板装到中立目录的形态）。
    private static let fallbackCLIPath = "$HOME/.dsh/specrune/bin/specrune"

    public init(transport: any SpecRuneTransport) {
        self.transport = transport
    }

    // MARK: - 项目判定

    /// 目标目录是否是 SpecRune 项目（存在 `.specrune/workflow.md`）。
    ///
    /// 会抛出连接错误——调用方据此区分「不是项目」与「读不到」。
    public func isSpecRuneProject(repo: String) async throws -> Bool {
        try await readText(repo: repo, path: ".specrune/workflow.md") != nil
    }

    // MARK: - 任务

    /// 已知的任务状态。分批拉取时按它遍历。
    private static let knownStatuses = ["planning", "in_progress", "completed", "blocked", "canceled"]

    /// 任务列表（活跃 + 归档）。
    ///
    /// 一次 `task list --json --all` 能拿全，但 `shell.exec` 的 stdout 上限
    /// 是 64 000 字符——任务多的项目会被截断成非法 JSON。所以截断时退化为
    /// 「按状态分批」，每批各自独立、互不影响，合并后去重。
    public func listTasks(repo: String) async throws -> SpecRuneTaskList {
        do {
            return try await fetchTaskList(repo: repo, arguments: ["task", "list", "--json", "--all"])
        } catch SpecRuneError.truncated {
            // 单批也可能超限（实测 239 条归档的 completed 批仍有 219KB），
            // 所以归档改走文件系统逐月读 task.json——不再受 stdout 上限约束。
            let active = await fetchActiveByStatus(repo: repo)
            let archive = await listArchiveViaFileSystem(repo: repo)
            if active.isEmpty && archive.isEmpty {
                throw SpecRuneError.truncated
            }
            return SpecRuneTaskList(tasks: active, archive: archive)
        }
    }

    /// 活跃任务按状态逐个拉（这些通常很少，单批不会超限）。
    private func fetchActiveByStatus(repo: String) async -> [SpecRuneTaskSummary] {
        var rows: [SpecRuneTaskSummary] = []
        var seen = Set<String>()
        for status in ["planning", "in_progress", "blocked"] {
            guard let part = try? await fetchTaskList(
                repo: repo,
                arguments: ["task", "list", "--json", "--all", "--status", status]
            ) else { continue }
            for task in part.tasks where seen.insert(task.dir).inserted {
                rows.append(task)
            }
        }
        return rows
    }

    /// 归档任务改读文件系统：`.specrune/tasks/archive/<月>/<dir>/task.json`。
    ///
    /// CLI 的 `--json --all` 一次吐出全部归档，任务多时必然超过 shell 的
    /// 64 000 字符上限；逐目录读文件不受这个限制。读取并发进行。
    private func listArchiveViaFileSystem(repo: String) async -> [SpecRuneTaskSummary] {
        guard let months = try? await transport.listDirectory(repo: repo, path: ".specrune/tasks/archive")
        else { return [] }

        let monthNames = months.filter(\.isDirectory).map(\.name).sorted(by: >)
        return await withTaskGroup(of: [SpecRuneTaskSummary].self) { group in
            for month in monthNames {
                group.addTask { await self.readArchiveMonth(repo: repo, month: month) }
            }
            var rows: [SpecRuneTaskSummary] = []
            for await part in group { rows.append(contentsOf: part) }
            return rows
        }
    }

    private func readArchiveMonth(repo: String, month: String) async -> [SpecRuneTaskSummary] {
        let monthPath = ".specrune/tasks/archive/\(month)"
        guard let entries = try? await transport.listDirectory(repo: repo, path: monthPath) else { return [] }
        let dirs = entries.filter(\.isDirectory).map(\.name)

        return await withTaskGroup(of: SpecRuneTaskSummary?.self) { group in
            for dir in dirs {
                group.addTask { await self.readArchivedTask(repo: repo, month: month, dir: dir) }
            }
            var rows: [SpecRuneTaskSummary] = []
            for await row in group { if let row { rows.append(row) } }
            return rows
        }
    }

    private func readArchivedTask(repo: String, month: String, dir: String) async -> SpecRuneTaskSummary? {
        let relative = ".specrune/tasks/archive/\(month)/\(dir)"
        guard let file = try? await transport.readText(repo: repo, path: "\(relative)/task.json"),
              let data = file.content.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return SpecRuneTaskSummary(
            dir: dir,
            title: (raw["title"] as? String) ?? dir,
            status: (raw["status"] as? String) ?? "completed",
            priority: raw["priority"] as? String,
            assignee: raw["assignee"] as? String,
            parent: raw["parent"] as? String,
            children: raw["children"] as? [String],
            createdAt: raw["createdAt"] as? String,
            completedAt: raw["completedAt"] as? String,
            archived: true,
            archiveMonth: month,
            path: "\(repo)/\(relative)"
        )
    }

    /// 执行一次 `task list` 并解码。
    private func fetchTaskList(repo: String, arguments: [String]) async throws -> SpecRuneTaskList {
        let output = try await runCLI(repo: repo, arguments: arguments)
        guard let data = output.data(using: .utf8) else {
            throw SpecRuneError.badOutput("输出不是 UTF-8")
        }
        do {
            return try JSONDecoder().decode(SpecRuneTaskList.self, from: data)
        } catch {
            throw SpecRuneError.badOutput(String(describing: error).prefix(200).description)
        }
    }

    /// 按状态分批拉取并合并（截断时的回退路径）。
    ///
    /// 单批失败/截断只丢这一批，不让整张列表失败——这是「任务过多」时
    /// 至少还能看到大部分任务的关键。
    private func fetchTaskListByStatus(repo: String) async -> SpecRuneTaskList {
        var tasks: [SpecRuneTaskSummary] = []
        var archive: [SpecRuneTaskSummary] = []
        var seenActive = Set<String>()
        var seenArchived = Set<String>()

        for status in Self.knownStatuses {
            guard let part = try? await fetchTaskList(
                repo: repo,
                arguments: ["task", "list", "--json", "--all", "--status", status]
            ) else { continue }
            for task in part.tasks where seenActive.insert(task.dir).inserted {
                tasks.append(task)
            }
            for task in part.archive where seenArchived.insert(task.dir).inserted {
                archive.append(task)
            }
        }
        return SpecRuneTaskList(tasks: tasks, archive: archive)
    }

    /// 任务详情：CLI 摘要 + 各产物文档正文（只取存在的）。
    public func taskDetail(repo: String, ref: String) async throws -> SpecRuneTaskDetail {
        let output = try await runCLI(repo: repo, arguments: ["task", "show", ref, "--json"])
        guard let data = output.data(using: .utf8) else {
            throw SpecRuneError.badOutput("输出不是 UTF-8")
        }
        let summary: SpecRuneTaskSummary
        do {
            summary = try JSONDecoder().decode(SpecRuneTaskSummary.self, from: data)
        } catch {
            throw SpecRuneError.badOutput(String(describing: error).prefix(200).description)
        }

        // 归档任务在 `.specrune/tasks/archive/<月>/<dir>/`，不能只用 dir 拼路径。
        let taskDir = relativeTaskDirectory(repo: repo, summary: summary)

        // 先按 CLI 的 has* 标志决定读哪些：不存在的文档根本不该发请求——
        // Connector 缺文件时抛 FileNotFoundError，Server 会包成 502，逐个盲读
        // 会让任意任务在 record/research 处失败。
        var docs: [SpecRuneDocKind: SpecRuneDoc] = [:]
        let declared: [(SpecRuneDocKind, Bool?)] = [
            (.prd, summary.hasPrd),
            (.design, summary.hasDesign),
            (.implement, summary.hasImplement),
        ]
        for (kind, present) in declared where present == true {
            if let file = try await readText(repo: repo, path: "\(taskDir)/\(kind.fileName)") {
                docs[kind] = SpecRuneDoc(content: file.content, bytes: file.size, truncated: file.truncated)
            }
        }
        // record / research / review 没有 has 标志，只能试读；缺失属于常态，容错即可。
        for kind in [SpecRuneDocKind.record, .research, .review] {
            if let file = try? await readText(repo: repo, path: "\(taskDir)/\(kind.fileName)") {
                docs[kind] = SpecRuneDoc(content: file.content, bytes: file.size, truncated: file.truncated)
            }
        }
        // 上下文清单：两份 jsonl 合并，与面板概览「上下文」同源。
        var context: [SpecRuneContextRow] = []
        for name in ["implement.jsonl", "check.jsonl"] {
            if let file = try? await readText(repo: repo, path: "\(taskDir)/\(name)") {
                context.append(contentsOf: Self.parseContextRows(file.content))
            }
        }
        // 调研/记录清单：两个聚合各自容错，失败返回空数组，不拖垮详情。
        let researchFiles = await researchFiles(repo: repo, taskDir: taskDir)
        let sessionRecords = await sessionRecords(repo: repo, taskRef: summary.dir)
        return SpecRuneTaskDetail(
            summary: summary,
            docs: docs,
            context: context,
            researchFiles: researchFiles,
            sessionRecords: sessionRecords
        )
    }

    // MARK: - 调研与记录清单

    /// 会话记录目录（相对 repo）。
    private static let sessionsDirectory = ".specrune/sessions"

    /// 调研文件清单：任务根 `research.md`、根 `research-<slug>.md` 与
    /// `research/` 第一层 `.md`（大小写不敏感、不递归）。
    ///
    /// 同名去重时 `research/` 内版本优先（与面板 `readResearchFiles` 同口径）；
    /// iOS 不取 mtime（用户裁决），改按文件名升序。目录或单个文件读取失败都
    /// 跳过，不拖垮任务详情。
    public func researchFiles(repo: String, taskDir: String) async -> [SpecRuneResearchFile] {
        // 先收根目录、再收 research/：同名键后写覆盖，保证目录内版本优先。
        var paths: [String: String] = [:]
        if let entries = try? await transport.listDirectory(repo: repo, path: taskDir) {
            for entry in entries where !entry.isDirectory && Self.isRootResearchName(entry.name) {
                paths[entry.name] = "\(taskDir)/\(entry.name)"
            }
        }
        let researchDir = "\(taskDir)/research"
        if let entries = try? await transport.listDirectory(repo: repo, path: researchDir) {
            for entry in entries where !entry.isDirectory && Self.isMarkdownName(entry.name) {
                paths[entry.name] = "\(researchDir)/\(entry.name)"
            }
        }

        var files: [SpecRuneResearchFile] = []
        for (name, path) in paths {
            guard let file = try? await readText(repo: repo, path: path) else { continue }
            files.append(SpecRuneResearchFile(
                name: name,
                bytes: file.size,
                truncated: file.truncated,
                content: file.content
            ))
        }
        return files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 匹配当前任务的会话记录（`.specrune/sessions/*.md`）。
    ///
    /// 入选条件与面板 `readSessionRecords` 一致：frontmatter `task` 等于任务
    /// 目录名，或去掉 `NN-MM-` 前缀的短名；`id`/`task` 为空、缺闭合 `---`
    /// 的记录跳过。按文件名（UTC 时间戳）倒序，每批 6 个并发读取；单个文件
    /// 失败跳过，目录不存在返回空数组。
    public func sessionRecords(repo: String, taskRef: String) async -> [SpecRuneSessionRecord] {
        guard let entries = try? await transport.listDirectory(repo: repo, path: Self.sessionsDirectory)
        else { return [] }
        let names = entries
            .filter { !$0.isDirectory && Self.isMarkdownName($0.name) }
            .map(\.name)
            .sorted(by: >)

        var records: [SpecRuneSessionRecord] = []
        for start in stride(from: 0, to: names.count, by: 6) {
            let batch = names[start..<min(start + 6, names.count)]
            let part = await withTaskGroup(of: SpecRuneSessionRecord?.self) { group in
                for name in batch {
                    group.addTask { await self.readSessionRecord(repo: repo, name: name, taskRef: taskRef) }
                }
                var rows: [SpecRuneSessionRecord] = []
                for await row in group { if let row { rows.append(row) } }
                return rows
            }
            records.append(contentsOf: part)
        }
        return records.sorted { $0.name > $1.name }
    }

    /// 读一条会话记录并解析 frontmatter；读取失败或畸形返回 nil。
    private func readSessionRecord(
        repo: String,
        name: String,
        taskRef: String
    ) async -> SpecRuneSessionRecord? {
        guard let file = try? await readText(repo: repo, path: "\(Self.sessionsDirectory)/\(name)"),
              let parsed = Self.parseSessionRecord(content: file.content, taskRef: taskRef)
        else { return nil }
        return SpecRuneSessionRecord(
            name: name,
            at: Self.recordDate(fromName: name),
            bytes: file.size,
            truncated: file.truncated,
            content: file.content,
            body: parsed.body,
            meta: parsed.meta
        )
    }

    /// 任务根的调研文件名：`research.md` 或 `research-<slug>.md`（大小写不敏感）。
    static func isRootResearchName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".md") else { return false }
        let stem = lower.dropLast(3)
        if String(stem) == "research" { return true }
        return stem.hasPrefix("research-") && stem.count > "research-".count
    }

    /// 是否 `.md` 文件（大小写不敏感）。
    static func isMarkdownName(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".md")
    }

    /// 解析会话记录：缺闭合分隔段或 `id`/`task` 为空返回 nil。
    ///
    /// 与面板正则 `^---\r?\n([\s\S]*?)\r?\n---` 同语义：开头必须是 `---`
    /// 分隔行，闭合行以行首 `---` 判定；`task`/`id` 只吃冒号后的水平空白
    /// （`\s*` 会跨行，空值会把下一行吞成自己的值）。
    static func parseSessionRecord(
        content: String,
        taskRef: String
    ) -> (body: String, meta: SpecRuneSessionMeta)? {
        guard let block = splitFrontmatter(content) else { return nil }
        let fields = frontmatterFields(block.frontmatter)
        guard let task = fields["task"], !task.isEmpty,
              let id = fields["id"], !id.isEmpty
        else { return nil }
        guard task == taskRef || task == shortTaskRef(taskRef) else { return nil }

        func value(_ key: String) -> String? {
            guard let raw = fields[key], !raw.isEmpty else { return nil }
            return raw
        }
        let meta = SpecRuneSessionMeta(
            title: value("title"),
            status: value("status"),
            created: value("created"),
            developer: value("developer"),
            platform: value("platform"),
            branch: value("branch")
        )
        return (body: block.body, meta: meta)
    }

    /// 拆出 frontmatter 与正文：正文是闭合行之后、去掉连续空行的部分。
    ///
    /// 用 `components(separatedBy:)` 而不是 `split(separator:)`：Swift 把
    /// `\r\n` 当作**一个** Character，按 `"\n"` 切分在 CRLF 文本里切不开。
    static func splitFrontmatter(_ text: String) -> (frontmatter: String, body: String)? {
        // 开头分隔行 = "---" + 一个换行 Character（LF 或 CRLF），都是 4 个 Character。
        guard text.hasPrefix("---\r\n") || text.hasPrefix("---\n") else { return nil }

        let lines = text.dropFirst(4).components(separatedBy: "\n")
        guard let closing = lines.firstIndex(where: { $0.hasPrefix("---") }) else { return nil }
        let frontmatter = lines[..<closing].joined(separator: "\n")
        // 去掉闭合行之后的连续空行（对应 `^(?:\r?\n)+`）。
        var bodyLines = lines[(closing + 1)...]
        while let first = bodyLines.first, first.isEmpty || first == "\r" {
            bodyLines = bodyLines.dropFirst()
        }
        return (frontmatter, bodyLines.joined(separator: "\n"))
    }

    /// 取 frontmatter 的 `key: value`（每个键取第一次出现，值去掉首尾空白）。
    static func frontmatterFields(_ frontmatter: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in frontmatter.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            guard !key.isEmpty, fields[key] == nil else { continue }
            fields[key] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fields
    }

    /// 去掉任务目录名的 `NN-MM-` 前缀（历史会话记录只写短名）。
    static func shortTaskRef(_ taskRef: String) -> String {
        let characters = Array(taskRef)
        guard characters.count > 6,
              characters[0].isASCII, characters[0].isNumber,
              characters[1].isASCII, characters[1].isNumber,
              characters[2] == "-",
              characters[3].isASCII, characters[3].isNumber,
              characters[4].isASCII, characters[4].isNumber,
              characters[5] == "-"
        else { return taskRef }
        return String(characters.dropFirst(6))
    }

    /// 从文件名解析记录时间：`YYYYMMDDTHHMMSS-<slug>.md`（UTC），转成本地时区
    /// `yyyy-MM-dd HH:mm:ss`；解析失败返回空。
    static func recordDate(fromName name: String) -> String {
        let prefix = Array(name.prefix(16))
        guard prefix.count == 16,
              prefix[8] == "T",
              prefix[15] == "-",
              prefix[0..<8].allSatisfy(Self.isASCIIDigit),
              prefix[9..<15].allSatisfy(Self.isASCIIDigit)
        else { return "" }
        let digits = String(prefix[0..<8]) + String(prefix[9..<15])
        guard let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)),
              let hour = Int(digits.dropFirst(8).prefix(2)),
              let minute = Int(digits.dropFirst(10).prefix(2)),
              let second = Int(digits.dropFirst(12).prefix(2))
        else { return "" }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? utcCalendar.timeZone
        guard let date = utcCalendar.date(from: components) else { return "" }
        // `Calendar.date(from:)` 对非法日期是宽松的（`2026-02-30` → `03-02`、
        // `2026-13-01` → `2027-01-01`）。反向取分量核对，与输入不一致即视为
        // 解析失败，避免把不存在的日期显示成被顺延的日期。
        let roundTrip = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day,
              roundTrip.hour == hour, roundTrip.minute == minute, roundTrip.second == second
        else { return "" }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let local = localCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard let localYear = local.year, let localMonth = local.month, let localDay = local.day,
              let localHour = local.hour, let localMinute = local.minute, let localSecond = local.second
        else { return "" }
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            localYear, localMonth, localDay, localHour, localMinute, localSecond
        )
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    // MARK: - 规范

    /// 读一条规范正文（`specRefs` 里的相对路径）。文件不存在返回 nil。
    public func readSpec(repo: String, path: String) async throws -> SpecRuneTextFile? {
        try await readText(repo: repo, path: path)
    }

    // MARK: - 会话关联

    /// 该会话当前绑定的任务；无关联返回 nil。
    ///
    /// DSH 把关联写在 `.specrune/.runtime/sessions/dsh_<sanitized>.json` 的
    /// `current_task`（相对仓库根的路径）。键规则与面板 `readSessionTask` 一致。
    /// 这是旁路信息，读失败按「无关联」处理，不打断会话页。
    public func sessionTask(repo: String, sessionId: String) async -> SpecRuneSessionTask? {
        let key = "dsh_" + sanitizeSessionId(sessionId)
        let raw: SpecRuneTextFile?
        do {
            raw = try await readText(repo: repo, path: ".specrune/.runtime/sessions/\(key).json")
        } catch {
            return nil
        }
        guard let text = raw?.content,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (object["current_task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty
        else {
            return nil
        }
        let ref = current.split(separator: "/").last.map(String.init) ?? ""
        guard !ref.isEmpty else { return nil }
        return SpecRuneSessionTask(taskRef: ref, title: nil, createdAt: nil)
    }

    // MARK: - 底层调用

    /// 在 repo 根下跑一条 specrune 命令，返回 stdout。
    private func runCLI(repo: String, arguments: [String]) async throws -> String {
        let args = arguments.joined(separator: " ")
        if let output = try await exec(repo: repo, command: "specrune \(args)") {
            return output
        }
        // PATH 上没有 specrune 时回退到中立目录；仍失败才认定未安装。
        if let output = try await exec(repo: repo, command: "\(Self.fallbackCLIPath) \(args)") {
            return output
        }
        throw SpecRuneError.cliMissing
    }

    /// 执行一次 shell；CLI 不存在返回 nil（交给上层回退）。
    private func exec(repo: String, command: String) async throws -> String? {
        let result: SpecRuneShellResult
        do {
            result = try await transport.shell(repo: repo, command: command)
        } catch let error as SpecRuneError {
            throw error
        } catch is CancellationError {
            // 视图切换导致的取消不是「连不上设备」，别包装成 offline。
            throw CancellationError()
        } catch {
            throw SpecRuneError.offline(String(describing: error).prefix(200).description)
        }

        if result.timedOut {
            throw SpecRuneError.cliFailed("执行超时")
        }
        if result.exitCode != 0 {
            let failure = SpecRuneFailureClassifier.classify(
                exitCode: result.exitCode,
                stderr: result.stderr,
                truncated: false
            )
            // 只有「命令不存在」才值得回退到另一条路径重试。
            if case .cliMissing = failure { return nil }
            throw failure
        }
        if result.stdoutTruncated {
            throw SpecRuneError.truncated
        }
        return result.stdout
    }

    /// 读仓库内文本文件；不存在返回 nil，连接错误抛出。
    private func readText(repo: String, path: String) async throws -> SpecRuneTextFile? {
        try await transport.readText(repo: repo, path: path)
    }

    /// 解析 jsonl 上下文清单：坏行跳过，`_example` 标记成示例行。
    static func parseContextRows(_ text: String) -> [SpecRuneContextRow] {
        var rows: [SpecRuneContextRow] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if object["_example"] != nil {
                rows.append(SpecRuneContextRow(file: "", reason: "", example: true))
                continue
            }
            let file = ((object["file"] as? String) ?? (object["path"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard !file.isEmpty else { continue }
            let reason = ((object["reason"] as? String) ?? (object["description"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            rows.append(SpecRuneContextRow(file: file, reason: reason, example: false))
        }
        return rows
    }

    /// 把 CLI 给的绝对任务目录换成相对 repo 的路径。
    private func relativeTaskDirectory(repo: String, summary: SpecRuneTaskSummary) -> String {
        let root = repo.hasSuffix("/") ? String(repo.dropLast()) : repo
        if summary.path.hasPrefix(root + "/") {
            return String(summary.path.dropFirst(root.count + 1))
        }
        // 兜底：绝对路径对不上时按归档月份推断，再退回活跃目录。
        if let month = summary.archiveMonth, !month.isEmpty {
            return ".specrune/tasks/archive/\(month)/\(summary.dir)"
        }
        return ".specrune/tasks/\(summary.dir)"
    }

    /// 与面板 `readSessionTask` 相同的键清洗规则。
    private func sanitizeSessionId(_ value: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var out = ""
        for character in value {
            out.append(allowed.contains(character) ? character : "_")
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    }
}
