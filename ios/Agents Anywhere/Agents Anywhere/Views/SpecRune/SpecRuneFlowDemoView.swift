import SwiftUI
import UIKit

// MARK: - 演示数据

enum FlowDemoStepStatus {
    case done, active, idle, unknown
}

struct FlowDemoStep: Identifiable {
    let id: String
    let title: String
    let status: FlowDemoStepStatus
    let activity: String
    let progress: Double
    let hasFoot: Bool
}

struct FlowDemoStage: Identifiable {
    let id: String
    let title: String
    let caption: String
    let detail: String
    let progress: Double
    let steps: [FlowDemoStep]
    let color: Color
}

enum FlowDemoData {
    static let stages: [FlowDemoStage] = [
        FlowDemoStage(
            id: "1",
            title: "Plan 阶段",
            caption: "1.0 → 1.4",
            detail: "prd.md · design.md · 清单 7/5",
            progress: 1,
            steps: [
                FlowDemoStep(id: "1.1", title: "需求探索", status: .done, activity: "已确认 6 项事实", progress: 1, hasFoot: true),
                FlowDemoStep(id: "1.2", title: "调研", status: .unknown, activity: "无信号", progress: 0, hasFoot: false),
                FlowDemoStep(id: "1.3", title: "配置上下文", status: .done, activity: "7 + 5 条已策展", progress: 1, hasFoot: true),
                FlowDemoStep(id: "1.4", title: "激活任务", status: .done, activity: "已绑定本会话", progress: 1, hasFoot: false),
            ],
            color: SpecRuneFlowTokens.stageColors[0]
        ),
        FlowDemoStage(
            id: "2",
            title: "Execute 阶段",
            caption: "2.1 → 2.3",
            detail: "2.1 实现中 · 4/6 文件已改",
            progress: 0.58,
            steps: [
                FlowDemoStep(id: "2.1", title: "实现", status: .active, activity: "正在复刻卡片与连线", progress: 0.64, hasFoot: true),
                FlowDemoStep(id: "2.2", title: "新鲜复查", status: .idle, activity: "等待实现完成", progress: 0, hasFoot: false),
                FlowDemoStep(id: "2.3", title: "修复", status: .idle, activity: "通常不需要", progress: 0, hasFoot: false),
            ],
            color: SpecRuneFlowTokens.stageColors[1]
        ),
        FlowDemoStage(
            id: "3",
            title: "Finish 阶段",
            caption: "3.2 → 3.4",
            detail: "等 Execute 收尾",
            progress: 0,
            steps: [
                FlowDemoStep(id: "3.2", title: "更新规范", status: .idle, activity: "无新增契约", progress: 0, hasFoot: false),
                FlowDemoStep(id: "3.3", title: "提交", status: .idle, activity: "代码与规范同提", progress: 0, hasFoot: false),
                FlowDemoStep(id: "3.4", title: "归档", status: .unknown, activity: "验收通过后", progress: 0, hasFoot: false),
            ],
            color: SpecRuneFlowTokens.stageColors[2]
        ),
    ]
}

// MARK: - 画布

