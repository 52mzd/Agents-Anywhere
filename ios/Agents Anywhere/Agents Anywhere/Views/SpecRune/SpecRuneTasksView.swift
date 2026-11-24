import SpecRuneKit
import SwiftUI
import Textual

/// SpecRune「任务」屏。
///
/// 数据经 `SpecRuneKit` 从工作设备取：`shell/exec` 跑 CLI 拿摘要，
/// `fs/readText` 读文档正文。Connector 与 Server 均无改动。
///
/// 布局（swiftui-iphone-duo Tier 1）：
/// - `NavigationSplitView` 三栏，compact 自动合成单栈、regular（Duo 内屏）三栏；
/// - 不按设备/idiom/方向判定，宽度只来自容器；
/// - 详情正文 `maxWidth 700`，多余宽度给层级而非更长的行。
///
/// 动效（apple-design）：切换任务用 critically damped 弹簧，
/// `accessibilityReduceMotion` 时退化为无动画。
struct SpecRuneTasksView: View {
    let connectorId: V2ConnectorID
    /// 该设备上的全部项目；非 SpecRune 项目会在列表里置灰。
    let projects: [V2Project]
    /// dashboard 还在加载（此时 `projects` 为空不代表设备真的没有项目）。
    var isLoadingProjects = false
    let api: any V2ConnectorAPIProtocol
    /// 打开 app 侧栏（Duo 内屏双栏时是切换，外屏抽屉时是展开）。
    let onMenu: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Duo 横屏时系统把 toolbar 收编成右缘竖排；页面必须把 rail 按钮
    /// 经 ChatPageToolbar 注入，否则新会话/账号入口会消失。
    @Environment(\.chatRail) private var chatRail

    @State private var model: SpecRuneBoardModel?
    /// 导航栈路径（元素是任务 ref）。单栏 push 详情。
    @State private var taskPath: [String] = []
    /// 归档段默认折叠（与面板一致：进来先看活跃任务）。
    @State private var archiveExpanded = false
    /// 已展开的归档月份组。
    @State private var expandedMonths: Set<String> = []
    /// 排序方向：默认从晚到早。
    @State private var sortDescending = true
    /// 项目选择弹层（rail 按钮触发）。用 Bool 而不是把 model 塞进 AnyView：
    /// ChatRailButton 用 AnyView 包装会打断 @Observable 追踪，菜单会停在旧状态。
    @State private var showsProjectPicker = false

