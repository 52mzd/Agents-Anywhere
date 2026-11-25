import SwiftUI
import UIKit

// MARK: - 数据

enum FlowNodeStatus {
    case done, active, idle, unknown

    var label: String {
        switch self {
        case .done: "已完成"
        case .active: "进行中"
        case .idle: "待命"
        case .unknown: "无信号"
        }
    }
}

struct FlowNodeModel: Identifiable {
    let id: String
    let title: String
    let model: String?
    let status: FlowNodeStatus
    let activity: String
    let progress: Double
    let progressLabel: String
    let footText: String?
    let color: Color
    let colorIndex: Int
    var children: [FlowNodeModel]

    static func makeTree(rootColor: Color) -> FlowNodeModel {
                let plan = [
            node("1.1", "需求探索", "explore", .done, "已确认 6 项事实", 1, .one, "SpecRune prd.md · design.md", 0),
            node("1.2", "调研", "research", .unknown, "无信号", 0, .zero, nil, 0),
            node("1.3", "配置上下文", "context", .done, "7 + 5 条已策展", 1, .one, "SpecRune 清单 12 条", 0),
            node("1.4", "激活任务", "start", .done, "已绑定本会话", 1, .one, nil, 0),
        ]
        let execute = [
            node("2.1", "实现", "implement", .active, "正在复刻卡片与连线", 0.64, .percent(0.64), "SpecRune 4/6 文件已改", 1),
            node("2.2", "新鲜复查", "review", .idle, "等待实现完成", 0, .zero, nil, 1),
            node("2.3", "修复", "fix", .idle, "通常不需要", 0, .zero, nil, 1),
        ]
        let finish = [
            node("3.2", "更新规范", "spec", .idle, "无新增契约", 0, .zero, nil, 2),
            node("3.3", "提交", "commit", .idle, "代码与规范同提", 0, .zero, nil, 2),
            node("3.4", "归档", "archive", .unknown, "验收通过后", 0, .zero, nil, 2),
        ]
        return FlowNodeModel(
            id: "root",
            title: "SpecRune 工作流图",
            model: "@dae · 阶段 2 / 3",
            status: .active,
            activity: "正在复刻卡片、连线与动效",
            progress: 0.62,
            progressLabel: "124k / 200k",
            footText: "最近一次注入",
            color: rootColor,
            colorIndex: 0,
            children: [
                FlowNodeModel(
                    id: "stage-1", title: "Plan 阶段", model: "1.0 → 1.4",
                    status: .done, activity: "prd.md · design.md · 清单 7/5",
                    progress: 1, progressLabel: "200k / 200k",
                    footText: "最近一次注入", color: SpecRuneFlowTokens.nodeColors[0], colorIndex: 0, children: plan
                ),
                FlowNodeModel(
                    id: "stage-2", title: "Execute 阶段", model: "2.1 → 2.3",
                    status: .active, activity: "2.1 实现中 · 4/6 文件已改",
                    progress: 0.58, progressLabel: "116k / 200k",
                    footText: "最近一次注入", color: SpecRuneFlowTokens.nodeColors[1], colorIndex: 1, children: execute
                ),
                FlowNodeModel(
                    id: "stage-3", title: "Finish 阶段", model: "3.2 → 3.4",
                    status: .idle, activity: "等 Execute 收尾",
                    progress: 0, progressLabel: "0 / 200k",
                    footText: "最近一次注入", color: SpecRuneFlowTokens.nodeColors[2], colorIndex: 2, children: finish
                ),
            ]
        )
    }

    private static func node(
        _ id: String, _ title: String, _ model: String, _ status: FlowNodeStatus,
        _ activity: String, _ ratio: Double, _ label: ProgressLabel, _ foot: String?, _ colorIndex: Int
    ) -> FlowNodeModel {
        FlowNodeModel(
            id: id, title: title, model: model, status: status, activity: activity,
            progress: ratio, progressLabel: label.text, footText: foot,
            color: SpecRuneFlowTokens.nodeColors[colorIndex], colorIndex: colorIndex, children: []
        )
    }

    enum ProgressLabel {
        case zero, one, percent(Double)
        var text: String {
            switch self {
            case .zero: "0%"
            case .one: "100%"
            case let .percent(v): "\(Int((v * 100).rounded()))%"
            }
        }
    }
}

// MARK: - 布局

struct FlowLayout {
    let nodeWidth: CGFloat = SpecRuneFlowTokens.cardWidth
    let nodeHeight: CGFloat = SpecRuneFlowTokens.nodeHeight
    let indent: CGFloat = SpecRuneFlowTokens.indent
    let columnGap: CGFloat = SpecRuneFlowTokens.levelGap
    let levelTop: CGFloat = SpecRuneFlowTokens.levelTopMargin
    let nodeGap: CGFloat = SpecRuneFlowTokens.nodeGap
    let padding: CGFloat = 28

