import AppKit
import SwiftUI

// MARK: - 皮肤
// 所有颜色都从当前皮肤色板取值；切换皮肤后视图重绘即生效。
// 每项是 (浅色模式, 深色模式) 的十六进制值，跟随系统外观自动切换。

struct SkinPalette {
    let canvas: (String, String)
    let paper: (String, String)
    let sidebar: (String, String)
    let ink: (String, String)
    let secondary: (String, String)
    let muted: (String, String)
    let accent: (String, String)
    let rule: (String, String)
    let selection: (String, String)
    let opportunity: (String, String)
    let opportunityInk: (String, String)
    let navy: (String, String)
    let whiteInk: (String, String)
    let hotWeibo: (String, String)
    let hotZhihu: (String, String)
    let gold: (String, String)
    let bronze: (String, String)
    let catCool: (String, String)
    let catPolicy: (String, String)
    let catTech: (String, String)
    let catGreen: (String, String)
    let catWarm: (String, String)
    let catRose: (String, String)
}

enum PlanetSkin: String, CaseIterable, Identifiable {
    case ink, paper, midnight, sage, clay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: return "晨报纸白"
        case .paper: return "极简冷白"
        case .midnight: return "深夜蓝"
        case .sage: return "青瓷"
        case .clay: return "赤陶"
        }
    }

    var subtitle: String {
        switch self {
        case .ink: return "暖米纸面 · 砖红点题"
        case .paper: return "中性灰白 · 克莱因蓝"
        case .midnight: return "冷调靛蓝 · 琥珀点题"
        case .sage: return "低饱和青绿 · 护眼"
        case .clay: return "暖陶土色 · 柔和"
        }
    }

    static var current: PlanetSkin {
        PlanetSkin(rawValue: UserDefaults.standard.string(forKey: "dailydigest.skin") ?? "ink") ?? .ink
    }

    var palette: SkinPalette {
        switch self {
        case .ink:
            return SkinPalette(
                canvas: ("F1EDE4", "101214"), paper: ("FEFDF9", "1B1D1F"),
                sidebar: ("EAE6DC", "15191C"), ink: ("1C2B33", "EDF0EE"),
                secondary: ("59666B", "B0B8B9"), muted: ("69777A", "A5AFB0"),
                accent: ("B7503A", "E89A83"), rule: ("DDD8CB", "383D40"),
                selection: ("E0DBCF", "2B3338"), opportunity: ("EDF1E9", "26322D"),
                opportunityInk: ("435C43", "C3D3C0"), navy: ("183D4D", "214F63"),
                whiteInk: ("F5F3EB", "F5F3EB"), hotWeibo: ("E05638", "E88A6E"),
                hotZhihu: ("2C6FA8", "7FAFD4"), gold: ("B8912B", "D8B45C"),
                bronze: ("B87333", "D8A06B"), catCool: ("4C7A8C", "9FC3D4"),
                catPolicy: ("2C4A7C", "A8BEDD"), catTech: ("506D7B", "A4C2CF"),
                catGreen: ("4D715F", "ACCCB8"), catWarm: ("82623C", "D7BE9B"),
                catRose: ("835B66", "D7B0BC"))
        case .paper:
            return SkinPalette(
                canvas: ("F5F6F7", "141618"), paper: ("FFFFFF", "1E2124"),
                sidebar: ("EDEFF1", "171A1D"), ink: ("1B2430", "ECEFF2"),
                secondary: ("5A6572", "AEB8C2"), muted: ("74808C", "98A3AD"),
                accent: ("2F6F9E", "7FB6DC"), rule: ("DDE2E7", "363C42"),
                selection: ("E4E9EE", "2B3238"), opportunity: ("EDF4F8", "22303A"),
                opportunityInk: ("3B6076", "BCD6E4"), navy: ("1B3A52", "244C68"),
                whiteInk: ("F7F9FB", "F7F9FB"), hotWeibo: ("D6543A", "E98A72"),
                hotZhihu: ("2C6FA8", "7FAFD4"), gold: ("A8862B", "D8B45C"),
                bronze: ("A97233", "D8A06B"), catCool: ("3F7086", "9FC3D4"),
                catPolicy: ("35598C", "AEC6E4"), catTech: ("4A6675", "A8C6D6"),
                catGreen: ("427060", "A6CFB6"), catWarm: ("85704A", "DCC5A2"),
                catRose: ("8A6270", "DDB9C5"))
        case .midnight:
            return SkinPalette(
                canvas: ("E8EDF3", "0B1420"), paper: ("F7FAFD", "121E2C"),
                sidebar: ("DCE5EF", "0E1A28"), ink: ("16283A", "E4ECF5"),
                secondary: ("4E6478", "A9BDD0"), muted: ("62788C", "93A9BE"),
                accent: ("C07A4A", "E8B183"), rule: ("CBD7E3", "2A3B4C"),
                selection: ("D6E1EC", "1C2D3E"), opportunity: ("E4EFE8", "1C332A"),
                opportunityInk: ("3A6350", "B7D4C2"), navy: ("122C42", "1B3E59"),
                whiteInk: ("F2F6FB", "F2F6FB"), hotWeibo: ("D45F42", "EB9A7C"),
                hotZhihu: ("3B72A6", "8AB6D8"), gold: ("A98B35", "D8B45C"),
                bronze: ("A97540", "D8A06B"), catCool: ("3F6C8A", "9CC0D8"),
                catPolicy: ("2E4E86", "AFC6E6"), catTech: ("4C6B84", "A6C4DA"),
                catGreen: ("3E6E5A", "A8CCB8"), catWarm: ("7C6440", "D6BF9C"),
                catRose: ("7E5D70", "D4B2C2"))
        case .sage:
            return SkinPalette(
                canvas: ("EEF1EA", "101814"), paper: ("FBFCF8", "1A221D"),
                sidebar: ("E5EBE1", "141C17"), ink: ("1D2C25", "E8F0E9"),
                secondary: ("566B5D", "AFC3B5"), muted: ("6B8072", "A0B7A6"),
                accent: ("3E7A5E", "8FC7A4"), rule: ("D6DFD3", "334138"),
                selection: ("DFE8DA", "25352A"), opportunity: ("E9F1E7", "203426"),
                opportunityInk: ("3D6447", "BED8C2"), navy: ("1B4034", "245442"),
                whiteInk: ("F3F7F1", "F3F7F1"), hotWeibo: ("C2603E", "E3A07E"),
                hotZhihu: ("3A7180", "8FBFC9"), gold: ("96852F", "D2BA66"),
                bronze: ("9A7640", "D2AC74"), catCool: ("4A7466", "A8CDBB"),
                catPolicy: ("3C5F52", "B0CFBF"), catTech: ("496E60", "A6CBB8"),
                catGreen: ("3F7454", "AAD2B2"), catWarm: ("7A6A3E", "D4C39A"),
                catRose: ("7A6264", "CFB4B7"))
        case .clay:
            return SkinPalette(
                canvas: ("F4EDE7", "1C1513"), paper: ("FEFAF6", "241B18"),
                sidebar: ("EEE3DA", "1A1311"), ink: ("30241F", "F2E9E2"),
                secondary: ("6E5649", "C5A99A"), muted: ("836A5C", "B99C8C"),
                accent: ("B7503A", "E89A83"), rule: ("E3D5C8", "403029"),
                selection: ("EADFD3", "33251F"), opportunity: ("EDF0E5", "2B3023"),
                opportunityInk: ("52613F", "CBD6B4"), navy: ("4A2E26", "5C3A2E"),
                whiteInk: ("FBF5EF", "FBF5EF"), hotWeibo: ("C45436", "E79172"),
                hotZhihu: ("6B6A93", "AFAED0"), gold: ("A2812C", "D5B45F"),
                bronze: ("A96F38", "D5A06C"), catCool: ("6E6A73", "BEB8C6"),
                catPolicy: ("5C515F", "BFB2C6"), catTech: ("6C6068", "C5B7BE"),
                catGreen: ("5D6A4C", "BFC9A8"), catWarm: ("8A633C", "DCC0A0"),
                catRose: ("8C5C5C", "DCB5B5"))
        }
    }
}