    private var detailAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1.0)
    }

    var body: some View {
        Group {
            if let model {
                board(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard model == nil else { return }
            let transport = SpecRuneConnectorTransport(api: api, connectorId: connectorId)
            let board = SpecRuneBoardModel(client: SpecRuneClient(transport: transport), projects: projects)
            model = board
            await board.probeProjects()
        }
        // dashboard 后到：项目列表变了要推给 Model，否则看板永远停在空列表。
        .onChange(of: projects) { _, newValue in
            guard let model else { return }
            model.updateProjects(newValue)
            Task { await model.probeProjects() }
        }
        // 选中项目从设备消失时 Model 会置 nil：导航栈里若还停在该项目的详情页，
        // 退回项目列表，而不是落在「未选择项目」兜底文案上。
        .onChange(of: model?.selectedRepo) { _, repo in
            if repo == nil { taskPath.removeAll() }
        }
    }

    // MARK: - 三栏

    private func board(_ model: SpecRuneBoardModel) -> some View {
        // 单栏 + push 详情：这个看板嵌在 app 的 detail 区域里，外面还有
        // 一条 app 侧栏。Duo 内屏横屏约 669pt，再并排两栏会把详情挤到不可见，
        // 所以列表与详情用导航栈串联，宽度全部留给当前页。
        NavigationStack(path: $taskPath) {
            taskColumn(model)
                .navigationDestination(for: String.self) { ref in
                    // 详情页必须自己再挂一次工具栏：ChatPageToolbar 的
                    // toolbar 项是 per-page 的，push 后外层那份不会跟过来，
                    // 右缘 rail 会整个消失。
                    detailPage(model, ref: ref)
                        .modifier(pageToolbar)
                }
        }
    }

    // MARK: - 项目切换（工具栏菜单）

    /// 项目切换器：列出该设备上的 SpecRune 项目，未启用的置灰。
    private func projectMenu(_ model: SpecRuneBoardModel) -> some View {
        Menu {
            ForEach(model.deviceProjects) { project in
                let enabled = model.specRuneRepos[project.workspacePath] == true
                Button {
                    taskPath.removeAll()
                    Task { await model.select(repo: project.workspacePath) }
                } label: {
                    if model.selectedRepo == project.workspacePath {
                        Label(project.name, appSymbol: "checkmark")
                    } else {
                        Text(verbatim: enabled ? project.name : "\(project.name)（未启用）")
                    }
                }
                .disabled(!enabled)
            }
        } label: {
            HStack(spacing: 4) {
                // 直接显示当前项目的目录名：不依赖 deviceProjects 反查，
                // 后者与 selectedRepo 不同步时会退化成「选择项目」。
                Text(verbatim: model.selectedRepo.map { ($0 as NSString).lastPathComponent } ?? "选择项目")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                AppSymbol("chevron.down", size: 11)
            }
        }
    }

    // MARK: - 任务列

    @ViewBuilder
    private func taskColumn(_ model: SpecRuneBoardModel) -> some View {
        Group {
            if let repo = model.selectedRepo {
                switch model.listStates[repo] ?? .idle {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(message):
                    ContentUnavailableView("无法读取任务", appSymbol: "exclamationmark.triangle",
                                           description: Text(verbatim: message))
                case let .loaded(list):
                    taskList(model, repo: repo, list: list)
                }
            } else {
                projectPicker(model)
            }
        }
        // 用 app 统一的页面工具栏：它负责把 rail 按钮送进 Duo 右缘竖排，
        // 并保证抽屉形态下导航栏占位不变（内容不位移）。
        // 标题固定「SpecRune」，当前项目在右侧菜单里显示——两者都写项目名会重复。
        .sheet(isPresented: $showsProjectPicker) {
            // 这里在 board(_ model:) 内部，model 已是非可选。
            SpecRuneProjectPickerSheet(model: model) { repo in
                taskPath.removeAll()
                showsProjectPicker = false
                Task { await model.select(repo: repo) }
            }
        }
        .modifier(ChatPageToolbar(
            title: "SpecRune",
            onMenu: onMenu,
            // 项目切换进右缘竖排（Duo 横屏右侧还有空间）。
            // 按钮本身不读 model 状态——它只翻转一个 @State，具体列表在
            // sheet 里渲染，这样 AnyView 打断追踪也不影响正确性。
            railTrailing: [ChatRailButton(id: "specrune-project", view: AnyView(
                Button { showsProjectPicker = true } label: {
                    Label("项目", image: AppSymbolAssets.names["folder"] ?? "aa-Folder")
                }
            ))] + (chatRail.map { chatRailButtons($0) } ?? []),
            pageTrailing: []
        ))
    }

    // MARK: - 项目选择（未选中时的首屏）

    /// 还没有选中项目时的首屏：列出该设备的项目，由用户自己点选。
    ///
    /// 内嵌在任务列的位置（不是自动弹出的 sheet）：选中后原地换成任务列表，
    /// 与 rail 的「项目」sheet 共用同一个 `model.select(repo:)`。
    @ViewBuilder
    private func projectPicker(_ model: SpecRuneBoardModel) -> some View {
        if model.deviceProjects.isEmpty {
            if isLoadingProjects {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("这个设备还没有项目", appSymbol: "folder",
                                       description: Text("先在设备上添加项目，再回来看任务"))
            }
        } else {
            List {
                Section("选择项目") {
                    ForEach(model.deviceProjects) { project in
                        projectPickerRow(model, project: project)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// 单个项目：只有确认是 SpecRune 项目的行可点；探测中与探测失败都置灰并说明原因。
    private func projectPickerRow(_ model: SpecRuneBoardModel, project: V2Project) -> some View {
        let enabled = model.specRuneRepos[project.workspacePath] == true
        let probing = model.specRuneRepos[project.workspacePath] == nil
            && model.probeFailures[project.workspacePath] == nil
        return Button {
            Task { await model.select(repo: project.workspacePath) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: project.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(verbatim: specRuneProjectStatusText(model, project: project))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                }
                Spacer(minLength: 4)
                if probing {
                    ProgressView().controlSize(.small)
                } else if enabled {
                    AppSymbol("chevron.right", size: 12)
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                }
            }
        }
        .disabled(!enabled)
    }

    private func projectName(_ model: SpecRuneBoardModel, repo: String) -> String {
        model.deviceProjects.first { $0.workspacePath == repo }?.name ?? "任务"
    }

    private func taskList(_ model: SpecRuneBoardModel, repo: String, list: SpecRuneTaskList) -> some View {
        let activeRows = SpecRuneTaskTree.rows(list.tasks, descending: sortDescending)
        let groups = SpecRuneTaskTree.archiveMonths(list.archive, descending: sortDescending)
        return List {
            if list.tasks.isEmpty && list.archive.isEmpty {
                ContentUnavailableView("暂无任务", appSymbol: "checkmark.circle",
                                       description: Text("这个项目还没有 SpecRune 任务"))
            }
            if !list.tasks.isEmpty {
                Section {
                    ForEach(activeRows) { row in
                        NavigationLink(value: row.task.dir) {
                            SpecRuneTaskRow(task: row.task, depth: row.depth)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("工作流 · \(list.tasks.count)")
                        Spacer()
                        Button {
                            sortDescending.toggle()
                        } label: {
                            HStack(spacing: 2) {
                                Text(sortDescending ? "从晚到早" : "从早到晚")
                                AppSymbol(sortDescending ? "chevron.down" : "chevron.up", size: 9)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !groups.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $archiveExpanded) {
                        ForEach(groups) { group in
                            DisclosureGroup(isExpanded: monthBinding(group.month)) {
                                ForEach(SpecRuneTaskTree.rows(group.tasks, descending: sortDescending)) { row in
                                    NavigationLink(value: row.task.dir) {
                                        SpecRuneTaskRow(task: row.task, depth: row.depth, isArchived: true)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(verbatim: group.month)
                                    Spacer(minLength: 4)
                                    Text("\(group.tasks.count)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                                }
                                .font(.subheadline)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("归档")
                            Spacer(minLength: 4)
                            Text("\(list.archive.count)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// app 统一的页面工具栏：负责把 rail 按钮送进 Duo 右缘竖排，
    /// 并保证抽屉形态下导航栏占位不变（内容不位移）。
    private var pageToolbar: ChatPageToolbar {
        ChatPageToolbar(
            title: "SpecRune",
            onMenu: onMenu,
            // 项目切换进右缘竖排。按钮只翻转 @State，列表在 sheet 里渲染——
            // ChatRailButton 的 AnyView 会打断 @Observable 追踪。
            railTrailing: [ChatRailButton(id: "specrune-project", view: AnyView(
                Button { showsProjectPicker = true } label: {
                    Label("项目", image: AppSymbolAssets.names["folder"] ?? "aa-Folder")
                }
            ))] + (chatRail.map { chatRailButtons($0) } ?? []),
            pageTrailing: []
        )
    }

    private func monthBinding(_ month: String) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(month) },
            set: { open in
                if open { expandedMonths.insert(month) } else { expandedMonths.remove(month) }
            }
        )
    }

    // MARK: - 详情列

    @ViewBuilder
    private func detailPage(_ model: SpecRuneBoardModel, ref: String) -> some View {
        if let repo = model.selectedRepo {
            switch model.detail(repo: repo, ref: ref) {
            case .idle, .loading:
                // idle 与 loading 必须共用同一个视图树：分成两个分支时，
                // 状态从 idle 变 loading 会销毁 .task，请求被取消→回 idle→再触发，死循环。
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: ref) { await model.loadDetail(repo: repo, ref: ref) }
            case let .failed(message):
                ContentUnavailableView("无法读取任务详情", appSymbol: "exclamationmark.triangle",
                                       description: Text(verbatim: message))
            case let .loaded(detail):
                SpecRuneTaskDetailView(detail: detail, repo: repo, model: model)
            }
        } else {
            ContentUnavailableView("未选择项目", appSymbol: "sidebar.left",
                                   description: Text("用上方菜单选择一个 SpecRune 项目"))
        }
    }
}

// MARK: - 项目选择弹层

/// 项目列表行副标题（首屏 picker 与 rail sheet 共用）：
/// 探测失败原因 / 检测中 / 已启用 / 未启用。
private func specRuneProjectStatusText(_ model: SpecRuneBoardModel, project: V2Project) -> String {
    if let failure = model.probeFailures[project.workspacePath] { return failure }
    if model.specRuneRepos[project.workspacePath] == nil { return "检测中…" }
    return model.specRuneRepos[project.workspacePath] == true ? "SpecRune 项目" : "未启用 SpecRune"
}

/// rail 按钮弹出的项目列表。读 model 的状态在 sheet 里是新鲜快照，
/// 不受外层 AnyView 打断追踪的影响。
private struct SpecRuneProjectPickerSheet: View {
    let model: SpecRuneBoardModel
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section("SpecRune 项目") {
                    ForEach(model.deviceProjects) { project in
                        let enabled = model.specRuneRepos[project.workspacePath] == true
                        Button {
                            onPick(project.workspacePath)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: project.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(verbatim: specRuneProjectStatusText(model, project: project))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                                }
                                Spacer(minLength: 4)
                                if model.selectedRepo == project.workspacePath {
                                    AppSymbol("checkmark", size: 13)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(!enabled)
                    }
                }
            }
            .navigationTitle("选择项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 任务行

private struct SpecRuneTaskRow: View {
    let task: SpecRuneTaskSummary
    /// 子任务缩进层级（面板：每层 16pt）。
    var depth: Int = 0
    var isArchived: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(SpecRunePresentation.statusColor(task.status))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(SpecRunePresentation.statusLabel(task.status))
                Text(verbatim: task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if let priority = task.priority {
                    SpecRunePriorityChip(priority: priority)
                }
            }
            HStack(spacing: 10) {
                if let progress = SpecRunePresentation.progress(task) {
                    SpecRuneProgressBar(done: progress.done, total: progress.total,
                                        tint: SpecRunePresentation.statusColor(task.status))
                        .frame(maxWidth: 100)
                    Text("\(progress.done)/\(progress.total) \(progress.label)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                }
                if let assignee = task.assignee, !assignee.isEmpty {
                    Label(assignee, appSymbol: "person.crop.circle")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let created = task.createdAt {
                    Text(verbatim: created)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, CGFloat(depth) * 16)
    }
}

// MARK: - 详情

private struct SpecRuneTaskDetailView: View {
    let detail: SpecRuneTaskDetail
    let repo: String
    let model: SpecRuneBoardModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: DetailTab = .overview
    /// 当前展开的规范路径（同一时刻只展开一条）。
    @State private var expandedSpec: String?
    /// 调研清单展开项：nil = 未点过（默认展开第一项），"" = 全部收起。
    @State private var openResearch: String?
    /// 记录清单展开项：语义同 `openResearch`。
    @State private var openRecord: String?

    /// 详情维度：概览 + 每种存在的产物文档，与 Mac 面板的标签条一致。
    enum DetailTab: Hashable {
        case overview
        case doc(SpecRuneDocKind)
    }

    private var summary: SpecRuneTaskSummary { detail.summary }

    private var availableDocs: [SpecRuneDocKind] {
        SpecRuneDocKind.allCases.filter(hasTab)
    }

    /// 维度是否可见：调研/记录还看清单是否非空（与 DSH 面板一致）。
    private func hasTab(_ kind: SpecRuneDocKind) -> Bool {
        switch kind {
        case .research:
            return !detail.researchFiles.isEmpty || detail.docs[.research] != nil
        case .record:
            return !detail.sessionRecords.isEmpty || detail.docs[.record] != nil
        default:
            return detail.docs[kind] != nil
        }
    }

    private var tabs: [DetailTab] {
        [.overview] + availableDocs.map(DetailTab.doc)
    }

    private func tabLabel(_ value: DetailTab) -> String {
        switch value {
        case .overview: "概览"
        case let .doc(kind): kind.label
        }
    }

    private var expandAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case .overview:
                        overview
                        if availableDocs.isEmpty {
                            Text("该任务还没有产物文档")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        }
                    case let .doc(kind):
                        docTab(kind)
                    }
                }
                .padding(20)
                // 先撑满可用宽度，再限制最大宽度并居中——顺序反了的话
                // VStack 宽度会收缩到内容宽度，居中后左右各留一大片空白。
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: 740, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(summary.title)
    }

    /// 标签条：横向滚动，选中的一项加底色（对应 Mac 面板的维度标签）。
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.self) { value in
                    let isSelected = tab == value
                    Button {
                        withAnimation(expandAnimation) { tab = value }
                    } label: {
                        Text(tabLabel(value))
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : AppTheme.secondaryText(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? AppTheme.groupedFill(colorScheme) : Color.clear,
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// 单个文档维度：分块渲染的正文 + 1 MiB 读取截断提示。
    @ViewBuilder
    private func docBody(_ kind: SpecRuneDocKind) -> some View {
        if let doc = detail.docs[kind] {
            // 正文按块交给独立的 ChatMarkdownView（块间距 0 由 Textual 自己给）；
            // 外层已有 ScrollView，容器不再嵌套滚动；长正文靠「显示更多」逐段追加。
            SpecRuneChunkedMarkdown(text: doc.content)
            if doc.truncated {
                SpecRuneTruncationNote(bytes: doc.bytes)
            }
        } else {
            Text("该任务没有这份文档")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText(colorScheme))
        }
    }

    /// 单个文档维度：调研/记录走多文件清单，其它文档渲染单份正文。
    @ViewBuilder
    private func docTab(_ kind: SpecRuneDocKind) -> some View {
        switch kind {
        case .research:
            researchBody
        case .record:
            recordBody
        default:
            docBody(kind)
        }
    }

    /// 调研清单：清单非空时用它；否则退化为单文件 `research.md`（与面板同形态）。
    private var researchItems: [SpecRuneResearchFile] {
        if !detail.researchFiles.isEmpty { return detail.researchFiles }
        guard let doc = detail.docs[.research] else { return [] }
        return [SpecRuneResearchFile(
            name: SpecRuneDocKind.research.fileName,
            bytes: doc.bytes,
            truncated: doc.truncated,
            content: doc.content
        )]
    }

    /// 记录清单：会话记录已按文件名倒序，`record.md` 固定附在末尾。
    private var recordItems: [SpecRuneSessionRecord] {
        var items = detail.sessionRecords
        if let doc = detail.docs[.record] {
            items.append(SpecRuneSessionRecord(
                name: SpecRuneDocKind.record.fileName,
                at: "",
                bytes: doc.bytes,
                truncated: doc.truncated,
                content: doc.content,
                body: doc.content,
                meta: SpecRuneSessionMeta()
            ))
        }
        return items
    }

    /// 当前展开的调研项：nil 表示还没点过（默认展开第一项），"" 表示全部收起。
    private var openResearchName: String {
        openResearch ?? researchItems.first?.name ?? ""
    }

    private var openRecordName: String {
        openRecord ?? recordItems.first?.name ?? ""
    }

    private func toggleResearch(_ name: String) {
        withAnimation(expandAnimation) {
            openResearch = openResearchName == name ? "" : name
        }
    }

    private func toggleRecord(_ name: String) {
        withAnimation(expandAnimation) {
            openRecord = openRecordName == name ? "" : name
        }
    }

    /// 调研维度：标题「调研报告」+ 计数，逐项展开 Markdown。
    private var researchBody: some View {
        let items = researchItems
        return sectionBlock(title: "调研报告", trailing: "\(items.count)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    SpecRuneDocListRow(
                        name: item.name,
                        bytes: item.bytes,
                        truncated: item.truncated,
                        isOpen: openResearchName == item.name,
                        onToggle: { toggleResearch(item.name) }
                    ) {
                        SpecRuneChunkedMarkdown(text: item.content)
                    }
                }
            }
        }
    }

    /// 记录维度：标题「记录」+ 计数；展开先 meta 行，再显示去 frontmatter 的正文。
    private var recordBody: some View {
        let items = recordItems
        return sectionBlock(title: "记录", trailing: "\(items.count)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    SpecRuneDocListRow(
                        name: item.name,
                        at: item.at,
                        bytes: item.bytes,
                        truncated: item.truncated,
                        isOpen: openRecordName == item.name,
                        onToggle: { toggleRecord(item.name) }
                    ) {
                        if let line = metaLine(item.meta) {
                            Text(verbatim: line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        }
                        // 面板在 body 为空时回退显示含 frontmatter 的全文。
                        SpecRuneChunkedMarkdown(
                            text: item.body.isEmpty ? item.content : item.body
                        )
                    }
                }
            }
        }
    }

    /// meta 展示行：title · status · created · branch，空值省略。
    private func metaLine(_ meta: SpecRuneSessionMeta) -> String? {
        let parts = [meta.title, meta.status, meta.created, meta.branch]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 概览：与 DSH 面板同颗粒度——进度 / 检查清单 / 上下文 / 关联。
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if let progress = SpecRunePresentation.progress(summary) {
                sectionBlock(title: "进度 · \(progress.label)", trailing: "\(progress.done) / \(progress.total)") {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                }
            }

            // 检查清单：恒显示，空态如实说明（面板同款）。
            let checks = SpecRunePresentation.checklist(from: detail)
            sectionBlock(
                title: "检查清单",
                trailing: checks.isEmpty ? "无" : "\(checks.filter(\.checked).count)/\(checks.count)"
            ) {
                if checks.isEmpty {
                    emptyNote("无检查清单（implement.md 无勾选项）")
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(checks.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                AppSymbol(item.checked ? "checkmark.square.fill" : "square", size: 14)
                                    .foregroundStyle(item.checked
                                        ? AppTheme.secondaryText(colorScheme)
                                        : AppTheme.secondaryText(colorScheme))
                                Text(verbatim: item.text)
                                    .font(.subheadline)
                                    .foregroundStyle(item.checked ? AppTheme.secondaryText(colorScheme) : .primary)
                                    .strikethrough(item.checked, color: AppTheme.secondaryText(colorScheme))
                            }
                        }
                    }
                }
            }

            // 上下文：文件名 chips，理由放 accessibility（面板用 tooltip）。
            sectionBlock(title: "上下文", trailing: "\(detail.context.count)") {
                if detail.context.isEmpty {
                    emptyNote("无上下文记录")
                } else {
                    FlowChips(items: detail.context)
                }
            }

            // 关联：规范引用 + 共享规范的任务。
            sectionBlock(title: "关联", trailing: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("规范引用")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                    if let refs = summary.specRefs, !refs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(refs, id: \.self) { path in
                                specRow(path)
                            }
                        }
                    } else {
                        emptyNote("没有规范引用")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(SpecRunePresentation.statusLabel(summary.status))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(AppTheme.groupedFill(colorScheme), in: .capsule)
                if let priority = summary.priority {
                    SpecRunePriorityChip(priority: priority)
                }
                if summary.active == true {
                    Text("当前会话任务")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: .capsule)
                }
                Spacer()
            }
            HStack(spacing: 14) {
                if let assignee = summary.assignee, !assignee.isEmpty {
                    Label(assignee, appSymbol: "person.crop.circle")
                }
                if let created = summary.createdAt {
                    Label(created, appSymbol: "clock")
                }
                Text(verbatim: summary.dir)
                    .font(.caption.monospaced())
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText(colorScheme))
        }
    }

    /// 一个概览小节：标题 + 右侧计数 + 内容。
    private func sectionBlock<Content: View>(
        title: String,
        trailing: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if let trailing {
                    Text(verbatim: trailing)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                }
            }
            content()
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText(colorScheme))
    }

    // MARK: - 规范引用

    private func specSection(_ refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("规范引用").font(.headline)
            ForEach(refs, id: \.self) { path in
                specRow(path)
            }
        }
    }

    private func specRow(_ path: String) -> some View {
        let isOpen = expandedSpec == path
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(expandAnimation) {
                    expandedSpec = isOpen ? nil : path
                }
                if !isOpen {
                    Task { await model.loadSpec(repo: repo, path: path) }
                }
            } label: {
                HStack(spacing: 6) {
                    AppSymbol(isOpen ? "chevron.down" : "chevron.right", size: 12)
                    Text(verbatim: name)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isOpen {
                switch model.spec(repo: repo, path: path) {
                case .idle, .loading:
                    ProgressView().controlSize(.small)
                case let .failed(message):
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(.red)
                case let .loaded(file):
                    SpecRuneChunkedMarkdown(text: file.content)
                    if file.truncated {
                        SpecRuneTruncationNote(bytes: file.size)
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

}

// MARK: - 展示派生（UI 语义，不进 SpecRuneKit）

private enum SpecRunePresentation {
    static func statusLabel(_ status: String) -> String {
        switch status {
        case "planning": "规划中"
        case "in_progress": "进行中"
        case "completed": "已完成"
        case "blocked": "受阻"
        case "canceled": "已取消"
        default: status
        }
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "planning": .secondary.opacity(0.6)
        case "in_progress": .blue
        case "completed": .green
        case "blocked": .orange
        case "canceled": .secondary
        default: .secondary
        }
    }

    /// 从 implement.md 解析 `- [ ]` 勾选项（与面板 parseChecklist 同规则）。
    static func checklist(from detail: SpecRuneTaskDetail) -> [SpecRuneChecklistItem] {
        guard let markdown = detail.docs[.implement]?.content else { return [] }
        var items: [SpecRuneChecklistItem] = []
        var inFence = false
        for line in markdown.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") || trimmed.hasPrefix("+ [") {
                guard trimmed.count > 5 else { continue }
                let markIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
                let checked = trimmed[markIndex] == "x" || trimmed[markIndex] == "X"
                let text = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                items.append(SpecRuneChecklistItem(checked: checked, text: text))
            } else if !inFence, !items.isEmpty, line.hasPrefix("  "), !trimmed.isEmpty {
                let last = items.removeLast()
                items.append(SpecRuneChecklistItem(checked: last.checked, text: last.text + " " + trimmed))
            }
        }
        return items
    }

    /// 进度：有子任务用子任务，否则用 implement 清单（与面板同口径）。
    static func progress(_ task: SpecRuneTaskSummary) -> (done: Int, total: Int, label: String)? {
        let childTotal = task.children?.count ?? 0
        if childTotal > 0 {
            return (task.childDone ?? 0, childTotal, "子任务")
        }
        let implTotal = task.implTotal ?? 0
        if implTotal > 0 {
            return (task.implDone ?? 0, implTotal, "实施清单")
        }
        return nil
    }

    /// 清单项大小：KB，至少显示 1（与面板 `max(1, round(bytes / 1024))` 同口径）。
    static func kbLabel(_ bytes: Int) -> String {
        "\(max(1, Int((Double(max(bytes, 0)) / 1024).rounded()))) KB"
    }
}

struct SpecRuneChecklistItem {
    let checked: Bool
    let text: String
}

/// 上下文 chips：横向换行铺开（面板同款的文件名 chip）。
private struct FlowChips: View {
    let items: [SpecRuneContextRow]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 用自适应网格代替手写换行：宽度变了自动重排。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(items) { row in
                Text(verbatim: row.example ? "（示例）" : (row.file as NSString).lastPathComponent)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.groupedFill(colorScheme), in: .rect(cornerRadius: 6))
                    .accessibilityLabel(Text(verbatim: row.reason.isEmpty ? row.file : "\(row.file)：\(row.reason)"))
            }
        }
    }
}

/// 文档正文的分段渲染容器。
///
/// 正文按 Markdown 行边界切成每段 ≤ 16 000 字符（`SpecRuneDocChunks`），默认
/// 只渲染第 1 段，点「显示更多」追加下一段。16000 字符是 `ChatMarkdownView`
/// 单次渲染的安全上限（1 MiB / 数万短段落会触发 SwiftUI `Text.resolve` 递归
/// 爆栈，2026-11-24 实跑 SIGSEGV）；一次性渲染几十段在真机上仍会卡死/闪退，
/// 所以用按钮显式追加，而不是全部铺开。
///
/// 真实调研文件很小（本仓库 65 份平均 8 KB、最大约 30 KB），绝大多数文件
/// 一段就能看完；只有接近或超过 16 000 字符时才需要点「显示更多」。
/// 外层已有 `ScrollView`（任务详情页），容器内不再嵌套滚动。
private struct SpecRuneChunkedMarkdown: View {
    let text: String
    @State private var chunked = Chunked()
    /// 已渲染的段数；点「显示更多」每次追加 1 段。
    @State private var visibleChunks = 1

    /// 切分结果与产生它的正文：正文变化后、新切分完成前不渲染旧段。
    private struct Chunked {
        var text = ""
        var chunks: [String] = []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chunked.text == text {
                ForEach(chunked.chunks.prefix(visibleChunks).indices, id: \.self) { index in
                    ChatMarkdownView(
                        text: chunked.chunks[index],
                        blockSpacing: 0,
                        reservesStreamingHeight: false
                    )
                }
                if visibleChunks < chunked.chunks.count {
                    Button {
                        visibleChunks = min(chunked.chunks.count, visibleChunks + 1)
                    } label: {
                        Text("显示更多（剩余 \(chunked.chunks.count - visibleChunks) 段）")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.top, 4)
                }
            }
        }
        .task(id: text) {
            let requested = text
            let chunks = await Task.detached(priority: .userInitiated) {
                SpecRuneDocChunks.split(requested)
            }.value
            // 正文已切换时 .task 会被取消：丢弃旧切分，避免写回旧 text 后守卫失败。
            guard !Task.isCancelled else { return }
            chunked = Chunked(text: requested, chunks: chunks)
            visibleChunks = 1
        }
    }
}

/// 数据层 1 MiB 截断提示：1 MiB 是读取上限，不是展示上限。
private struct SpecRuneTruncationNote: View {
    let bytes: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: "原文超过 1 MiB，仅读取前 1 MiB（原始 \(bytes) 字节）")
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText(colorScheme))
    }
}

/// 调研/记录清单的一行：箭头 + 文件名 + 可选时间 + 大小；展开区显示正文。
private struct SpecRuneDocListRow<Content: View>: View {
    let name: String
    /// 记录时间（调研清单不显示）。
    let at: String
    let bytes: Int
    let truncated: Bool
    let isOpen: Bool
    let onToggle: () -> Void
    let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        name: String,
        at: String = "",
        bytes: Int,
        truncated: Bool,
        isOpen: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.name = name
        self.at = at
        self.bytes = bytes
        self.truncated = truncated
        self.isOpen = isOpen
        self.onToggle = onToggle
        self.content = content
    }

    /// VoiceOver 播报：文件名 + 记录时间（有则拼上）+ 大小。
    private var accessibilityText: String {
        let size = SpecRunePresentation.kbLabel(bytes)
        return at.isEmpty ? "\(name)，\(size)" : "\(name)，\(at)，\(size)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    AppSymbol(isOpen ? "chevron.down" : "chevron.right", size: 11)
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                    Text(verbatim: name)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !at.isEmpty {
                        Text(verbatim: at)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText(colorScheme))
                            .lineLimit(1)
                    }
                    Text(verbatim: SpecRunePresentation.kbLabel(bytes))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: accessibilityText))
            .accessibilityValue(Text(verbatim: isOpen ? "已展开" : "已收起"))

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                    if truncated {
                        SpecRuneTruncationNote(bytes: bytes)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.groupedFill(colorScheme), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.secondaryControlStroke(colorScheme).opacity(0.5))
        )
    }
}

private struct SpecRunePriorityChip: View {
    let priority: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: priority)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                priority == "P0" ? Color.red.opacity(0.16) : AppTheme.groupedFill(colorScheme),
                in: .rect(cornerRadius: 5)
            )
            .foregroundStyle(priority == "P0" ? Color.red : AppTheme.secondaryText(colorScheme))
    }
}

private struct SpecRuneProgressBar: View {
    let done: Int
    let total: Int
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.groupedFill(colorScheme))
                Capsule().fill(tint.opacity(0.7))
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 4)
    }

    private var ratio: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(done) / CGFloat(total))
    }
}