    let stageCount: Int
    let childCounts: [Int]

    var columnWidth: CGFloat { nodeWidth + indent }

    var boardWidth: CGFloat {
        padding * 2 + CGFloat(stageCount) * columnWidth
            + CGFloat(max(stageCount - 1, 0)) * columnGap
    }

    var rootRect: CGRect {
        CGRect(x: (boardWidth - nodeWidth) / 2, y: 0, width: nodeWidth, height: nodeHeight)
    }

    var levelY: CGFloat { nodeHeight + levelTop }

    func stageX(_ index: Int) -> CGFloat {
        padding + CGFloat(index) * (columnWidth + columnGap)
    }

    func stageRect(_ index: Int) -> CGRect {
        CGRect(x: stageX(index), y: levelY, width: nodeWidth, height: nodeHeight)
    }

    func childY(_ stage: Int, _ index: Int) -> CGFloat {
        levelY + nodeHeight + nodeGap + CGFloat(index) * (nodeHeight + nodeGap)
    }

    func childRect(_ stage: Int, _ index: Int) -> CGRect {
        CGRect(
            x: stageX(stage) + indent,
            y: childY(stage, index),
            width: nodeWidth,
            height: nodeHeight
        )
    }

    var boardHeight: CGFloat {
        var tallest = levelY + nodeHeight
        for stage in 0 ..< stageCount {
            let count = childCounts[stage]
            guard count > 0 else { continue }
            tallest = max(tallest, childY(stage, count - 1) + nodeHeight)
        }
        return tallest + padding
    }

    func allNodeRects() -> [ (id: String, rect: CGRect, color: Color) ] { [] }
}

// MARK: - 动画时间轴

/// 原版 `data-side`：闪光从卡片的哪一侧升起。
enum GroundSide {
    /// 默认，从底部向上（`n.back` 的反向 hop）。
    case bottom
    /// 宽屏下根节点到一级子节点，旋转 180° 从上往下。
    case top
    /// 二级子节点，宽高互换后旋转 90°，从左往右。
    case left
}

/// 把「连线跑光带 → 节点落地闪光」算成 time 的纯函数，方便每帧重算。
struct FlowTimeline {
    struct Hop {
        let id: String
        let path: Path
        let length: CGFloat
        let targetID: String
        let color: Color
        let side: GroundSide
    }

    let hops: [Hop]
    let nodeRects: [String: CGRect]

    static let hopDuration: Double = 0.38
    /// 下一条 hop 在上一条开始后 300ms 启动（原版 `t += s - 80`）。
    static let hopStep: Double = 0.30
    static let startDelay: Double = 0.7
    static let tailPause: Double = 1.4
    static let glowDuration: Double = SpecRuneFlowTokens.glow

    var cycle: Double {
        guard !hops.isEmpty else { return 4 }
        return Self.startDelay + Double(max(hops.count - 1, 0)) * Self.hopStep + Self.hopDuration + Self.tailPause
    }

    /// 同时活跃的 hop（原版是重叠启动的，可能有多条一起跑）。
    func activeHops(at time: Double) -> [(index: Int, progress: Double)] {
        guard !hops.isEmpty else { return [] }
        let local = time.truncatingRemainder(dividingBy: cycle)
        var result: [(Int, Double)] = []
        for index in hops.indices {
            let start = Self.startDelay + Double(index) * Self.hopStep
            let progress = (local - start) / Self.hopDuration
            if progress >= 0, progress <= 1 {
                result.append((index, progress))
            }
        }
        return result
    }

    /// 节点落地闪光的进度与方向（nil 表示不在闪）。
    func glow(for nodeID: String, at time: Double) -> (rise: Double, side: GroundSide)? {
        guard !hops.isEmpty else { return nil }
        let local = time.truncatingRemainder(dividingBy: cycle)
        for (index, hop) in hops.enumerated() where hop.targetID == nodeID {
            let arrive = Self.startDelay + Double(index) * Self.hopStep + Self.hopDuration
            let delta = local - arrive
            guard delta >= 0, delta < Self.glowDuration else { continue }
            return (delta / Self.glowDuration, hop.side)
        }
        return nil
    }
}

// MARK: - 画布

