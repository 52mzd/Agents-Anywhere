import SwiftUI

/// SpecRune 任务流的视觉 token。
///
/// 数值全部取自 SpecRune 面板的 `req:backend/dsh-panel-visual` 与 `client.js` 的
/// `FLOW_THEME_CSS` / affectUI Agent Crew 组件 CSS。改这里之前先对照那份契约。
enum SpecRuneFlowTokens {

    // MARK: - 主题

    struct Palette {
        let tray: Color
        let card: Color
        let ink: Color
        let text: Color
        let muted: Color
        let line: Color
        let fill: Color
        let tag: Color
        let blue: Color
        let brandBackground: Color
        let brandForeground: Color
        let okBackground: Color
        let okForeground: Color
        let warnBackground: Color
        let warnForeground: Color
        let dangerBackground: Color
        let dangerForeground: Color
        let cardRing: Color
        let cardShadow: Color
        let cardShadowOpacity: Double
        let cardShadowRadius: CGFloat
        let cardShadowY: CGFloat

        static let light = Palette(
            tray: Color(hex: 0xE9E9EF),
            card: Color(hex: 0xFFFFFF),
            ink: Color(hex: 0x17171A),
            text: Color(hex: 0x3A3A42),
            muted: Color(hex: 0x78787F),
            line: Color(hex: 0xECECF0),
            fill: Color(hex: 0xF5F5F7),
            tag: Color(hex: 0xF7F7F9),
            blue: Color(hex: 0x0A84FF),
            brandBackground: Color(hex: 0xEAF1FF),
            brandForeground: Color(hex: 0x2456D6),
            okBackground: Color(hex: 0xE6F6ED),
            okForeground: Color(hex: 0x1E8A4F),
            warnBackground: Color(hex: 0xFFF1E0),
            warnForeground: Color(hex: 0xB25E00),
            dangerBackground: Color(hex: 0xFDECEA),
            dangerForeground: Color(hex: 0xC4320A),
            cardRing: Color(hex: 0xE3E3EA),
            cardShadow: Color(hex: 0x101018),
            cardShadowOpacity: 0.18,
            cardShadowRadius: 8,
            cardShadowY: 6
        )

        static let dark = Palette(
            tray: Color(hex: 0x1E1E22),
            card: Color(hex: 0x161618),
            ink: Color(hex: 0xE8E8EA),
            text: Color(hex: 0xC8CCD4),
            muted: Color(hex: 0x8A8F9A),
            line: Color(hex: 0x2A2A30),
            fill: Color(hex: 0x242428),
            tag: Color(hex: 0x1F242E),
            blue: Color(hex: 0x2F7CF6),
            brandBackground: Color(hex: 0x1B2A45),
            brandForeground: Color(hex: 0x8AB4FF),
            okBackground: Color(hex: 0x14301F),
            okForeground: Color(hex: 0x2EC98F),
            warnBackground: Color(hex: 0x33260F),
            warnForeground: Color(hex: 0xE0A35A),
            dangerBackground: Color(hex: 0x35171A),
            dangerForeground: Color(hex: 0xFF6B6B),
            cardRing: Color.clear,
            cardShadow: Color.black,
            cardShadowOpacity: 0.38,
            cardShadowRadius: 12,
            cardShadowY: 8
        )

        static func resolve(_ scheme: ColorScheme) -> Palette {
            scheme == .dark ? .dark : .light
        }
    }

    // MARK: - 节点主题色（按层级索引取色）

    /// 节点主题色的 RGB 分量，供地面闪光按原版 `color-mix` 公式算 floor-1/2/3。
    static let nodeColorRGBA: [(r: Double, g: Double, b: Double, a: Double)] = [
        (166 / 255, 81 / 255, 240 / 255, 0.85),
        (20 / 255, 179 / 255, 240 / 255, 0.85),
        (95 / 255, 200 / 255, 138 / 255, 0.9),
        (238 / 255, 62 / 255, 158 / 255, 0.8),
        (94 / 255, 106 / 255, 210 / 255, 0.85),
        (20 / 255, 160 / 255, 150 / 255, 0.85),
    ]

    /// `--ui-acr-floor-1/2/3`：顶浅、中主色、底深，各自带 alpha。
    static func floorColors(_ index: Int) -> (top: Color, mid: Color, bottom: Color) {
        let rgba = nodeColorRGBA[index % nodeColorRGBA.count]
        let top = Color(
            red: rgba.r * 0.55 + 0.45,
            green: rgba.g * 0.55 + 0.45,
            blue: rgba.b * 0.55 + 0.45
        ).opacity(0.55)
        let mid = Color(red: rgba.r, green: rgba.g, blue: rgba.b).opacity(0.5)
        let bottom = Color(
            red: rgba.r * 0.85,
            green: rgba.g * 0.85,
            blue: rgba.b * 0.85
        ).opacity(0.45)
        return (top, mid, bottom)
    }

    static let nodeColors: [Color] = [
        Color(red: 166 / 255, green: 81 / 255, blue: 240 / 255).opacity(0.85),
        Color(red: 20 / 255, green: 179 / 255, blue: 240 / 255).opacity(0.85),
        Color(red: 95 / 255, green: 200 / 255, blue: 138 / 255).opacity(0.9),
        Color(red: 238 / 255, green: 62 / 255, blue: 158 / 255).opacity(0.8),
        Color(red: 94 / 255, green: 106 / 255, blue: 210 / 255).opacity(0.85),
        Color(red: 20 / 255, green: 160 / 255, blue: 150 / 255).opacity(0.85),
    ]

    // MARK: - 尺寸（桌面 1:1，靠画布缩放适配手机）

    /// `.ui-acr` 的 `--ui-acr-card-w`。
    static let cardWidth: CGFloat = 222
    /// `.ui-acr__below` 的 `padding-left`。
    static let indent: CGFloat = 24
    /// `.ui-acr__level` 的 `gap`。
    static let levelGap: CGFloat = 8
    /// `.ui-acr__level` 的 `margin-top`。
    static let levelTopMargin: CGFloat = 40
    /// `.ui-acr__hang` / `.ui-acr__below` 的 `gap`。
    static let nodeGap: CGFloat = 10
    /// 节点托盘：`.ui-acr__node` 的 padding 与圆角。
    static let trayPadding: CGFloat = 4
    static let trayRadius: CGFloat = 16
    /// 卡片圆角 = 托盘圆角 - 4。
    static let cardRadius: CGFloat = 12

    /// 节点高度（托盘 + 卡片），布局与闪光裁剪共用。
    static let nodeHeight: CGFloat = 128
    static let avatarSize: CGFloat = 24
    static let statusHeight: CGFloat = 20
    static let footHeight: CGFloat = 28
    static let meterHeight: CGFloat = 3

    // MARK: - 动效

    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    static let enter = ease(0.38)
    static let linkDraw = ease(0.52)
    static let linkDrawDelay: Double = 0.12
    static let pop = ease(0.2)
    static let meter = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.7)
    static let spin: Double = 0.9
    static let pixel: Double = 1.2
    static let shine: Double = 2.0
    static let glow: Double = 0.95
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
