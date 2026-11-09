import SwiftUI
import AppKit

// MARK: - 统一视觉语言：纸面层次 / 发丝渐变线 / 今日提要
// 目标：深色皮肤下卡片不再与背景糊成一片；浅色皮肤下仍然保持纸张的干净。
// 所有颜色都从当前皮肤派生，不写死某一套色值。

final class RefinedHoverModel: ObservableObject {
    @Published var isOn: Bool = false
}

/// 卡片表层：纸色 + 顶部极淡高光 + 细描边 + 柔和投影，hover 时轻轻抬起 1.5pt。
struct RefinedSurface: ViewModifier {
    var interactive: Bool = true
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var scheme
    @StateObject private var hover = RefinedHoverModel()

    private var isDark: Bool { scheme == .dark }
    private var raised: Bool { interactive && hover.isOn }

    private var sheen: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color.white.opacity(0.075), Color.white.opacity(0.018), Color.white.opacity(0.005)]
                : [Color.white.opacity(0.92), Color.white.opacity(0.42), Color.white.opacity(0.08)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var edge: Color {
        isDark
            ? Color.white.opacity(raised ? 0.22 : 0.10)
            : Color.black.opacity(raised ? 0.15 : 0.075)
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PlanetTheme.paper)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(sheen)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(edge, lineWidth: 0.8)
            }
            .shadow(
                color: Color.black.opacity(isDark ? (raised ? 0.52 : 0.36) : (raised ? 0.13 : 0.065)),
                radius: raised ? 16 : 9,
                x: 0, y: raised ? 7 : 3
            )
            .shadow(
                color: Color.black.opacity(isDark ? 0.18 : 0.035),
                radius: 1, x: 0, y: 1
            )
            .offset(y: raised ? -1.5 : 0)
            .onHover { hover.isOn = $0 }
            .animation(.easeOut(duration: 0.18), value: hover.isOn)
    }
}

extension View {
    func refinedCard(cornerRadius: CGFloat = 16, interactive: Bool = true) -> some View {
        modifier(RefinedSurface(interactive: interactive, cornerRadius: cornerRadius))
    }
}

/// 从左到右淡出的发丝线：比一整条实线更轻，也更像印刷品的栏目分隔。
struct GradientRule: View {
    var strength: Double = 0.5
    var body: some View {
        LinearGradient(
            colors: [
                PlanetTheme.ink.opacity(strength),
                PlanetTheme.ink.opacity(strength * 0.42),
                PlanetTheme.ink.opacity(0.015),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 0.8)
    }
}

/// 刊头下方的「今日提要」：把当天最重要的一句话放到打开 App 的第一屏。
/// 数据来源完全是本地日报 JSON，不调用任何在线服务。
struct EditorLead: View {
    @EnvironmentObject private var store: DigestStore

    private var lead: String {
        // 优先当天最具体的一条深度新闻；模板化的「全景梳理」和「以下是今日重点」不作提要
        if let story = store.brief?.deepStories?.first?.title {
            let value = story.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        if let first = store.brief?.points.first?.text {
            let head = first.components(separatedBy: "——").first ?? first
            let value = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return String(value.prefix(72)) }
        }
        let summary = (store.brief?.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "" }
        if let end = summary.firstIndex(where: { "。！？!?；;".contains($0) }) {
            return String(summary[...end])
        }
        return String(summary.prefix(64))
    }

    var body: some View {
        if !lead.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(PlanetTheme.accent)
                    .frame(width: 3, height: 34)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(PlanetTheme.accent)
                            .frame(width: 4, height: 4)
                        Text("今日提要")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.9)
                            .foregroundStyle(PlanetTheme.accent)
                    }
                    Text(lead)
                        .font(.system(size: 17, weight: .medium))
                        .lineSpacing(5)
                        .foregroundStyle(PlanetTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
    }
}
