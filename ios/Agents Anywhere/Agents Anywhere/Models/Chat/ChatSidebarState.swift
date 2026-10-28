import Foundation

/// Selecting content dismisses an overlay, but preserves a regular-width split.
nonisolated struct ChatSidebarState: Equatable {
    /// 设置项存储键（AccountSettingsSheet「启动时展开侧栏」）。
    static let openOnLaunchDefaultsKey = "chat.sidebar.openOnLaunch"
    /// 「侧栏状态记忆」开关 + 上次分栏侧栏开合快照（优先级高于
    /// openOnLaunch：开启时启动恢复上次状态）。
    static let rememberStateDefaultsKey = "chat.sidebar.rememberState"
    static let lastOpenDefaultsKey = "chat.sidebar.lastOpen"

    enum Layout {
        case drawer, regularSplit

        static func resolve(hasRegularWidth: Bool) -> Layout {
            hasRegularWidth ? .regularSplit : .drawer
        }
    }
    private(set) var layout = Layout.drawer
    var isOpen = false
    /// 分栏形态的启动默认（设置项，UserDefaults 持久化）。抽屉形态恒
    /// 闭合启动——抽屉盖内容，默认展开会挡住会话。
    var defaultOpen: Bool

    init(defaultOpen: Bool = true) {
        self.defaultOpen = defaultOpen
    }

    var obscuresDetail: Bool { layout != .regularSplit && isOpen }

    func isOpen(in next: Layout) -> Bool {
        // A newly mounted navigation host needs its destination state before
        // onChange commits the new layout, otherwise a narrow window flashes
        // an open drawer and immediately animates it closed.
        layout == next ? isOpen : next == .regularSplit && defaultOpen
    }

    mutating func setLayout(_ next: Layout) {
        guard layout != next else { return }
        isOpen = isOpen(in: next)
        layout = next
    }

    mutating func selectDestination() {
        if layout != .regularSplit { isOpen = false }
    }
}
