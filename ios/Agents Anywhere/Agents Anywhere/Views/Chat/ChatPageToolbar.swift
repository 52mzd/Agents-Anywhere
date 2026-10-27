import SwiftUI

/// The phone drawer needs a navigation host inside its moving card. The iPad
/// detail already has the NavigationSplitView's host; nesting another stack
/// there would duplicate navigation chrome and safe-area handling.
struct ChatDetailNavigation: ViewModifier {
    let insets: EdgeInsets
    @Environment(\.sidebarDrawerPresentation) private var presentation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        Group {
            if presentation == .drawer {
                NavigationStack { content }
                    .ignoresSafeArea(.keyboard)
                    // Preserve the drawer's stable, untransformed safe area,
                    // including keyboard avoidance. Pages add no other inset.
                    .padding(insets)
            } else {
                content
            }
        }
        .background(Color(uiColor: .systemBackground))
        .tint(AppTheme.primaryControlBackground(colorScheme))
    }
}

/// Duo 横屏右缘竖排注入的动作（ChatShellView 持有，页面级 toolbar 消费
/// ——shell 级 toolbar 项不进竖排，见 ChatPageToolbar.railTrailing）。
struct ChatRailContext {
    let onNewSession: () -> Void
    let onAccount: () -> Void
    /// 真实头像（缓存 UIImage）；竖排容器只收零修饰 label，此处不做
    /// frame/裁剪，交给系统按钮样式。
    var avatarImage: UIImage?
}

private struct ChatRailKey: EnvironmentKey {
    static let defaultValue: ChatRailContext? = nil
}
extension EnvironmentValues {
    var chatRail: ChatRailContext? {
        get { self[ChatRailKey.self] }
        set { self[ChatRailKey.self] = newValue }
    }
}

/// 右缘竖排按钮（零修饰图标——系统竖排容器拒收带修饰/自定义结构的
/// label；头像用零修饰 UIImage，有图显图、无图 symbol）。
func chatRailButtons(_ rail: ChatRailContext) -> [AnyView] {
    [
        AnyView(Button(action: rail.onNewSession) { AppSymbol("square.and.pencil") }
            .accessibilityLabel(String(localized: "新会话"))),
        AnyView(Button(action: rail.onAccount) {
            if let avatar = rail.avatarImage {
                Image(uiImage: avatar)
            } else {
                AppSymbol("person.crop.circle")
            }
        }
        .accessibilityLabel(String(localized: "账号")))
    ]
}

/// Native title/subtitle placements and toolbar items own size, spacing, glass
/// grouping and scroll-edge rendering. No header view sits in the timeline.
struct ChatPageToolbar: ViewModifier {
    let title: String
    var subtitle: String?
    var status: ChatHeaderStatus?
    var alignsTitleLeading = false
    let onMenu: () -> Void
    /// Duo 横屏（宽 detail，系统 toolbar 收编成右缘竖排）时追加的尾部
    /// 按钮。必须挂在页面级——shell 级 toolbar 项不进竖排（2026-10-27
    /// 实证：页面级 folder/… 进竖排，shell 级新会话/头像留顶部）。
    var railTrailing: [AnyView] = []

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(alignsTitleLeading ? "" : subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onMenu) { SidebarMenuIcon() }
                        .accessibilityLabel(String(localized: "打开侧栏"))
                }
                ForEach(railTrailing.indices, id: \.self) { index in
                    ToolbarItem(placement: .topBarTrailing) { railTrailing[index] }
                }
                if alignsTitleLeading {
                    // Use the title region's available width. A leading bar
                    // item is sized as a control and can collapse to its minimum
                    // width even when there is space between the buttons.
                    ToolbarItem(placement: .principal) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.headline).lineLimit(1)
                                .accessibilityAddTraits(.isHeader)
                            if subtitle != nil || status != nil {
                                ChatToolbarSubtitle(subtitle: subtitle, status: status)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else if subtitle != nil || status != nil {
                    ToolbarItem(placement: .subtitle) {
                        ChatToolbarSubtitle(subtitle: subtitle, status: status)
                    }
                }
            }
    }
}

private struct ChatToolbarSubtitle: View {
    let subtitle: String?
    let status: ChatHeaderStatus?
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 16

    private var text: String {
        [subtitle, status?.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 4) {
            if let status {
                Group {
                    if status.isProgress { ProgressView().controlSize(.mini) }
                    else { AppSymbol(status.symbol, size: 12) }
                }.frame(width: lineHeight, height: lineHeight)
            }
            Text(verbatim: text).lineLimit(1)
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(height: lineHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([subtitle, status?.detail].compactMap { $0 }.joined(separator: " · "))
    }
}

struct SidebarMenuIcon: View {
    var body: some View {
        AppSymbol("sidebar.left", size: 22).accessibilityHidden(true)
    }
}
