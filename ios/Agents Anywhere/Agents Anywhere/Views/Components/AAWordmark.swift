import SwiftUI

/// SpecRune 品牌字标：官方应用图标 + "SpecRune" 粗体字的组合，按 fontSize 等比缩放。
struct AAWordmark: View {
    let fontSize: CGFloat

    var body: some View {
        // 中心对齐：大图标与文字行框居中；文字行框下缘含 descender 空白，
        // 字形视觉中心偏高，图标下压 fontSize*0.02 让视觉重心回到字面中心。
        HStack(alignment: .center, spacing: fontSize * 0.24) {
            SpecRuneLogoMark(fontSize: fontSize)
                .offset(y: fontSize * 0.02)

            Text(verbatim: "SpecRune")
                .font(.system(size: fontSize, weight: .bold))
                .tracking(fontSize * -0.02)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
    }
}

private struct SpecRuneLogoMark: View {
    let fontSize: CGFloat

    var body: some View {
        // 官方应用图标整图（自带圆角与符文图形），透明边距已含在图内。
        Image("specrune-logo")
            .resizable()
            .frame(width: fontSize * 1.35, height: fontSize * 1.35)
            .clipShape(RoundedRectangle(cornerRadius: fontSize * 0.3, style: .continuous))
    }
}
