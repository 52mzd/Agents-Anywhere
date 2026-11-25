import SwiftUI

/// SpecRune 任务流的视觉 token。
///
/// 数值全部移植自 SpecRune 面板的 `req:backend/dsh-panel-visual`（`plugins/dsh/panel/lib/client.js`
/// 里的 `FLOW_THEME_CSS`）：两套主题色、阶段主题色、阴影与动效时长。改这里之前先对照那份契约。
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
        let blue: Color
        let okForeground: Color
        let warnForeground: Color
        let dangerForeground: Color
        /// 卡片描边（CSS 的第一段 `0 0 0 1px`）。
        let cardRing: Color
        /// 卡片柔和投影主色。
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
            blue: Color(hex: 0x0A84FF),
            okForeground: Color(hex: 0x1E8A4F),
            warnForeground: Color(hex: 0xB25E00),
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
            blue: Color(hex: 0x2F7CF6),
            okForeground: Color(hex: 0x2EC98F),
            warnForeground: Color(hex: 0xE0A35A),
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

    // MARK: - 阶段主题色（子节点按索引取色）

    static let stageColors: [Color] = [
        Color(red: 166 / 255, green: 81 / 255, blue: 240 / 255).opacity(0.85),
        Color(red: 20 / 255, green: 179 / 255, blue: 240 / 255).opacity(0.85),
        Color(red: 95 / 255, green: 200 / 255, blue: 138 / 255).opacity(0.9),
    ]

    // MARK: - 尺寸（桌面 1:1，靠画布缩放适配手机）

    static let cardWidth: CGFloat = 222
    static let avatarSize: CGFloat = 44
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 16
    static let stageGap: CGFloat = 16
    static let stepGap: CGFloat = 40
    static let stageHeaderHeight: CGFloat = 116
    static let stepCardHeight: CGFloat = 104

    // MARK: - 动效（CSS 毫秒）

    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    static let enter = ease(0.38)
    static let linkDraw = ease(0.52)
    static let linkDrawDelay: Double = 0.12
    static let panelPop = ease(0.2)
    static let meter = Animation.easeOut(duration: 0.7)
    static let spin = Animation.linear(duration: 0.9)
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
