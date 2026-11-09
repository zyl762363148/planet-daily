// 行星日报 App 图标 ——「观测日报」
// 原生矢量：纸色方圆底 + 墨蓝日轮/版面 + 斜向轨迹 + 朱砂新信号。
// 与 app/Sources/BrandMark.swift 共同编译；运行 ./build_icon.sh 生成 PNG 和 ICNS。

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct PlanetIconGenerator {
    static func main() {
        let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
        let side = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 1024) : 1024
        guard (16...4096).contains(side),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fail("无法创建 sRGB 图标画布")
        }
        // 位图 CGContext 采用下向上的坐标；共享标记使用上向下的设计坐标。
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        PlanetBrandDrawing.draw(in: context, size: CGFloat(side))
        guard let cgImage = context.makeImage() else { fail("图标渲染失败") }
        let url = URL(fileURLWithPath: output)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { fail("无法创建图标输出文件") }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { fail("图标写入失败") }
        print("已生成：\(url.path)（\(side) × \(side)，sRGB，透明四角）")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