struct FlowDemoCanvas<Content: View>: UIViewRepresentable {
    let contentSize: CGSize
    var resetToken: Int = 0
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FitScrollView {
        let scroll = FitScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 0.1
        scroll.maximumZoomScale = 2.4
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let host = UIHostingController(rootView: AnyView(
            content().frame(width: contentSize.width, height: contentSize.height)
        ))
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        scroll.addSubview(host.view)
        scroll.contentSize = contentSize

        context.coordinator.host = host
        context.coordinator.scroll = scroll
        context.coordinator.contentSize = contentSize

        scroll.onLayout = { [weak scroll, weak coordinator = context.coordinator] view in
            guard let scroll else { return }
            coordinator?.fitIfNeeded(scroll)
            _ = view
        }

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap)
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        return scroll
    }

    func updateUIView(_ scroll: FitScrollView, context: Context) {
        guard let host = context.coordinator.host else { return }
        host.rootView = AnyView(
            content().frame(width: contentSize.width, height: contentSize.height)
        )
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.resetZoom(in: scroll)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        weak var scroll: UIScrollView?
        var contentSize: CGSize = .zero
        var lastResetToken = 0
        private var fitScale: CGFloat = 1
        private var userZoomed = false

        func fitIfNeeded(_ scroll: UIScrollView) {
            guard !userZoomed, scroll.bounds.width > 1, contentSize.width > 1 else { return }
            let scale = min(
                scroll.bounds.width / contentSize.width,
                scroll.bounds.height / contentSize.height
            )
            guard scale > 0 else { return }
            fitScale = scale
            DispatchQueue.main.async { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                self.applyScale(scale, to: scroll)
            }
        }

        func resetZoom(in scroll: UIScrollView) {
            userZoomed = false
            fitIfNeeded(scroll)
        }

        private func applyScale(_ scale: CGFloat, to scroll: UIScrollView) {
            scroll.minimumZoomScale = scale
            scroll.maximumZoomScale = max(2.4, scale * 4)
            scroll.setZoomScale(scale, animated: false)
            centerContent(in: scroll)
        }

        private func centerContent(in scroll: UIScrollView) {
            let scaled = CGSize(
                width: contentSize.width * scroll.zoomScale,
                height: contentSize.height * scroll.zoomScale
            )
            let insetX = max(0, (scroll.bounds.width - scaled.width) / 2)
            let insetY = max(0, (scroll.bounds.height - scaled.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }

        @objc func handleDoubleTap() {
            guard let scroll else { return }
            let target: CGFloat = abs(scroll.zoomScale - fitScale) < 0.02 ? 1.0 : fitScale
            userZoomed = abs(target - fitScale) > 0.001
            scroll.setZoomScale(target, animated: true)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            userZoomed = true
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }
    }
}

final class FitScrollView: UIScrollView {
    var onLayout: ((FitScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

// MARK: - 画布内容

struct FlowDemoBoard: View {
    let palette: SpecRuneFlowTokens.Palette
    let reduceMotion: Bool
    let appeared: Bool
    let onSelect: (FlowNodeModel) -> Void

    @State private var tree: FlowNodeModel = FlowNodeModel.makeTree(rootColor: .blue)
    @State private var clockOrigin = Date.timeIntervalSinceReferenceDate

    private var layout: FlowLayout {
        FlowLayout(stageCount: 3, childCounts: [4, 3, 3])
    }

    private var timeline: FlowTimeline {
        let layout = layout
        var hops: [FlowTimeline.Hop] = []
        var rects: [String: CGRect] = ["root": layout.rootRect]
        rects["root"] = layout.rootRect

        for (stageIndex, stage) in tree.children.enumerated() {
            let stageRect = layout.stageRect(stageIndex)
            rects[stage.id] = stageRect

            // 原版 `data-side` 由 hop 方向决定：宽屏根节点子级用 top、二级子节点用 left、
            // 反向 hop 用 bottom。这里按列轮流分配，让三种方向都能在 demo 里看到。
            let side: GroundSide = stageIndex == 0 ? .left : (stageIndex == 1 ? .top : .bottom)

            for (childIndex, child) in stage.children.enumerated() {
                let childRect = layout.childRect(stageIndex, childIndex)
                rects[child.id] = childRect
                let link = Self.linkPath(from: stageRect, to: childRect)
                hops.append(.init(
                    id: "\(stage.id)>\(child.id)",
                    path: link.path,
                    length: link.length,
                    targetID: child.id,
                    color: stage.color,
                    side: side
                ))
            }
        }
        return FlowTimeline(hops: hops, nodeRects: rects)
    }

    var body: some View {
        let layout = layout
        let timeline = timeline

        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate - clockOrigin
                ZStack(alignment: .topLeading) {
                    FlowLinksLayer(
                        layout: layout,
                        tree: tree,
                        timeline: timeline,
                        palette: palette,
                        time: time,
                        appeared: appeared,
                        reduceMotion: reduceMotion
                    )

                    nodeView(tree, rect: layout.rootRect, timeline: timeline, time: time)

                    ForEach(Array(tree.children.enumerated()), id: \.element.id) { item in
                        let stageIndex = item.offset
                        let stage = item.element
                        nodeView(stage, rect: layout.stageRect(stageIndex), timeline: timeline, time: time)

                        ForEach(Array(stage.children.enumerated()), id: \.element.id) { childItem in
                            nodeView(
                                childItem.element,
                                rect: layout.childRect(stageIndex, childItem.offset),
                                timeline: timeline,
                                time: time
                            )
                        }
                    }
                }
                .frame(width: layout.boardWidth, height: layout.boardHeight, alignment: .topLeading)
                .animation(nil, value: time)
            }
        }
        .frame(width: layout.boardWidth, height: layout.boardHeight, alignment: .topLeading)
    }

    private func nodeView(
        _ node: FlowNodeModel,
        rect: CGRect,
        timeline: FlowTimeline,
        time: Double
    ) -> some View {
        FlowNodeCard(
            node: node,
            palette: palette,
            time: time,
            reduceMotion: reduceMotion,
            glow: timeline.glow(for: node.id, at: time)?.rise ?? 0,
            glowSide: timeline.glow(for: node.id, at: time)?.side ?? .bottom,
            onTap: { onSelect(node) }
        )
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    /// 父卡左下 17pt 处下竖线，圆角拐进子卡左侧 25pt 处。
    static func linkPath(from parent: CGRect, to child: CGRect) -> (path: Path, length: CGFloat) {
        let start = CGPoint(x: parent.minX + 17, y: parent.maxY)
        let endX = child.minX
        let endY = child.minY + 25

        var path = Path()
        path.move(to: start)

        let deltaX = endX - start.x
        guard deltaX > 0.5 else {
            path.addLine(to: CGPoint(x: start.x, y: endY))
            return (path, abs(endY - start.y))
        }

        let corner = min(8, deltaX / 2, max(0, (endY - start.y) / 2))
        path.addLine(to: CGPoint(x: start.x, y: endY - corner))
        path.addQuadCurve(
            to: CGPoint(x: start.x + corner, y: endY),
            control: CGPoint(x: start.x, y: endY)
        )
        path.addLine(to: CGPoint(x: endX, y: endY))

        let length = max(0, endY - start.y - corner) + corner * .pi / 2 + max(0, deltaX - corner)
        return (path, length)
    }

}

// MARK: - 连线 / 光带 / 落地闪光

struct FlowLinksLayer: View {
    let layout: FlowLayout
    let tree: FlowNodeModel
    let timeline: FlowTimeline
    let palette: SpecRuneFlowTokens.Palette
    let time: Double
    let appeared: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(timeline.hops.enumerated()), id: \.offset) { item in
                item.element.path
                    .trimmedPath(from: 0, to: appeared ? 1 : 0)
                    .stroke(
                        item.element.color.opacity(0.88),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: layout.boardWidth, height: layout.boardHeight, alignment: .topLeading)
            }

            // 连接点小圆
            ForEach(Array(timeline.hops.enumerated()), id: \.offset) { item in
                if let target = timeline.nodeRects[item.element.targetID] {
                    Circle()
                        .fill(item.element.color.opacity(0.88))
                        .frame(width: 5, height: 5)
                        .offset(x: target.minX - 2.5, y: target.minY + 22.5)
                }
            }

            // 光带：原版每 hop 叠 8 条 dash 拖尾（44 → 5.5px），dash 从路径前 22pt
            // 流到后 22pt，形成「头长尾短」的锥形光流。
            ForEach(Array(timeline.activeHops(at: time).enumerated()), id: \.offset) { _, active in
                let hop = timeline.hops[active.index]
                let length = max(hop.length, 1)
                let center = -22 + active.progress * (length + 44)

                ForEach(0 ..< 8, id: \.self) { layer in
                    let dash = 44.0 * Double(8 - layer) / 8
                    let lower = max(0, (center - dash / 2) / length)
                    let upper = min(1, (center + dash / 2) / length)
                    if upper > lower {
                        hop.path
                            .trimmedPath(from: lower, to: upper)
                            .stroke(
                                hop.color.opacity(0.28),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .butt)
                            )
                            .shadow(color: hop.color.opacity(0.45), radius: 1.5)
                            .frame(
                                width: layout.boardWidth,
                                height: layout.boardHeight,
                                alignment: .topLeading
                            )
                    }
                }
            }

            // 根卡母线
            Canvas { context, _ in
                drawRootLinks(context: &context)
            }
            .frame(width: layout.boardWidth, height: layout.boardHeight)
        }
        .frame(width: layout.boardWidth, height: layout.boardHeight, alignment: .topLeading)
        .animation(reduceMotion ? nil : SpecRuneFlowTokens.linkDraw.delay(SpecRuneFlowTokens.linkDrawDelay), value: appeared)
    }

    private func mixed(_ color: Color) -> Color {
        // 原版 stroke 是 color-mix(节点色 50%, 卡片色)：这里用节点色降透明度近似。
        color.opacity(0.88)
    }

    private func drawRootLinks(context: inout GraphicsContext) {
        let root = layout.rootRect
        let start = CGPoint(x: root.midX, y: root.maxY)
        // 母线走父卡底与 level 顶的中点（原版 `o = n + (s - n)/2`）。
        let busY = root.maxY + (layout.levelY - root.maxY) / 2

        for index in 0 ..< layout.stageCount {
            let stage = layout.stageRect(index)
            let path = Self.rootLinkPath(from: start, to: CGPoint(x: stage.midX, y: stage.minY), busY: busY)
            let color = tree.color.opacity(0.55)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

            var dot = Path()
            dot.addEllipse(in: CGRect(x: stage.midX - 2.5, y: stage.minY - 2.5, width: 5, height: 5))
            context.fill(dot, with: .color(color))
        }
    }

    /// 原版 `c(e, 0)` 的根节点分支：竖下 → 圆角 → 横移 → 圆角 → 竖下。
    static func rootLinkPath(from start: CGPoint, to end: CGPoint, busY: CGFloat) -> Path {
        var path = Path()
        path.move(to: start)

        let dx = end.x - start.x
        let absDx = abs(dx)
        guard absDx >= 12 else {
            // 正下方：一条直线就够（原版同样走 `V` 分支）。
            path.addLine(to: CGPoint(x: start.x, y: end.y))
            return path
        }

        let sign: CGFloat = dx > 0 ? 1 : -1
        let bendOut = max(0, min(8, absDx / 2, (busY - start.y) / 2))
        let bendIn = max(0, min(8, absDx / 2 - bendOut, (end.y - busY) / 2))

        path.addLine(to: CGPoint(x: start.x, y: busY - bendOut))
        path.addQuadCurve(
            to: CGPoint(x: start.x + sign * bendOut, y: busY),
            control: CGPoint(x: start.x, y: busY)
        )
        path.addLine(to: CGPoint(x: end.x - sign * bendIn, y: busY))
        path.addQuadCurve(
            to: CGPoint(x: end.x, y: busY + bendIn),
            control: CGPoint(x: end.x, y: busY)
        )
        path.addLine(to: CGPoint(x: end.x, y: end.y))
        return path
    }
}

