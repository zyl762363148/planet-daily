import SwiftUI

// MARK: - 数据模型

struct Digest: Codable {
    let date: String
    let generatedAt: String
    let categories: [DigestCategory]
    let topic: DigestTopic?
    let brief: DigestBrief?
    let hotlists: HotBoardSnapshot?
    let sports: SportsPayload?

    enum CodingKeys: String, CodingKey {
        case date
        case generatedAt = "generated_at"
        case categories
        case topic
        case brief
        case hotlists
        case sports
    }
}

// MARK: - 全网热榜（微博热搜 / 知乎热榜实时快照，参考「要知」的榜单样式）

struct HotBoardSnapshot: Codable {
    let updatedAt: String?
    let sources: [HotListSource]

    enum CodingKeys: String, CodingKey {
        case sources
        case updatedAt = "updated_at"
    }
}

struct HotListSource: Codable, Identifiable {
    let id: String
    let name: String
    let updatedAt: String?
    let items: [HotListEntry]

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case updatedAt = "updated_at"
    }
}

struct HotListEntry: Codable, Identifiable {
    let title: String
    let url: String
    let heat: String?
    let label: String?
    let prevRank: Int?

    enum CodingKeys: String, CodingKey {
        case title, url, heat, label
        case prevRank = "prev_rank"
    }

    var id: String { "\(url)|\(title)" }

    /// 「爆」「沸」等热搜标签；知乎来源没有标签。
    var badge: String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        return label
    }

    /// 位次趋势：传入当前名次，返回 nil 表示上一期未上榜。
    static func trend(currentRank: Int, prevRank: Int?) -> (symbol: String, isUp: Bool, isFlat: Bool)? {
        guard let prevRank else { return nil }
        let delta = prevRank - currentRank
        if delta == 0 { return ("—", false, true) }
        return (delta > 0 ? "↑\(delta)" : "↓\(-delta)", delta > 0, false)
    }

    /// 解析「109.5万」「784万」「1.2亿」为数值，用于热度条归一化；解析失败返回 nil。
    var heatValue: Double? {
        guard var text = heat?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        var multiplier = 1.0
        if text.hasSuffix("亿") {
            text = String(text.dropLast()); multiplier = 1e8
        } else if text.hasSuffix("万") {
            text = String(text.dropLast()); multiplier = 1e4
        } else if text.hasSuffix("回答") {
            text = String(text.dropLast(2))
        }
        let digits = text.filter { "0123456789.".contains($0) }
        guard let value = Double(digits), value > 0 else { return nil }
        return value * multiplier
    }
}

// MARK: - 赛事（NBA 比分快讯，ESPN 公开数据）

struct SportsPayload: Codable {
    let nba: NbaBoard?
}

struct NbaBoard: Codable {
    let updatedAt: String?
    let games: [NbaGame]

    enum CodingKeys: String, CodingKey {
        case games
        case updatedAt = "updated_at"
    }
}

struct NbaGame: Codable, Identifiable {
    let awayName: String
    let awayScore: Int?
    let homeName: String
    let homeScore: Int?
    let state: String
    let detail: String?
    let startText: String

    enum CodingKeys: String, CodingKey {
        case awayName = "away"
        case awayScore = "away_score"
        case homeName = "home"
        case homeScore = "home_score"
        case state, detail
        case startText = "start_text"
    }

    var id: String { "\(awayName)|\(homeName)|\(startText)" }

    /// 客队是否获胜（未开赛时无意义）。
    var awayWins: Bool {
        guard let awayScore, let homeScore else { return false }
        return awayScore > homeScore
    }
}

// MARK: - 跨日期归档搜索

struct ArchiveSearchHit: Identifiable {
    let date: String
    let definition: CategoryDefinition
    let item: DigestItem

    var id: String { "\(date)|\(definition.id)|\(item.id)" }
}

// MARK: - 24小时全球早报（含虎嗅早报风深度大事件 + 中外双视角对比）

struct DigestBrief: Codable {
    let headline: String?
    let summary: String
    let deepStories: [DigestDeepStory]?
    let points: [DigestBriefPoint]
    let opportunities: [DigestOpportunity]?
    let audioScript: String?
    let audioChapters: [String]?

    enum CodingKeys: String, CodingKey {
        case headline, summary, points, opportunities
        case deepStories = "deep_stories"
        case audioScript = "audio_script"
        case audioChapters = "audio_chapters"
    }
}

struct DigestDeepStory: Codable, Identifiable {
    let id: String
    let tag: String
    let title: String
    let lead: String
    let globalPerspective: String?
    let domesticPerspective: String?
    let impact: String?
    let sources: [String]?
    let url: String?
    let categoryID: String?
    let itemID: String?

    enum CodingKeys: String, CodingKey {
        case id, tag, title, lead, impact, sources, url
        case globalPerspective = "global_perspective"
        case domesticPerspective = "domestic_perspective"
        case categoryID = "category_id"
        case itemID = "item_id"
    }
}

// MARK: - 机会信号

struct DigestOpportunity: Codable, Identifiable {
    let title: String?
    let category: String?
    let categoryID: String?
    let itemID: String?
    let why: String?
    let how: String?
    let audience: String?

    enum CodingKeys: String, CodingKey {
        case title, category, why, how, audience
        case categoryID = "category_id"
        case itemID = "item_id"
    }

    var id: String {
        "\(itemID ?? "")|\(title ?? "")|\(why ?? "")"
    }