/// 把固定尺寸的流程图画布塞进 `UIScrollView`：原生惯性、双指缩放、双击缩放。
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
        /// 用户手动缩放过之后就不再自动 fit，避免抢走他的缩放。
        private var userZoomed = false

        /// 每次 bounds 变化且用户还没缩放过，就重新适配——sheet 呈现动画期间
        /// bounds 会从 0 长到最终尺寸，只在第一次 layout 里 fit 会算错。
        func fitIfNeeded(_ scroll: UIScrollView) {
            guard !userZoomed, scroll.bounds.width > 1, contentSize.width > 1 else { return }
            let scale = min(
                scroll.bounds.width / contentSize.width,
                scroll.bounds.height / contentSize.height
            )
            guard scale > 0 else { return }
            fitScale = scale
            // 不要在 layoutSubviews 里同步改 zoom，否则会触发下一轮布局。
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

        /// 内容小于视口时居中显示。
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

/// 每次布局都把 bounds 交给上层——sheet 呈现过程中 bounds 会变好几次。
final class FitScrollView: UIScrollView {
    var onLayout: ((FitScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

// MARK: - 画布尺寸

enum FlowBoardMetrics {
    static let padding: CGFloat = 24
    static let rootWidth: CGFloat = 222
    static let rootHeight: CGFloat = 108
    static let rootGap: CGFloat = 64
    static let footHeight: CGFloat = 22

    static let columns: CGFloat = 3
    static var boardWidth: CGFloat {
        padding * 2 + columns * SpecRuneFlowTokens.cardWidth
            + (columns - 1) * SpecRuneFlowTokens.stageGap
    }

    static var stageTop: CGFloat { rootHeight + rootGap }

    static func stepHeights(_ stage: FlowDemoStage) -> [CGFloat] {
        stage.steps.map {
            SpecRuneFlowTokens.stepCardHeight + ($0.hasFoot ? footHeight : 0)
        }
    }

    static func columnHeight(_ stage: FlowDemoStage) -> CGFloat {
        stageTop + SpecRuneFlowTokens.stageHeaderHeight
            + SpecRuneFlowTokens.stepGap
            + stepHeights(stage).reduce(0, +)
            + CGFloat(max(stage.steps.count - 1, 0)) * SpecRuneFlowTokens.stepGap
            + padding
    }

    static var boardHeight: CGFloat {
        FlowDemoData.stages.map(columnHeight).max() ?? 600
    }

    static func stageX(_ index: Int) -> CGFloat {
        padding + CGFloat(index) * (SpecRuneFlowTokens.cardWidth + SpecRuneFlowTokens.stageGap)
    }

    static func stepY(_ stage: FlowDemoStage, _ index: Int) -> CGFloat {
        var y = stageTop + SpecRuneFlowTokens.stageHeaderHeight + SpecRuneFlowTokens.stepGap
        let heights = stepHeights(stage)
        for i in 0 ..< min(index, heights.count) {
            y += heights[i] + SpecRuneFlowTokens.stepGap
        }
        return y
    }

    static var rootX: CGFloat { (boardWidth - rootWidth) / 2 }
}

// MARK: - 画布内容

struct FlowDemoBoard: View {
    let palette: SpecRuneFlowTokens.Palette
    let appeared: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            FlowDemoLinksLayer(palette: palette, appeared: appeared, reduceMotion: reduceMotion)

            FlowDemoRootCard(palette: palette)
                .frame(width: FlowBoardMetrics.rootWidth, height: FlowBoardMetrics.rootHeight)
                .offset(x: FlowBoardMetrics.rootX, y: 0)

            ForEach(Array(FlowDemoData.stages.enumerated()), id: \.element.id) { item in
                FlowDemoStageColumn(
                    stage: item.element,
                    palette: palette,
                    reduceMotion: reduceMotion
                )
                .offset(
                    x: FlowBoardMetrics.stageX(item.offset),
                    y: FlowBoardMetrics.stageTop
                )
            }
        }
        .frame(
            width: FlowBoardMetrics.boardWidth,
            height: FlowBoardMetrics.boardHeight,
            alignment: .topLeading
        )
    }
}

// MARK: - 连线

struct FlowDemoLinksLayer: View {
    let palette: SpecRuneFlowTokens.Palette
    let appeared: Bool
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, _ in
            for link in links {
                let trimmed = link.path.trimmedPath(from: 0, to: appeared ? 1 : 0)
                context.stroke(
                    trimmed,
                    with: .color(link.color.opacity(linkColorOpacity)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: FlowBoardMetrics.boardWidth, height: FlowBoardMetrics.boardHeight)
        .animation(
            reduceMotion ? nil : SpecRuneFlowTokens.linkDraw.delay(SpecRuneFlowTokens.linkDrawDelay),
            value: appeared
        )
    }

    private var linkColorOpacity: Double {
        palette.card == .clear ? 0.9 : 0.6
    }

    private var links: [(path: Path, color: Color)] {
        var result: [(path: Path, color: Color)] = []
        let rootCenter = FlowBoardMetrics.rootX + FlowBoardMetrics.rootWidth / 2
        let rootBottom = FlowBoardMetrics.rootHeight

        for (index, stage) in FlowDemoData.stages.enumerated() {
            let columnX = FlowBoardMetrics.stageX(index)
            let stageCenter = columnX + SpecRuneFlowTokens.cardWidth / 2

            // 根卡 → 阶段卡：共享一条水平母线，再垂直落到每列顶部。
            result.append((
                elbow(
                    from: CGPoint(x: rootCenter, y: rootBottom),
                    to: CGPoint(x: stageCenter, y: FlowBoardMetrics.stageTop),
                    midY: rootBottom + (FlowBoardMetrics.stageTop - rootBottom) / 2,
                    radius: 8
                ),
                stage.color
            ))

            // 阶段卡 → 步骤卡：主干绕到卡片左侧外走，分支水平指向卡片左边缘
            // （分支末段被卡片遮住，和桌面视觉一致，不会让竖线穿过卡片内容）。
            let stageBottom = FlowBoardMetrics.stageTop + SpecRuneFlowTokens.stageHeaderHeight
            let heights = FlowBoardMetrics.stepHeights(stage)
            guard !heights.isEmpty else { continue }

            let trunkX = columnX - 14
            let trunkTop = stageBottom + SpecRuneFlowTokens.stepGap / 2
            let bottoMostY = FlowBoardMetrics.stepY(stage, heights.count - 1) + heights[heights.count - 1] / 2

            var trunk = Path()
            trunk.move(to: CGPoint(x: stageCenter, y: stageBottom))
            trunk.addLine(to: CGPoint(x: stageCenter, y: trunkTop - 8))
            trunk.addQuadCurve(
                to: CGPoint(x: trunkX, y: trunkTop),
                control: CGPoint(x: stageCenter, y: trunkTop)
            )
            trunk.addLine(to: CGPoint(x: trunkX, y: bottoMostY))
            result.append((trunk, stage.color))

            for stepIndex in heights.indices {
                let y = FlowBoardMetrics.stepY(stage, stepIndex) + heights[stepIndex] / 2
                var branch = Path()
                branch.move(to: CGPoint(x: trunkX, y: y))
                branch.addLine(to: CGPoint(x: columnX, y: y))
                result.append((branch, stage.color))
            }
        }
        return result
    }

    /// 一竖一横的圆角折线：先沿起点 x 竖下，再拐向目标 x。
    private func elbow(from: CGPoint, to: CGPoint, midY: CGFloat, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: from)
        guard abs(to.x - from.x) > 0.5, midY > from.y else {
            path.addLine(to: to)
            return path
        }
        let direction: CGFloat = to.x > from.x ? 1 : -1
        let r = min(radius, abs(midY - from.y) / 2, abs(to.x - from.x) / 2)
        path.addLine(to: CGPoint(x: from.x, y: midY - r))
        path.addQuadCurve(
            to: CGPoint(x: from.x + direction * r, y: midY),
            control: CGPoint(x: from.x, y: midY)
        )
        path.addLine(to: CGPoint(x: to.x, y: midY))
        return path
    }
}

// MARK: - 阶段列

struct FlowDemoStageColumn: View {
    let stage: FlowDemoStage
    let palette: SpecRuneFlowTokens.Palette
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SpecRuneFlowTokens.stepGap) {
            FlowDemoStageCard(stage: stage, palette: palette)

            ForEach(Array(stage.steps.enumerated()), id: \.element.id) { item in
                FlowDemoNodeCard(
                    step: item.element,
                    stageColor: stage.color,
                    palette: palette,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(width: SpecRuneFlowTokens.cardWidth, alignment: .leading)
    }
}

// MARK: - 卡片

struct FlowDemoStageCard: View {
    let stage: FlowDemoStage
    let palette: SpecRuneFlowTokens.Palette

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    FlowDemoMark(color: stage.color, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stage.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(stage.caption)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    FlowDemoStatusBadge(text: stageBadge, color: stageBadgeColor)
                }

                Text(stage.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                FlowDemoMeter(progress: stage.progress, color: stage.color, palette: palette)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(height: SpecRuneFlowTokens.stageHeaderHeight - FlowBoardMetrics.footHeight, alignment: .topLeading)

            FlowDemoFootBar(text: "最近一次注入", palette: palette)
        }
        .frame(width: SpecRuneFlowTokens.cardWidth, height: SpecRuneFlowTokens.stageHeaderHeight)
        .background(cardSurface)
    }

    private var stageBadge: String {
        if stage.progress >= 1 { return "已完成" }
        if stage.progress > 0 { return "进行中" }
        return "待命"
    }

    private var stageBadgeColor: Color {
        if stage.progress >= 1 { return palette.okForeground }
        if stage.progress > 0 { return stage.color }
        return palette.muted
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: SpecRuneFlowTokens.radius, style: .continuous)
            .fill(palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: SpecRuneFlowTokens.radius, style: .continuous)
                    .strokeBorder(palette.cardRing, lineWidth: 1)
            )
            .shadow(
                color: palette.cardShadow.opacity(palette.cardShadowOpacity),
                radius: palette.cardShadowRadius,
                y: palette.cardShadowY
            )
    }
}