// MARK: - 节点卡

struct FlowNodeCard: View {
    let node: FlowNodeModel
    let palette: SpecRuneFlowTokens.Palette
    let time: Double
    let reduceMotion: Bool
    let glow: Double
    let glowSide: GroundSide
    let onTap: () -> Void

    @State private var visible = false

    private var isActive: Bool { node.status == .active }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: SpecRuneFlowTokens.trayRadius, style: .continuous)
                .fill(palette.tray)

            RoundedRectangle(cornerRadius: SpecRuneFlowTokens.cardRadius, style: .continuous)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: SpecRuneFlowTokens.cardRadius, style: .continuous)
                        .strokeBorder(palette.cardRing, lineWidth: 0.8)
                )
                .overlay {
                    glowLayer.frame(
                        width: SpecRuneFlowTokens.cardWidth - SpecRuneFlowTokens.trayPadding * 2,
                        height: SpecRuneFlowTokens.nodeHeight - SpecRuneFlowTokens.trayPadding * 2
                    )
                }
                .shadow(
                    color: palette.cardShadow.opacity(palette.cardShadowOpacity),
                    radius: palette.cardShadowRadius,
                    y: palette.cardShadowY
                )
                .padding(SpecRuneFlowTokens.trayPadding)

            content
                .padding(SpecRuneFlowTokens.trayPadding)
        }
        .contentShape(RoundedRectangle(cornerRadius: SpecRuneFlowTokens.trayRadius, style: .continuous))
        .onTapGesture(perform: onTap)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 6)
        .scaleEffect(visible ? 1 : 0.98)
        .onAppear {
            guard !reduceMotion else {
                visible = true
                return
            }
            withAnimation(SpecRuneFlowTokens.enter) { visible = true }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            topRow
            activityRow
            meterRow
            footRow
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 10)
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            PixelMark(
                seed: node.id,
                color: node.color,
                active: isActive,
                time: time,
                reduceMotion: reduceMotion,
                palette: palette
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(node.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if let model = node.model {
                    Text(model)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            statusPill
        }
        .frame(height: 24)
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            statusIcon
            Text(node.status.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(statusForeground)
        .padding(.horizontal, 7)
        .frame(height: SpecRuneFlowTokens.statusHeight)
        .background(statusBackground, in: Capsule())
    }

    private var statusBackground: Color {
        switch node.status {
        case .active: palette.brandBackground
        case .done: palette.okBackground
        case .idle: palette.fill
        case .unknown: palette.fill
        }
    }

    private var statusForeground: Color {
        switch node.status {
        case .active: palette.brandForeground
        case .done: palette.okForeground
        case .idle, .unknown: palette.text
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch node.status {
        case .active:
            RotatingRing(color: node.color, time: time, reduceMotion: reduceMotion)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
        case .idle:
            Circle().fill(palette.muted.opacity(0.6)).frame(width: 5, height: 5)
        case .unknown:
            Image(systemName: "minus")
                .font(.system(size: 8, weight: .bold))
        }
    }

    private var activityRow: some View {
        ShineText(
            text: node.activity,
            active: isActive,
            time: time,
            reduceMotion: reduceMotion,
            palette: palette,
            color: node.color
        )
        .frame(height: 17, alignment: .leading)
    }

    private var meterRow: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.fill)
                    Capsule()
                        .fill(node.color)
                        .frame(width: max(0, min(1, node.progress)) * geo.size.width)
                }
            }
            .frame(height: SpecRuneFlowTokens.meterHeight)

            Text(node.progressLabel)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(palette.muted)
                .lineLimit(1)
        }
        .frame(height: 14)
    }

    private var footRow: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< 2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(palette.line, lineWidth: 0.8)
                    )
                    .frame(width: 17, height: 17)
                    .overlay {
                        Image(systemName: index == 0 ? "arrow.turn.down.left" : "text.bubble")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(palette.muted)
                    }
            }

            if let text = node.footText {
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(height: SpecRuneFlowTokens.footHeight)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var glowLayer: some View {
        if glow > 0, !reduceMotion {
            let rise = glow
            // 原版 `ui-acr-got`：0–30% 保持满亮，之后线性淡出。
            let fade = rise < 0.3 ? 1 : max(0, 1 - (rise - 0.3) / 0.7)
            let phase = (time / 1.1) * 2 * .pi
            let floors = SpecRuneFlowTokens.floorColors(node.colorIndex)
            let w = SpecRuneFlowTokens.cardWidth - SpecRuneFlowTokens.trayPadding * 2
            let h = SpecRuneFlowTokens.nodeHeight - SpecRuneFlowTokens.trayPadding * 2

            Group {
                switch glowSide {
                case .bottom:
                    // 默认：从底部向上。
                    waveBody(rise: rise, phase: phase, floors: floors)
                        .frame(width: w, height: h)
                case .top:
                    // `[data-side="top"] .ui-acr__floor-turn { transform: rotate(180deg) }`
                    waveBody(rise: rise, phase: phase, floors: floors)
                        .frame(width: w, height: h)
                        .rotationEffect(.degrees(180))
                case .left:
                    // `[data-side="left"]` 先把容器宽高互换，再绕左上角转 90°。
                    waveBody(rise: rise, phase: phase, floors: floors)
                        .frame(width: h, height: w)
                        .rotationEffect(.degrees(90))
                }
            }
            .frame(width: w, height: h)
            .opacity(fade)
            .clipped()
            .mask(
                RoundedRectangle(cornerRadius: SpecRuneFlowTokens.cardRadius, style: .continuous)
            )
            .allowsHitTesting(false)
        }
    }

    /// 两层波形 + 浅色模式的 40% 白纱（`--ui-acr-floor-veil`）。
    private func waveBody(
        rise: Double,
        phase: Double,
        floors: (top: Color, mid: Color, bottom: Color)
    ) -> some View {
        ZStack(alignment: .bottom) {
            GroundWave(phase: phase, light: false)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: floors.top, location: 0),
                            .init(color: floors.mid, location: 0.302885),
                            .init(color: floors.bottom, location: 0.673077),
                        ],
                        // 原版是 `userSpaceOnUse`，y 从 423.3 到 894.3（viewBox 高 1514.1）。
                        startPoint: UnitPoint(x: 0.5, y: 423.3 / 1514.1),
                        endPoint: UnitPoint(x: 0.5, y: 894.3 / 1514.1)
                    )
                )
                // `--ui-acr-gf-bleed` inset -31.27% -10.17%：画布 326×143。
                .frame(width: 270 * 1.2034, height: 88 * 1.6254)
                .scaleEffect(x: 1 + rise * 0.08, y: 1 + rise, anchor: .bottom)
                .offset(y: 45 - rise * 81)
                .blur(radius: 14)

            GroundWave(phase: phase, light: true)
                .fill(Color.white.opacity(palette.card == .clear ? 0.2 : 0.8))
                .frame(width: 228 * 1.2034, height: 74 * 1.6254)
                .scaleEffect(x: 1 + rise * 0.04, y: 1 + rise * 0.8, anchor: .bottom)
                .offset(y: 48 - rise * 72)
                .blur(radius: 12)
                .blendMode(.plusLighter)

            if palette.card != .clear {
                Color.white.opacity(0.4)
            }
        }
    }

}