// One palette for the newspaper, the radio and native navigation.
enum PlanetTheme {
    static var skin: PlanetSkin { PlanetSkin.current }

    static func color(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hexValue: darkMode ? dark : light)
        })
    }

    private static var p: SkinPalette { skin.palette }
    private static func pair(_ value: (String, String)) -> Color { color(value.0, value.1) }

    static var canvas: Color { pair(p.canvas) }
    static var paper: Color { pair(p.paper) }
    static var sidebar: Color { pair(p.sidebar) }
    static var ink: Color { pair(p.ink) }
    static var secondary: Color { pair(p.secondary) }
    static var muted: Color { pair(p.muted) }
    static var accent: Color { pair(p.accent) }
    static var rule: Color { pair(p.rule) }
    static var selection: Color { pair(p.selection) }
    static var opportunity: Color { pair(p.opportunity) }
    static var opportunityInk: Color { pair(p.opportunityInk) }
    static var navy: Color { pair(p.navy) }
    static var whiteInk: Color { pair(p.whiteInk) }
    static var hotWeibo: Color { pair(p.hotWeibo) }
    static var hotZhihu: Color { pair(p.hotZhihu) }
    static var gold: Color { pair(p.gold) }
    static var bronze: Color { pair(p.bronze) }

    static func category(_ id: String) -> Color {
        switch id {
        case "wire", "global": return pair(p.catCool)
        case "policy": return pair(p.catPolicy)
        case "ai", "infogap": return pair(p.catTech)
        case "opensource", "health", "sport": return pair(p.catGreen)
        case "economy", "life": return pair(p.catWarm)
        case "design", "media", "games": return pair(p.catRose)
        // accent 纪律：强调色只允许出现在侧栏指示条 / 电台卡播放键 / 简报序号；
        // overview/hotboard/favorites/week 等非内容栏目一律灰阶。
        default: return pair(p.secondary)
        }
    }
}

private extension NSColor {
    convenience init(hexValue value: String) {
        let hex = UInt64(value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0
        self.init(srgbRed: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, alpha: 1)
    }
}