struct FlowDemoNodeCard: View {
    let step: FlowDemoStep
    let stageColor: Color
    let palette: SpecRuneFlowTokens.Palette
    let reduceMotion: Bool

    @State private var progress: Double = 0

    private var totalHeight: CGFloat {
        SpecRuneFlowTokens.stepCardHeight + (step.hasFoot ? FlowBoardMetrics.footHeight : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    FlowDemoMark(color: stageColor, size: 24)
                    Text(step.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    FlowDemoStepIcon(
                        status: step.status,
                        color: stageColor,
                        palette: palette,
                        reduceMotion: reduceMotion
                    )
                }

                Text(step.activity)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                FlowDemoMeter(progress: progress, color: stageColor, palette: palette)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(
                height: SpecRuneFlowTokens.stepCardHeight - (step.hasFoot ? FlowBoardMetrics.footHeight : 0),
                alignment: .topLeading
            )

            if step.hasFoot {
                FlowDemoFootBar(text: "SpecRune 最近一次注入", palette: palette)
            }
        }
        .frame(width: SpecRuneFlowTokens.cardWidth, height: totalHeight)
        .background(
            RoundedRectangle(cornerRadius: SpecRuneFlowTokens.radius, style: .continuous)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: SpecRuneFlowTokens.radius, style: .continuous)
                        .strokeBorder(palette.cardRing, lineWidth: 1)
                )
                .shadow(
                    color: palette.cardShadow.opacity(palette.cardShadowOpacity),
                    radius: palette.cardShadowRadius,
                    y: palette.cardShadowY
                )
        )
        .onAppear {
            guard !reduceMotion else {
                progress = step.progress
                return
            }
            withAnimation(SpecRuneFlowTokens.meter.delay(0.3)) {
                progress = step.progress
            }
        }
    }
}