/// 原版 affectUI 的落地闪光波形 `A(e, t)`：五个正弦偏移驱动一条闭合波带。
struct GroundWave: Shape {
    let phase: Double
    let light: Bool

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = light ? 0.8427 : 1
        let viewBox = light
            ? CGSize(width: 2904.96, height: 1275.97)
            : CGSize(width: 3447.1, height: 1514.1)

        let v1 = light ? CGPoint(x: 781.039, y: 476.815) : CGPoint(x: 926.8, y: 565.8)
        let ctrl = light ? CGPoint(x: 254.588, y: 250.543) : CGPoint(x: 302.1, y: 297.3)
        let left = light ? CGPoint(x: 245.486, y: 245.486) : CGPoint(x: 291.3, y: 291.3)
        let bottom: CGFloat = light ? 1030.49 : 1222.8
        let right = light ? CGPoint(x: 2659.48, y: 304.477) : CGPoint(x: 3155.8, y: 361.3)
        let v4 = light ? CGPoint(x: 2101.59, y: 476.815) : CGPoint(x: 2493.8, y: 565.8)
        let v3 = light ? CGPoint(x: 1844.98, y: 476.815) : CGPoint(x: 2189.3, y: 565.8)
        let m2 = light ? CGPoint(x: 1600.17, y: 361.361) : CGPoint(x: 1898.8, y: 428.8)
        let m1 = light ? CGPoint(x: 1273.19, y: 361.361) : CGPoint(x: 1510.8, y: 428.8)
        let v2 = light ? CGPoint(x: 1037.23, y: 476.815) : CGPoint(x: 1230.8, y: 565.8)

