import SwiftUI
import UIKit

/// 上下双区域宿主：iPhone Duo 半折叠（笔记本姿态）时把 primary（上屏）
/// 与 secondary（下屏）分到铰链两侧，split 自动避开折叠带。
///
/// iOS 27.1 的 arrangement API 只在 UIKit 公开（SwiftUI 无对应符号，
/// SDK 头文件实证见任务 research-duo-api.md），因此用
/// UIViewControllerRepresentable 桥接。
@available(iOS 27.1, *)
struct DuoArrangementHost<Primary: View, Secondary: View>: UIViewControllerRepresentable {
    let primary: Primary
    let secondary: Secondary
    /// 挂在容器自身 view 上的铰链回调：容器挂载期间外层 SwiftUI
    /// background 的监听会断链（真机实测），必须由容器自己续上。
    var onHinge: (UIHinge?) -> Void = { _ in }

    final class Coordinator {
        var primaryHost: UIHostingController<Primary>?
        var secondaryHost: UIHostingController<Secondary>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIArrangementViewController {
        let vc = UIArrangementViewController()
        let primaryHost = UIHostingController(rootView: primary)
        let secondaryHost = UIHostingController(rootView: secondary)
        primaryHost.view.backgroundColor = .clear
        secondaryHost.view.backgroundColor = .clear
        primaryHost.sizingOptions = []
        secondaryHost.sizingOptions = []
        vc.setViewController(primaryHost, for: .primary)
        vc.setViewController(secondaryHost, for: .secondary)
        // 半折叠时自动上下分（上午真机/模拟器对照验证过的最简配置）。
        vc.updateArrangement(.split)
        vc.view.addInteraction(UIHingeInteraction { _, update in
            onHinge(update.hinge)
        })
        context.coordinator.primaryHost = primaryHost
        context.coordinator.secondaryHost = secondaryHost
        return vc
    }

    func updateUIViewController(_ vc: UIArrangementViewController, context: Context) {
        context.coordinator.primaryHost?.rootView = primary
        context.coordinator.secondaryHost?.rootView = secondary
    }
}

/// 双屏分支入口：机型 + 半折叠姿态 + iOS 27.1 三重门控。
/// 双屏时输入 dock 走浮层 + keyboardLayoutGuide 锚定（见 Branch 注释）。
enum DuoArrangementGate {
    @ViewBuilder
    static func embedIfSupported<Primary: View, Secondary: View, Fallback: View>(
        primary: Primary,
        secondary: Secondary,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        // 机型契约见 .specrune/spec/ios/duo-layout.md：折叠机型判断必须走
        // isDuoFoldableIPhone（模拟器靠 SIMULATOR_MODEL_IDENTIFIER）。
        if isDuoFoldableIPhone, #available(iOS 27.1, *) {
            DuoArrangementBranch(primary: primary, secondary: secondary, fallback: fallback())
        } else {
            fallback()
        }
    }
}

/// 半折叠时挂 arrangement 容器（上=primary、下=secondary），其他姿态回退。
/// 输入 dock 不进 pane：真机实测 pane 内布局会被 arrangement 截断/重排
/// （键盘下输入框跳位、lift 测量波动），改为恒定浮层 + 系统级
/// keyboardLayoutGuide 锚定（实例不变保焦点，位置零测量误差）。
@available(iOS 27.1, *)
private struct DuoArrangementBranch<Primary: View, Secondary: View, Fallback: View>: View {
    let primary: Primary
    let secondary: Secondary
    let fallback: Fallback
    @State private var partiallyOpen = false

    private func handleHinge(_ hinge: UIHinge?) {
        let next: Bool
        switch hinge?.status {
        case .partiallyOpen: next = true
        case .closed, .fullyOpen: next = false
        case nil, .unknown: return
        }
        if next != partiallyOpen { partiallyOpen = next }
    }

    var body: some View {
        Group {
            if partiallyOpen {
                GeometryReader { geo in
                    DuoArrangementHost(
                        primary: primary,
                        // 下屏只放固定高度占位（维持上下分区，消息流不进下屏）；
                        // 真实 dock 由浮层承载。
                        secondary: Color.clear.frame(height: geo.size.height * 0.45),
                        onHinge: handleHinge)
                    .ignoresSafeArea(.keyboard)
                    .overlay {
                        DuoKeyboardDock(dock: secondary)
                    }
                }
            } else {
                fallback
                    .background(DuoHingeFallbackMonitor(onHinge: handleHinge))
            }
        }
    }
}

/// 事件穿透容器：自身空白区域不拦截触摸（消息流的点击/滑动从下方
/// arrangement 透传），仅 dock 子树正常响应。
final class DuoPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

/// 输入 dock 浮层：宿主 view 底边约束到 keyboardLayoutGuide 顶——键盘
/// 弹出时系统精确贴键盘顶，收起时贴屏幕底，dock 实例恒定、焦点稳定。
@available(iOS 27.1, *)
struct DuoKeyboardDock<Dock: View>: UIViewControllerRepresentable {
    let dock: Dock

    final class Coordinator { weak var host: UIHostingController<Dock>? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view = DuoPassthroughView()
        let host = UIHostingController(rootView: dock)
        host.view.backgroundColor = .clear
        // intrinsic 参与尺寸：指令建议面板等向上展开的内容需要 hosting
        // 视图随内容增高，sizingOptions=[] 会把它裁死。
        host.sizingOptions = [.intrinsicContentSize]
        vc.addChild(host)
        vc.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: vc.view.keyboardLayoutGuide.topAnchor),
            // 上边界只设下限：dock 上方的弹出面板（指令列表）可向上生长。
            host.view.topAnchor.constraint(greaterThanOrEqualTo: vc.view.topAnchor),
        ])
        host.didMove(toParent: vc)
        context.coordinator.host = host
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        context.coordinator.host?.rootView = dock
    }
}

/// 回退形态下的铰链监听（进入双屏由它触发；退出由容器自身的监听触发）。
@available(iOS 27.1, *)
struct DuoHingeFallbackMonitor: UIViewRepresentable {
    let onHinge: (UIHinge?) -> Void

    final class Coordinator { var interaction: UIHingeInteraction? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        // hidden 视图的 interaction 不激活（真机实测），用 1x1 透明视图。
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        let interaction = UIHingeInteraction { [onHinge] _, update in
            onHinge(update.hinge)
        }
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
