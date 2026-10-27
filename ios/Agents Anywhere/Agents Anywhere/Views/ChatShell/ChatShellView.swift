import SwiftUI
import UIKit

struct ChatShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var sidebar = ChatSidebarState()
    @State private var newSessionPresentationID = UUID()
    /// 会话页/新会话页 composer 玻璃共享的 namespace：detail 切换时同 ID
    /// glass 做 matched 过渡，避免新页 glass 单独"泡泡式"出现（Duo 横屏
    /// 宽 detail 下肉眼可见的大圆闪现）。
    @Namespace private var composerGlass
    /// 宽 detail（>1000pt，Duo 横屏）：新会话/头像迁到右缘竖排 toolbar，
    /// 侧栏底栏清空。onGeometryChange 驱动，旋转时一次重建可接受。
    @State private var isWideDetail = false
    @State private var showsRailAccountSettings = false
    private var selection: ChatShellSelection {
        get { appState.chatSelection }
        nonmutating set { appState.chatSelection = newValue }
    }

    var body: some View {
        // NavigationSplitView adapts to a single stack in a compact system size
        // class. Use that same system trait for the drawer fallback, never a
        // device model, screen measurement or custom window-width breakpoint.
        let layout = ChatSidebarState.Layout.resolve(
            hasRegularWidth: horizontalSizeClass == .regular
        )
        // Regular width keeps the native split sidebar. The two-tab shell is
        // exclusive to the iPhone Duo cover screen: its narrow strip is the
        // only compact width where the drawer hurts. Bar phones share the
        // compact trait with it, so the model id is the one reliable signal —
        // the "never a device model" rule above cannot express this split.
        // Extend the set when more foldables land.
        Group {
            if layout == .regularSplit || !isDuoFoldableIPhone {
                sidebarLayout(layout)
            } else {
                CompactChatShellView()
            }
        }
        .onChange(of: layout, initial: true) { _, next in sidebar.setLayout(next) }
        .task(id: NewSessionLoadKey(target: appState.nativeChatServices?.newSession.refreshKey,
            presentationID: newSessionPresentationID)) {
            // Warm the next draft even when launch restores a session/device.
            // Remounting the welcome view no longer starts its first data load.
            guard let model = appState.nativeChatServices?.newSession else { return }
            await model.refresh(connectors: appState.connectors)
        }
        .alert(String(localized: "Could not update session"), isPresented: sessionActionErrorBinding) {
            Button(String(localized: "OK"), role: .cancel) {
                appState.dismissSessionActionError()
            }
        } message: {
            Text(appState.sessionActionError ?? "")
        }
        .sheet(item: agentSetupBinding) { connector in
            if let services = appState.nativeChatServices {
                AgentSetupSheet(connector: connector, model: services.agents(on: connector.id)) {
                    services.agentSetup.finish(connector.id)
                    Task { await appState.refreshDashboard() }
                }
            }
        }
        .onChange(of: visibleSessionID, initial: true) { _, id in
            appState.setVisibleSession(id)
        }
        .onDisappear { appState.setVisibleSession(nil) }
    }

    private var agentSetupBinding: Binding<V2Connector?> {
        Binding(get: { appState.nativeChatServices?.agentSetup.presentedConnector }, set: { value in
            if value == nil, let setup = appState.nativeChatServices?.agentSetup, let connector = setup.presentedConnector {
                setup.finish(connector.id)
            }
        })
    }

    private var sidebarDevices: [ChatSidebarDevice] {
        appState.connectors.map { connector in
            ChatSidebarDevice(connector: connector)
        }
    }

    private var sidebarAccount: ChatSidebarAccount? {
        guard let me = appState.me else { return nil }
        return ChatSidebarAccount(me: me, avatarSource: appState.accountAvatarSource)
    }

    private var sidebarSessions: [ChatSidebarSession] {
        appState.sessions
            .filter { !$0.archived }
            .map { session in
                ChatSidebarSession(session: session)
            }
            .sorted { $0.presentation.precedes($1.presentation, id: $0.id, otherID: $1.id) }
    }

    private var visibleSessionID: V2SessionID? {
        scenePhase == .active && !sidebar.obscuresDetail ? selectedSessionId : nil
    }

    /// 右缘竖排的头像按钮：行为同侧栏头像（打开账号设置）。
    @ViewBuilder private var railAccountButton: some View {
        if let account = sidebarAccount {
            Button { showsRailAccountSettings = true } label: {
                AccountAvatarView(displayName: account.displayName,
                    source: account.avatarSource, size: 38)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(String(localized: "账号"))
            .sheet(isPresented: $showsRailAccountSettings) {
                AccountSettingsSheet(appState: appState)
            }
        }
    }

    private func sidebarLayout(_ layout: ChatSidebarState.Layout) -> some View {
        // Map and sort the session list once per body, not once per section.
        let sessions = sidebarSessions
        let services = appState.nativeChatServices
        return SidebarDrawer(
            isOpen: sidebarBinding(for: layout),
            presentation: layout == .regularSplit ? .nativeSidebar : .drawer,
            configuration: .chat
        ) { _ in
            // 侧栏头部（新会话/头像）不随键盘避让上移：键盘是 detail 列
            // 输入框的事，侧栏顶上来只会挤走会话列表空间。
            ChatSidebarHeaderView()
                .ignoresSafeArea(.keyboard)
        } sidebar: { safeAreaInsets in
            ChatSidebarView(
                appState: appState,
                agentSetup: services?.agentSetup,
                safeAreaInsets: safeAreaInsets,
                devices: sidebarDevices,
                pinnedSessions: sessions.filter(\.pinned),
                recentSessions: sessions.filter { !$0.pinned },
                repository: services?.dashboardRepository,
                onNewProjectSession: startProjectSession,
                onRestoreSession: { await appState.setSessionArchived(sessionId: $0, archived: false) },
                account: sidebarAccount,
                // 宽 detail（Duo 横屏）新会话/头像移到右缘竖排 toolbar，
                // 侧栏底栏清空不重复。
                showsBottomControls: !isWideDetail,
                selectedDeviceId: selectedDeviceId,
                selectedSessionId: selectedSessionId,
                isLoadingDevices: appState.isDashboardLoading && !appState.hasLoadedConnectors,
                isLoadingSessions: appState.isDashboardLoading && !appState.hasLoadedSessions,
                onNewSession: startNewSession,
                onOpenDevice: openDevice,
                onOpenSession: openSession,
                onRenameSession: renameSession,
                onToggleSessionPinned: setSessionPinned,
                onArchiveSession: archiveSession,
                onCopyDeviceId: copyDeviceId,
                onCopySessionId: copySessionId
            )
            // 直板抽屉形态的防御层：弹键盘后展开侧栏的转场中，键盘
            // safe area 变化与 ScrollView 布局可能互相触发循环（真机
            // 曾剧烈抖动）。根因已在 NativeComposerEditor（异步焦点块
            // 改读实时意图），此挂载保留双保险；底栏随键盘上移在抽屉
            // 形态留作遗留（insets 是 GeometryReader 参数污染，修在
            // 内容层无效）。
            .ignoresSafeArea(.keyboard)
        } content: { safeAreaInsets in
            mainContent
                .modifier(ChatDetailNavigation(insets: safeAreaInsets))
                .environment(\.composerGlassNamespace, composerGlass)
                // "Duo 横屏"信号：系统在此形态把 toolbar 重排成右缘竖排。
                // 注意 size 是 detail 列（横屏 ≈600×669，宽高比 0.9；竖屏
                // 展开 ≈640×1300，比 0.49）——用宽高比 >0.75 区分，加机型
                // 条件不误伤 iPad/竖屏。图标恒定不切换内容——该路径对
                // label 内容切换有系统 bug（玻璃大圆，2026-10-27）。
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    isWideDetail = isDuoFoldableIPhone
                        && size.height > 0 && size.width / size.height > 0.75
                }
                .toolbar {
                    if isWideDetail {
                        ToolbarItem(placement: .topBarTrailing) {
                            AppGlassButton(systemImage: "square.and.pencil",
                                style: .prominent, maxWidth: nil, action: startNewSession)
                                .accessibilityLabel(String(localized: "新会话"))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            railAccountButton
                        }
                    }
                }
        }
    }

    private func sidebarBinding(for layout: ChatSidebarState.Layout) -> Binding<Bool> {
        Binding(get: { sidebar.isOpen(in: layout) }, set: { isOpen in
            sidebar.setLayout(layout)
            sidebar.isOpen = isOpen
        })
    }

    private var selectedDeviceId: V2ConnectorID? {
        guard case let .device(id) = selection else { return nil }
        return id
    }

    private var selectedSessionId: V2SessionID? {
        guard case let .session(id) = selection else { return nil }
        return id
    }

    private var selectedContentTitle: String? {
        switch selection {
        case .newSession:
            return nil
        case let .device(id):
            return appState.connectors.first { $0.id == id }?.name
        case let .session(id):
            return appState.sessions.first { $0.id == id }?.title
        }
    }

    private var sessionActionErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.sessionActionError != nil },
            set: { isPresented in
                if !isPresented {
                    appState.dismissSessionActionError()
                }
            }
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if case let .device(connectorId) = selection,
           let connector = appState.connectors.first(where: { $0.id == connectorId }),
           let clients = appState.nativeChatServices,
           let service = appState.deviceManagementService,
           let workspaceFilesService = appState.workspaceFilesService,
           let serverURL = appState.serverURL
        {
            DeviceManagementView(
                connector: connector,
                allSessions: appState.sessions,
                projects: appState.projects,
                agents: clients.agents(on: connectorId),
                dashboard: clients.dashboardRepository,
                service: service,
                workspaceFilesService: workspaceFilesService,
                serverURL: serverURL,
                onMenu: toggleSidebar,
                onOpenSession: openSession,
                onNewSession: { path in
                    if let model = appState.nativeChatServices?.newSession {
                        model.focusDevice(connectorId, workspace: path)
                    }
                    startNewSession()
                },
                onNewProjectSession: startProjectSession,
                onConnectorUpdated: appState.updateConnector,
                onConnectorDeleted: removeConnector,
                onSessionsUpdated: appState.updateSessions,
                onSetSessionsArchived: appState.setSessionsArchived
            )
            .id(connectorId)
        } else if let services = appState.nativeChatServices {
            if case let .session(id) = selection {
                let session = services.sessionRepository.session(id: id)
                let connectorID = session.metadata?.connectorId ?? appState.sessions.first { $0.id == id }?.connectorId
                SessionChatView(session: session, services: services,
                    deviceName: appState.connectors.first { $0.id == connectorID }?.name,
                    onMenu: toggleSidebar)
                    .equatable()
                    .id(id)
            } else {
                NewSessionView(model: services.newSession, connectors: appState.connectors, sessions: appState.sessions, repository: services.dashboardRepository,
                    dashboardLoading: appState.isDashboardLoading,
                    dashboardError: appState.connectorsError,
                    onMenu: toggleSidebar,
                    onOpenDevice: openDevice,
                    onCreated: { session in
                        appState.updateSession(session)
                        if case .newSession = selection { openSession(session.id) }
                    },
                    onRefresh: { await appState.refreshDashboard(); return appState.connectors })
                    .equatable()
                    .id(newSessionPresentationID)
            }
        } else {
            ChatShellPlaceholderPage(
                isConnecting: appState.isRetryingServerConnection,
                title: selectedContentTitle ?? "",
                onOpenSidebar: openSidebar
            )
        }
    }

    private func startProjectSession(_ id: String) {
        guard let services = appState.nativeChatServices else { return }
        services.newSession.updateProjects(services.dashboardRepository.projects)
        guard services.newSession.selectProject(id) else { return }
        startNewSession()
    }

    private func startNewSession() {
        // Reselecting this destination must also remount its local presentation
        // state, including the welcome reveal. The account still owns the draft.
        // 共享 draft 会把上一页的聚焦状态带进新页：异步焦点块随后弹起
        // 键盘又收起，横屏下像底部闪现一个大玻璃圆（真机报告）。
        // 进新会话页不继承焦点，键盘不弹。
        appState.nativeChatServices?.newSession.draft.isFocused = false
        newSessionPresentationID = UUID()
        selection = .newSession
        sidebar.selectDestination()
    }

    private func openDevice(_ id: V2ConnectorID) {
        selection = .device(id)
        sidebar.selectDestination()
    }

    private func openSession(_ id: V2SessionID) {
        selection = .session(id)
        sidebar.selectDestination()
    }

    private func removeConnector(_ id: V2ConnectorID) {
        appState.removeConnector(connectorId: id)
        selection = .newSession
    }

    private func renameSession(_ id: V2SessionID, title: String) {
        Task {
            _ = await appState.renameSession(sessionId: id, title: title)
        }
    }

    private func setSessionPinned(_ id: V2SessionID, pinned: Bool) {
        Task {
            _ = await appState.setSessionPinned(sessionId: id, pinned: pinned)
        }
    }

    private func archiveSession(_ id: V2SessionID) {
        Task {
            let shouldArchive = appState.sessions.first { $0.id == id }?.archived != true
            let changed = await appState.setSessionArchived(sessionId: id, archived: shouldArchive)
            if changed && shouldArchive, selectedSessionId == id {
                selection = .newSession
            }
        }
    }

    private func copyDeviceId(_ id: V2ConnectorID) {
        UIPasteboard.general.string = id
    }

    private func copySessionId(_ id: V2SessionID) {
        UIPasteboard.general.string = id
    }

    private func toggleSidebar() {
        sidebar.isOpen.toggle()
    }

    private func openSidebar() {
        sidebar.isOpen = true
    }
}

private struct NewSessionLoadKey: Equatable {
    let target: NewSessionRefreshKey?
    let presentationID: UUID
}

private struct ChatShellPlaceholderPage: View {
    let isConnecting: Bool
    let title: String
    let onOpenSidebar: () -> Void

    var body: some View {
        Color(.systemBackground)
            .overlay {
                if isConnecting {
                    Label(String(localized: "正在连接，首次同步后即可保留本地内容"), appSymbol: "network")
                        .font(.footnote).foregroundStyle(.secondary).padding(24)
                }
            }
            .modifier(ChatPageToolbar(title: title, onMenu: onOpenSidebar))
    }
}

#Preview {
    ChatShellView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