        let l = 110 * sin(phase)
        let m = -110 * sin(phase + 0.5)
        let rr = 110 * sin(phase + 1)
        let vL = 80 * sin(phase + .pi / 2 + 0.25)
        let vR = 80 * sin(phase - .pi / 2 + 0.75)

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + point.x / viewBox.width * rect.width,
                y: rect.minY + point.y / viewBox.height * rect.height
            )
        }
        func shifted(_ point: CGPoint, _ offset: Double) -> CGPoint {
            CGPoint(x: point.x, y: point.y + CGFloat(offset) * k)
        }
        func horizontal(_ x: CGFloat, _ point: CGPoint) -> CGPoint {
            CGPoint(x: x, y: point.y)
        }

        var path = Path()
        path.move(to: map(shifted(v1, vL)))
        path.addCurve(
            to: map(shifted(left, l)),
            control1: map(shifted(v1, vL)),
            control2: map(shifted(ctrl, l))
        )
        path.addLine(to: map(CGPoint(x: left.x, y: bottom)))
        path.addLine(to: map(CGPoint(x: right.x, y: bottom)))
        path.addLine(to: map(shifted(right, rr)))
        path.addLine(to: map(shifted(v4, vR)))
        path.addLine(to: map(horizontal(v3.x, shifted(v4, vR))))
        path.addLine(to: map(shifted(v3, vR)))
        path.addLine(to: map(shifted(m2, m)))
        path.addLine(to: map(horizontal(m1.x, shifted(m2, m))))
        path.addLine(to: map(shifted(m1, m)))
        path.addLine(to: map(shifted(v2, vL)))
        path.addLine(to: map(horizontal(v1.x, shifted(v2, vL))))
        path.addLine(to: map(shifted(v1, vL)))
        path.closeSubpath()
        return path
    }
}

