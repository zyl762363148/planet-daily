import SwiftUI
import CoreGraphics

/// 行星日报的原生矢量标记：日轮、三行版面、一道轨迹和一个新信号。
/// App 内和图标生成器共享同一份路径，避免缩放时出现两个版本。
struct PlanetBrandMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            context.withCGContext { cg in
                PlanetBrandDrawing.draw(in: cg, size: min(canvasSize.width, canvasSize.height))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum PlanetBrandDrawing {
    private static let paper = CGColor(srgbRed: 244 / 255, green: 241 / 255, blue: 234 / 255, alpha: 1)
    private static let ink = CGColor(srgbRed: 24 / 255, green: 61 / 255, blue: 77 / 255, alpha: 1)
    private static let signal = CGColor(srgbRed: 183 / 255, green: 80 / 255, blue: 58 / 255, alpha: 1)

    /// 所有坐标以左上为原点，采用 1024 × 1024 的设计画布。
    static func draw(in context: CGContext, size: CGFloat) {
        guard size > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: size / 1024, y: size / 1024)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // 方圆底保留透明四角；平面纸色不使用渐变、星空或发光效果。
        let field = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                           cornerWidth: 226, cornerHeight: 226, transform: nil)
        context.addPath(field)
        context.setFillColor(paper)
        context.fillPath()

        let globe = CGRect(x: 255, y: 271, width: 494, height: 494)
        context.setFillColor(ink)
        context.fillEllipse(in: globe)

        context.saveGState()
        context.addEllipse(in: globe)
        context.clip()
        context.setLineCap(.round)
        context.setStrokeColor(paper)
        context.setLineWidth(26)
        // 三条逐行缩进的负形，同时暗示报纸排版与观测刻度。
        for (y, endX): (CGFloat, CGFloat) in [(368, 620), (425, 570), (482, 515)] {
            context.move(to: CGPoint(x: 350, y: y))
            context.addLine(to: CGPoint(x: endX, y: y))
            context.strokePath()
        }
        // 轨迹穿过日轮时留一条纸白间隙，细小尺寸仍有明确的前后关系。
        context.setLineWidth(62)
        context.move(to: CGPoint(x: 190, y: 700))
        context.addLine(to: CGPoint(x: 770, y: 377))
        context.strokePath()
        context.restoreGState()

        context.setStrokeColor(ink)
        context.setLineWidth(26)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 190, y: 700))
        context.addLine(to: CGPoint(x: 770, y: 377))
        context.strokePath()

        context.setFillColor(signal)
        context.fillEllipse(in: CGRect(x: 792, y: 315, width: 64, height: 64))
    }
}
