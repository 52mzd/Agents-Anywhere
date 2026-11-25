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
    var children: [FlowNodeModel]

    static func makeTree(rootColor: Color) -> FlowNodeModel {
        let colors = SpecRuneFlowTokens.nodeColors
        let plan = [
            node("1.1", "需求探索", "explore", .done, "已确认 6 项事实", 1, .one, "SpecRune prd.md · design.md", colors[0]),
            node("1.2", "调研", "research", .unknown, "无信号", 0, .zero, nil, colors[0]),
            node("1.3", "配置上下文", "context", .done, "7 + 5 条已策展", 1, .one, "SpecRune 清单 12 条", colors[0]),
            node("1.4", "激活任务", "start", .done, "已绑定本会话", 1, .one, nil, colors[0]),
        ]
        let execute = [
            node("2.1", "实现", "implement", .active, "正在复刻卡片与连线", 0.64, .percent(0.64), "SpecRune 4/6 文件已改", colors[1]),
            node("2.2", "新鲜复查", "review", .idle, "等待实现完成", 0, .zero, nil, colors[1]),
            node("2.3", "修复", "fix", .idle, "通常不需要", 0, .zero, nil, colors[1]),
        ]
        let finish = [
            node("3.2", "更新规范", "spec", .idle, "无新增契约", 0, .zero, nil, colors[2]),
            node("3.3", "提交", "commit", .idle, "代码与规范同提", 0, .zero, nil, colors[2]),
            node("3.4", "归档", "archive", .unknown, "验收通过后", 0, .zero, nil, colors[2]),
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
            children: [
                FlowNodeModel(
                    id: "stage-1", title: "Plan 阶段", model: "1.0 → 1.4",
                    status: .done, activity: "prd.md · design.md · 清单 7/5",
                    progress: 1, progressLabel: "200k / 200k",
                    footText: "最近一次注入", color: colors[0], children: plan
                ),
                FlowNodeModel(
                    id: "stage-2", title: "Execute 阶段", model: "2.1 → 2.3",
                    status: .active, activity: "2.1 实现中 · 4/6 文件已改",
                    progress: 0.58, progressLabel: "116k / 200k",
                    footText: "最近一次注入", color: colors[1], children: execute
                ),
                FlowNodeModel(
                    id: "stage-3", title: "Finish 阶段", model: "3.2 → 3.4",
                    status: .idle, activity: "等 Execute 收尾",
                    progress: 0, progressLabel: "0 / 200k",
                    footText: "最近一次注入", color: colors[2], children: finish
                ),
            ]
        )
    }

    private static func node(
        _ id: String, _ title: String, _ model: String, _ status: FlowNodeStatus,
        _ activity: String, _ ratio: Double, _ label: ProgressLabel, _ foot: String?, _ color: Color
    ) -> FlowNodeModel {
        FlowNodeModel(
            id: id, title: title, model: model, status: status, activity: activity,
            progress: ratio, progressLabel: label.text, footText: foot, color: color, children: []
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
    let nodeHeight: CGFloat = 128
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

/// 把「连线跑光带 → 节点落地闪光」算成 time 的纯函数，方便每帧重算。
struct FlowTimeline {
    struct Hop {
        let id: String
        let path: Path
        let targetID: String
        let color: Color
    }

    let hops: [Hop]
    let nodeRects: [String: CGRect]

    static let hopDuration: Double = 0.55
    static let hopGap: Double = 0.14
    static let startDelay: Double = 1.1
    static let tailPause: Double = 2.2
    static let glowDuration: Double = SpecRuneFlowTokens.glow

    var cycle: Double {
        guard !hops.isEmpty else { return 4 }
        return Self.startDelay + Double(hops.count) * (Self.hopDuration + Self.hopGap) + Self.tailPause
    }

    /// 当前跑到第几个 hop、进度多少。
    func currentHop(at time: Double) -> (index: Int, progress: Double)? {
        guard !hops.isEmpty else { return nil }
        let local = time.truncatingRemainder(dividingBy: cycle)
        let slot = Self.hopDuration + Self.hopGap
        let offset = local - Self.startDelay
        guard offset >= 0 else { return nil }
        let index = Int(offset / slot)
        guard index < hops.count else { return nil }
        let progress = (offset - Double(index) * slot) / Self.hopDuration
        guard progress <= 1 else { return nil }
        return (index, max(0, min(1, progress)))
    }

    /// 节点落地闪光的进度（0 表示不在闪）。
    func glow(for nodeID: String, at time: Double) -> Double {
        guard !hops.isEmpty else { return 0 }
        let local = time.truncatingRemainder(dividingBy: cycle)
        for (index, hop) in hops.enumerated() where hop.targetID == nodeID {
            let arrive = Self.startDelay + Double(index) * (Self.hopDuration + Self.hopGap) + Self.hopDuration
            let delta = local - arrive
            guard delta >= 0, delta < Self.glowDuration else { continue }
            return delta / Self.glowDuration
        }
        return 0
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

            for (childIndex, child) in stage.children.enumerated() {
                let childRect = layout.childRect(stageIndex, childIndex)
                rects[child.id] = childRect
                let path = Self.linkPath(from: stageRect, to: childRect)
                hops.append(.init(id: "\(stage.id)>\(child.id)", path: path, targetID: child.id, color: stage.color))
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
                        time: time
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
            glow: timeline.glow(for: node.id, at: time),
            onTap: { onSelect(node) }
        )
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    /// 父卡左下 17pt 处下竖线，圆角拐进子卡左侧 25pt 处。
    static func linkPath(from parent: CGRect, to child: CGRect) -> Path {
        let start = CGPoint(x: parent.minX + 17, y: parent.maxY)
        let endX = child.minX
        let endY = child.minY + 25

        var path = Path()
        path.move(to: start)
        let deltaX = endX - start.x
        guard deltaX > 0.5 else {
            path.addLine(to: CGPoint(x: start.x, y: endY))
            return path
        }
        let corner = min(8, deltaX / 2, max(0, (endY - start.y) / 2))
        path.addLine(to: CGPoint(x: start.x, y: endY - corner))
        path.addQuadCurve(
            to: CGPoint(x: start.x + corner, y: endY),
            control: CGPoint(x: start.x, y: endY)
        )
        path.addLine(to: CGPoint(x: endX, y: endY))
        return path
    }
}

// MARK: - 连线 / 光带 / 落地闪光

struct FlowLinksLayer: View {
    let layout: FlowLayout
    let tree: FlowNodeModel
    let timeline: FlowTimeline
    let palette: SpecRuneFlowTokens.Palette
    let time: Double

    var body: some View {
        Canvas { context, size in
            // 1. 根卡 → 阶段卡的母线
            drawRootLinks(context: &context, size: size)

            // 2. 阶段卡 → 步骤卡
            for hop in timeline.hops {
                context.stroke(
                    hop.path,
                    with: .color(mixed(hop.color)),
                    style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
                )
                // 连接点小圆
                if let target = timeline.nodeRects[hop.targetID] {
                    let dot = CGRect(x: target.minX - 2.5, y: target.minY + 25 - 2.5, width: 5, height: 5)
                    context.fill(Path(ellipseIn: dot), with: .color(mixed(hop.color)))
                }
            }

            // 3. 光带：沿当前 hop 的路径跑
            if let current = timeline.currentHop(at: time) {
                let hop = timeline.hops[current.index]
                let head = current.progress
                let tail = max(0, head - 0.22)
                let band = hop.path.trimmedPath(from: tail, to: head)
                // 原版沿 path 跑 8 条带 drop-shadow 的光带；这里用三层描边近似辉光。
                context.stroke(
                    band,
                    with: .color(hop.color.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    band,
                    with: .color(hop.color.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    band,
                    with: .color(.white.opacity(0.98)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: layout.boardWidth, height: layout.boardHeight)
    }

    private func mixed(_ color: Color) -> Color {
        // 原版 stroke 是 color-mix(节点色 50%, 卡片色)：这里用节点色降透明度近似。
        color.opacity(0.55)
    }

    private func drawRootLinks(context: inout GraphicsContext, size: CGSize) {
        let root = layout.rootRect
        let start = CGPoint(x: root.midX, y: root.maxY)
        // 母线走父卡底与 level 顶的中点（原版 `o = n + (s - n)/2`）。
        let busY = root.maxY + (layout.levelY - root.maxY) / 2

        for index in 0 ..< layout.stageCount {
            let stage = layout.stageRect(index)
            let path = Self.rootLinkPath(from: start, to: CGPoint(x: stage.midX, y: stage.minY), busY: busY)
            let color = tree.color.opacity(0.55)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))

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
                .overlay { glowLayer }
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
            // 原版 `ui-acr-got`：前 30% 保持全亮，之后线性淡出。
            let fade = rise < 0.3 ? 1 : max(0, 1 - (rise - 0.3) / 0.7)
            ZStack(alignment: .bottom) {
                // 彩色光雾：比卡片更宽、强模糊，从底边向上升起再散开。
                Ellipse()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: node.color.opacity(0.62), location: 0),
                                .init(color: node.color.opacity(0.24), location: 0.48),
                                .init(color: node.color.opacity(0), location: 1),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 320, height: 84)
                    .scaleEffect(x: 1, y: 1 + rise * 2.2, anchor: .bottom)
                    .offset(y: 28 - rise * 44)
                    .blur(radius: 34)

                // 白色高光：更窄、更淡，只负责「亮一下」。
                Ellipse()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(palette.card == .clear ? 0.16 : 0.7), location: 0),
                                .init(color: .white.opacity(0), location: 1),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 210, height: 64)
                    .scaleEffect(x: 1, y: 1 + rise * 2.0, anchor: .bottom)
                    .offset(y: 22 - rise * 40)
                    .blur(radius: 26)
            }
            .opacity(fade)
            .clipShape(RoundedRectangle(cornerRadius: SpecRuneFlowTokens.cardRadius, style: .continuous))
            .allowsHitTesting(false)
        }
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
                    FlowDemoBoard(palette: palette, reduceMotion: reduceMotion) { node in
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