// MARK: - 零件

/// 3×3 像素头像：`active` 时按原版的 1.2s ease-in-out 交错闪烁。
struct PixelMark: View {
    let seed: String
    let color: Color
    let active: Bool
    let time: Double
    let reduceMotion: Bool
    let palette: SpecRuneFlowTokens.Palette

    private static let delays: [Double] = [0, 0.12, 0.24, 0.12, 0.24, 0.36, 0.24, 0.36, 0.48]

    var body: some View {
        let dots = Self.pattern(seed)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.line, lineWidth: 0.8)
                )

            VStack(spacing: 1.5) {
                ForEach(0 ..< 3, id: \.self) { row in
                    HStack(spacing: 1.5) {
                        ForEach(0 ..< 3, id: \.self) { column in
                            pixel(index: row * 3 + column, on: dots[row * 3 + column])
                        }
                    }
                }
            }
        }
        .frame(width: SpecRuneFlowTokens.avatarSize, height: SpecRuneFlowTokens.avatarSize)
    }

    private func pixel(index: Int, on: Bool) -> some View {
        let opacity: Double = {
            guard on else { return active ? 0.16 : 0 }
            guard active, !reduceMotion else { return 1 }
            let phase = (time + Self.delays[index]).truncatingRemainder(dividingBy: SpecRuneFlowTokens.pixel)
            let wave = 0.5 + 0.5 * cos(2 * .pi * phase / SpecRuneFlowTokens.pixel)
            return 0.2 + 0.8 * wave
        }()

        return RoundedRectangle(cornerRadius: 0.75, style: .continuous)
            .fill(color)
            .frame(width: 3, height: 3)
            .opacity(opacity)
    }

    static func pattern(_ seed: String) -> [Bool] {
        var hash: UInt64 = 0
        for scalar in seed.unicodeScalars {
            hash = hash &* 31 &+ UInt64(scalar.value)
        }
        var cells = [Bool](repeating: false, count: 9)
        for index in 0 ..< 9 {
            cells[index] = (hash >> UInt64(index)) & 1 == 1
        }
        // 保证至少 5 个点亮，避免出现过于稀疏的图案。
        if cells.filter({ $0 }).count < 5 {
            for index in 0 ..< 9 where !cells[index] {
                cells[index] = true
                if cells.filter({ $0 }).count >= 5 { break }
            }
        }
        return cells
    }
}