    var displayTitle: String {
        let value = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "值得跟进的机会" : value
    }
}

struct DigestBriefPoint: Codable, Identifiable {
    let category: String
    let categoryID: String?
    let itemID: String?
    let text: String

    enum CodingKeys: String, CodingKey {
        case category, text
        case categoryID = "category_id"
        case itemID = "item_id"
    }

    var id: String { "\(categoryID ?? "")|\(itemID ?? "")|\(text.prefix(24))" }
}

struct DigestBriefEntry: Identifiable {
    let point: DigestBriefPoint
    let definition: CategoryDefinition?
    let item: DigestItem?

    var id: String { point.id }
}

struct DigestTopic: Codable {
    let title: String
    let summary: String
    let points: [String]
    let tags: [String]?
    let itemIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case title, summary, points, tags
        case itemIDs = "item_ids"
    }
}

struct SourceCoverage: Codable {
    let available: Int
    let total: Int
    let issues: [String]?
}

struct DigestCategory: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let brief: String
    let items: [DigestItem]
    var coverage: SourceCoverage? = nil
}

struct TokenPromotion: Codable {
    let verified: Bool
    let kind: String
    let checkedAt: String
    let startsAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case verified, kind
        case checkedAt = "checked_at", startsAt = "starts_at", expiresAt = "expires_at"
    }
    func isCurrent(at now: Date = Date()) -> Bool {
        let parser = ISO8601DateFormatter()
        guard verified, ["limited_grant", "daily_event"].contains(kind),
              let checked = parser.date(from: checkedAt),
              let start = parser.date(from: startsAt),
              let end = parser.date(from: expiresAt) else { return false }
        let age = now.timeIntervalSince(checked)
        return age >= 0 && age < 86_400 && start <= checked && checked < end && start <= now && now < end
    }
    var checkedLabel: String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: checkedAt) else { return "核验时间不明" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "zh_CN")
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        format.dateFormat = "M月d日 HH:mm"
        return format.string(from: date) + " 核验"
    }
}

struct DigestItem: Codable, Identifiable {
    let id: String
    let title: String
    let originalTitle: String?
    let source: String
    let url: String
    let time: String?
    let heat: String?
    let score: Double?
    let summary: String
    let takeaway: String
    let interpretation: String
    let perspective: String?
    let tags: [String]?
    let audience: String?
    var promotion: TokenPromotion? = nil

    enum CodingKeys: String, CodingKey {
        case promotion
        case id, title, source, url, time, heat, score, summary, takeaway, interpretation, perspective, tags, audience
        case originalTitle = "original_title"
    }
}

// MARK: - 导航栏目

struct CategoryDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String

    var color: Color {
        PlanetTheme.category(id)
    }
}

struct DigestItemGroup: Identifiable {
    let definition: CategoryDefinition
    let brief: String
    let items: [DigestItem]

    var id: String { definition.id }
}

struct DigestTopicRelated: Identifiable {
    let definition: CategoryDefinition
    let item: DigestItem

    var id: String { "\(definition.id)-\(item.id)" }
}

struct FavoriteEntry: Codable, Identifiable {
    let key: String
    let date: String
    let categoryID: String
    let savedAt: String
    let item: DigestItem

    var id: String { key }
}

// MARK: - 一周

struct WeeklyItem: Identifiable {
    let date: String
    let definition: CategoryDefinition
    let item: DigestItem
    let isFavorite: Bool

    var id: String { "\(date)|\(definition.id)|\(item.id)" }
}

struct WeeklyGroup: Identifiable {
    let definition: CategoryDefinition
    let items: [WeeklyItem]

    var id: String { definition.id }
}

// MARK: - 天气（open-meteo）

struct WeatherConfig: Codable {
    let city: String
    let latitude: Double
    let longitude: Double

    static let fallback = WeatherConfig(city: "杭州富阳", latitude: 30.05, longitude: 119.95)
}

struct WeatherDay: Identifiable {
    let date: String
    let maxTemp: Double
    let minTemp: Double
    let weatherCode: Int

    var id: String { date }

    var symbolName: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// 报头天气文字（WMO code → 中文，spec 版式「杭州 12°C 晴」）。
    var conditionLabel: String {
        switch weatherCode {
        case 0, 1: return "晴"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51...57: return "毛毛雨"
        case 61...65, 80...82: return "雨"
        case 66, 67: return "冻雨"
        case 71...77, 85, 86: return "雪"
        case 95...99: return "雷雨"
        default: return "阴"
        }
    }

    var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: date) else { return date }
        let weekday = Calendar.current.component(.weekday, from: day)
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        let today = Calendar.current.isDateInToday(day)
        return today ? "今天" : "周" + labels[(weekday - 1) % 7]
    }
}

struct OpenMeteoResponse: Codable {
    let daily: DailyPayload

    struct DailyPayload: Codable {
        let time: [String]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case weatherCode = "weather_code"
        }
    }
}

// MARK: - 颜色

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 6 {
            value += "FF"
        }
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = Double((number >> 24) & 0xFF) / 255.0
        let green = Double((number >> 16) & 0xFF) / 255.0
        let blue = Double((number >> 8) & 0xFF) / 255.0
        let alpha = Double(number & 0xFF) / 255.0
        if value.count == 8 {
            self.init(red: red, green: green, blue: blue, opacity: alpha)
        } else {
            self.init(red: 0.35, green: 0.42, blue: 0.55)
        }
    }
}