struct FlowDemoRootCard: View {
    let palette: SpecRuneFlowTokens.Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                FlowDemoMark(color: palette.blue, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SpecRune 工作流图")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("@dae · 阶段 2 / 3")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                FlowDemoStatusBadge(text: "运行中", color: palette.blue)
            }

            Text("正在复刻卡片、连线与动效")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            FlowDemoMeter(progress: 0.62, color: palette.blue, palette: palette)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SpecRuneFlowTokens.radius, style: .continuous)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: SpecRuneFlowTokens.radius, style: .continuous)
                        .strokeBorder(palette.cardRing, lineWidth: 1)
                )
                .shadow(
                    color: palette.cardShadow.opacity(palette.cardShadowOpacity),
                    radius: palette.cardShadowRadius,
                    y: palette.cardShadowY
                )
        )
    }
}

// MARK: - 零件

struct FlowDemoMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.8)
            )
            .overlay {
                VStack(spacing: size * 0.1) {
                    HStack(spacing: size * 0.1) {
                        dot
                        dot
                    }
                    HStack(spacing: size * 0.1) {
                        dot
                        dot
                    }
                }
            }
            .frame(width: size, height: size)
    }

    private var dot: some View {
        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
            .fill(color.opacity(0.72))
            .frame(width: size * 0.22, height: size * 0.22)
    }
}

struct FlowDemoStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.1), in: Capsule())
    }
}

struct FlowDemoStepIcon: View {
    let status: FlowDemoStepStatus
    let color: Color
    let palette: SpecRuneFlowTokens.Palette
    let reduceMotion: Bool

    @State private var spinning = false

    var body: some View {
        Group {
            switch status {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.okForeground)
            case .active:
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .frame(width: 11, height: 11)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(SpecRuneFlowTokens.spin.repeatForever(autoreverses: false)) {
                            spinning = true
                        }
                    }
            case .idle:
                Circle()
                    .fill(palette.muted.opacity(0.55))
                    .frame(width: 7, height: 7)
            case .unknown:
                Text("—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(width: 14, height: 14)
    }
}

struct FlowDemoMeter: View {
    let progress: Double
    let color: Color
    let palette: SpecRuneFlowTokens.Palette

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.line)
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 3)

            Text("\(Int((max(0, min(1, progress)) * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.muted)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// 卡片下方那条浅色托盘。
struct FlowDemoFootBar: View {
    let text: String
    let palette: SpecRuneFlowTokens.Palette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.turn.down.left")
                .font(.system(size: 8, weight: .semibold))
            Image(systemName: "text.bubble")
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 10)
        .frame(width: SpecRuneFlowTokens.cardWidth, height: FlowBoardMetrics.footHeight)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: SpecRuneFlowTokens.radius,
                bottomTrailingRadius: SpecRuneFlowTokens.radius,
                style: .continuous
            )
            .fill(palette.fill)
        )
    }
}

// MARK: - Demo 入口页

struct SpecRuneFlowDemoView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var appeared = false
    @State private var resetToken = 0

    private var palette: SpecRuneFlowTokens.Palette {
        .resolve(colorScheme)
    }

    private var backdrop: Color {
        colorScheme == .dark ? Color(hex: 0x0D0F14) : Color(hex: 0xF6F7F9)
    }

    var body: some View {
        NavigationStack {
            FlowDemoCanvas(
                contentSize: CGSize(
                    width: FlowBoardMetrics.boardWidth,
                    height: FlowBoardMetrics.boardHeight
                ),
                resetToken: resetToken
            ) {
                FlowDemoBoard(
                    palette: palette,
                    appeared: appeared,
                    reduceMotion: reduceMotion
                )
            }
            .background(backdrop)
            .ignoresSafeArea(edges: .bottom)
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
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(SpecRuneFlowTokens.enter) {
                appeared = true
            }
        }
    }
}