/// active 的加载环：原版 `ui-acr-spin` 900ms linear infinite。
struct RotatingRing: View {
    let color: Color
    let time: Double
    let reduceMotion: Bool

    var body: some View {
        let angle = reduceMotion ? 0 : time.truncatingRemainder(dividingBy: SpecRuneFlowTokens.spin) / SpecRuneFlowTokens.spin * 360
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(angle))
            .frame(width: 10, height: 10)
    }
}

/// active 活动文字的三段扫光，对应 `ui-acr-shine` 的 2s linear infinite。
struct ShineText: View {
    let text: String
    let active: Bool
    let time: Double
    let reduceMotion: Bool
    let palette: SpecRuneFlowTokens.Palette
    let color: Color

    var body: some View {
        let phase = reduceMotion ? 0.5 : (time.truncatingRemainder(dividingBy: SpecRuneFlowTokens.shine) / SpecRuneFlowTokens.shine)
        let head = 1.5 - phase * 2.4

        Text(text)
            .font(.system(size: 12.5))
            .lineLimit(1)
            .foregroundStyle(palette.text)
            .overlay {
                if active, !reduceMotion {
                    Text(text)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .foregroundStyle(palette.ink)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.42),
                                    .init(color: .black, location: 0.58),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: UnitPoint(x: head, y: 0.5),
                                endPoint: UnitPoint(x: head + 0.55, y: 0.5)
                            )
                        }
                }
            }
    }
}

// MARK: - 节点面板

struct FlowNodePanel: View {
    let node: FlowNodeModel
    let palette: SpecRuneFlowTokens.Palette
    let onAction: (String) -> Void
    let onClose: () -> Void

    private let actions: [(title: String, value: String, primary: Bool)] = [
        ("Approve", "approve", true),
        ("Decline", "decline", false),
        ("跳过", "skip", false),
        ("补做", "redo", false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PixelMark(
                    seed: node.id, color: node.color, active: false,
                    time: 0, reduceMotion: true, palette: palette
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(node.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(node.id)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 24, height: 24)
                        .background(palette.fill, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Text(node.activity)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.text)
                .lineLimit(2)

            Divider().overlay(palette.line)

            HStack(spacing: 6) {
                ForEach(actions, id: \.value) { action in
                    Button {
                        onAction(action.value)
                    } label: {
                        Text(action.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(action.primary ? Color.white : palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                action.primary ? palette.brandForeground : palette.card,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(action.primary ? Color.clear : palette.line, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.cardRing, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }
}

// MARK: - Demo 页

struct SpecRuneFlowDemoView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var selected: FlowNodeModel?
    @State private var resetToken = 0
    @State private var appeared = false
    @State private var lastAction: String?

    private var palette: SpecRuneFlowTokens.Palette { .resolve(colorScheme) }

    private var backdrop: Color {
        colorScheme == .dark ? Color(hex: 0x0D0F14) : Color(hex: 0xF6F7F9)
    }

    private var layout: FlowLayout {
        FlowLayout(stageCount: 3, childCounts: [4, 3, 3])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop.ignoresSafeArea()

                FlowDemoCanvas(
                    contentSize: CGSize(width: layout.boardWidth, height: layout.boardHeight),
                    resetToken: resetToken
                ) {
                    FlowDemoBoard(palette: palette, reduceMotion: reduceMotion, appeared: appeared) { node in
                        selected = node
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                if let node = selected {
                    ZStack {
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                            .onTapGesture { selected = nil }
                        FlowNodePanel(
                            node: node,
                            palette: palette,
                            onAction: { action in
                                lastAction = "\(node.title) → \(action)"
                                selected = nil
                            },
                            onClose: { selected = nil }
                        )
                        .transition(.opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.98)))
                    }
                }

                if let lastAction {
                    VStack {
                        Spacer()
                        Text(lastAction)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(palette.card, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                            .padding(.bottom, 28)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else {
                    appeared = true
                    return
                }
                withAnimation(SpecRuneFlowTokens.enter) { appeared = true }
            }
            .navigationTitle("任务流 · 视觉 Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") { resetToken += 1 }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
