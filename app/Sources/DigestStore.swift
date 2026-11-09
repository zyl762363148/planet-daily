import AppKit
import SwiftUI
import Combine
import Foundation

/// 一个可选模块；侧栏完全由 config.json 的 modules.catalog 驱动，不再写死。
struct ModuleEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let group: String
    let broadcastDefault: Bool
}

final class DigestStore: ObservableObject {
    // MARK: - Published state

    @Published var digest: Digest?
    @Published var selectedCategoryID: String = DigestStore.overviewID
    @Published var overviewPulseFilter: String = "all"
    @Published var searchText: String = "" {
        didSet { scheduleArchiveSearch() }
    }
    @Published var archiveResults: [ArchiveSearchHit] = []
    @Published var isArchiveSearching: Bool = false
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var favorites: [FavoriteEntry] = []
    @Published var availableDateStrings: Set<String> = []
    @Published var pendingItemID: String?
    @Published var weatherDays: [WeatherDay] = []
    @Published var weatherCity: String = "杭州富阳"
    @Published var weatherFailed: Bool = false
    @Published var weatherLoading: Bool = false

    // MARK: - 用户可配置项（统一写回 config.json，后端下次生成即生效）
    @Published var moduleCatalog: [ModuleEntry] = []
    @Published var enabledModuleIDs: [String] = []
    @Published var broadcastModuleIDs: [String] = []
    @Published var broadcastMaxItems: Int = 3
    @Published var includeWeatherInBroadcast: Bool = true
    @Published var includeHotTopicsInBroadcast: Bool = true
    @Published var includeSportsInBroadcast: Bool = false
    @Published var showHotlists: Bool = true
    @Published var showSportsBoard: Bool = true
    @Published var showTopic: Bool = true
    @Published var showOpportunities: Bool = false
    @Published var weatherEnabled: Bool = true
    @Published var weatherLatitude: Double = 30.05
    @Published var weatherLongitude: Double = 119.95
    @Published var skin: String = UserDefaults.standard.string(forKey: "dailydigest.skin") ?? "ink" {
        didSet { UserDefaults.standard.set(skin, forKey: "dailydigest.skin") }
    }

    /// 本地预渲染音频、精确章节和可配置定时播放。
    let tts = TTSPlayer()

    private var archiveCache: [String: Digest] = [:]
    private var archiveSearchWork: DispatchWorkItem?

    // MARK: - Paths

    let baseRoot: URL
    let dataDirectory: URL
    let backendScript: URL

    private let fileManager = FileManager.default
    private let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private let chineseTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
    private let mastheadDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日"
        return formatter
    }()
    private let mastheadWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        return formatter
    }()
    private let chineseTitleWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private let favoriteTimestampFormatter = ISO8601DateFormatter()
    private var generationProcess: Process?
    private var loadedFileModification: Date?
    private var followsLatest = true

    @Published var appearanceMode: String = UserDefaults.standard.string(forKey: "dailydigest.appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "dailydigest.appearance") }
    }
    var preferredAppearance: ColorScheme? {
        appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil
    }

    // MARK: - Categories

    static let overviewID = "overview"
    static let favoritesID = "favorites"
    static let weekID = "week"
    static let hotboardID = "hotboard"

    let overviewDefinition = CategoryDefinition(
        id: DigestStore.overviewID,
        name: "今日速览",
        icon: "sun.max.fill",
        colorHex: "#E86A33"
    )

    let hotboardDefinition = CategoryDefinition(
        id: DigestStore.hotboardID,
        name: "热榜速览",
        icon: "flame.fill",
        colorHex: "#D95436"
    )

    let favoritesDefinition = CategoryDefinition(
        id: DigestStore.favoritesID,
        name: "收藏",
        icon: "star.fill",
        colorHex: "#D99A2B"
    )

    let weekDefinition = CategoryDefinition(
        id: DigestStore.weekID,
        name: "一周回顾",
        icon: "calendar",
        colorHex: "#8B5CF6"
    )

    /// 旧版 config.json 没有 catalog 时的兜底（与后端 modules_config.CATALOG 一致）。
    static let fallbackCatalog: [ModuleEntry] = [
        ModuleEntry(id: "wire", name: "环球通讯社", icon: "globe.asia.australia", colorHex: "#4C7A8C", group: "要闻", broadcastDefault: true),
        ModuleEntry(id: "global", name: "外媒编译", icon: "newspaper", colorHex: "#3F6E8C", group: "要闻", broadcastDefault: true),
        ModuleEntry(id: "policy", name: "政策解读", icon: "building.columns", colorHex: "#2C4A7C", group: "要闻", broadcastDefault: true),
        ModuleEntry(id: "economy", name: "财经观察", icon: "chart.line.uptrend.xyaxis", colorHex: "#82623C", group: "要闻", broadcastDefault: true),
        ModuleEntry(id: "infogap", name: "信息差", icon: "sparkles", colorHex: "#506D7B", group: "科技", broadcastDefault: false),
        ModuleEntry(id: "ai", name: "人工智能", icon: "brain.head.profile", colorHex: "#7C5CFF", group: "科技", broadcastDefault: true),
        ModuleEntry(id: "opensource", name: "开源动态", icon: "chevron.left.forwardslash.chevron.right", colorHex: "#22A06B", group: "科技", broadcastDefault: false),
        ModuleEntry(id: "sport", name: "体育资讯", icon: "sportscourt", colorHex: "#2E7D6B", group: "生活", broadcastDefault: false),
        ModuleEntry(id: "life", name: "生活消费", icon: "house", colorHex: "#B07A3C", group: "生活", broadcastDefault: false),
        ModuleEntry(id: "health", name: "健康生活", icon: "heart.text.square", colorHex: "#D65050", group: "生活", broadcastDefault: false),
        ModuleEntry(id: "games", name: "游戏资讯", icon: "gamecontroller", colorHex: "#776493", group: "兴趣", broadcastDefault: false),
        ModuleEntry(id: "design", name: "设计灵感", icon: "paintpalette", colorHex: "#D95B8A", group: "兴趣", broadcastDefault: false),
        ModuleEntry(id: "media", name: "新媒动态", icon: "megaphone", colorHex: "#1F9D9B", group: "兴趣", broadcastDefault: false),
    ]

    static let defaultEnabled = [
        "wire", "global", "policy", "economy", "infogap", "ai",
        "sport", "life", "health", "games", "opensource",
    ]
    static let defaultBroadcast = ["wire", "global", "policy", "economy", "ai"]

    /// 由配置生成的全量栏目定义（不再写死）。
    var definitions: [CategoryDefinition] {
        moduleCatalog.map {
            CategoryDefinition(id: $0.id, name: $0.name, icon: $0.icon, colorHex: $0.colorHex)
        }
    }

    /// 侧栏按 catalog 的 group 动态分组，只显示用户勾选的模块。
    var sidebarGroups: [(title: String, definitions: [CategoryDefinition])] {
        let enabled = Set(enabledModuleIDs)
        var result: [(String, [CategoryDefinition])] = [
            ("今日", [overviewDefinition] + (showHotlists ? [hotboardDefinition] : [])),
        ]
        for group in ["要闻", "科技", "生活", "兴趣", "活动", "其他"] {
            let defs = moduleCatalog
                .filter { enabled.contains($0.id) && $0.group == group }
                .map { CategoryDefinition(id: $0.id, name: $0.name, icon: $0.icon, colorHex: $0.colorHex) }
            if !defs.isEmpty { result.append((group, defs)) }
        }
        return result
    }

    init(startBackgroundServices: Bool = true) {
        let envRoot = ProcessInfo.processInfo.environment["DIGEST_DATA_ROOT"]
        let userRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DailyDigest", isDirectory: true)
        if let envRoot, !envRoot.isEmpty {
            baseRoot = URL(fileURLWithPath: envRoot, isDirectory: true)
        } else {
            baseRoot = userRoot
        }
        dataDirectory = baseRoot.appendingPathComponent("data", isDirectory: true)
        backendScript = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/DailyDigest/backend/run_generate.sh")
        loadConfig()
        loadFavorites()
        loadInitial()
        refreshAvailableDates()
        // 报头合并了天气段：启动即预热，异步返回后自动刷新
        if startBackgroundServices {
            loadWeather()
            scheduleAutoGenerateIfNeeded()
        }
    }

    // MARK: - Computed values

    var isOverview: Bool {
        selectedCategoryID == DigestStore.overviewID
    }

    var isHotboard: Bool {
        selectedCategoryID == DigestStore.hotboardID
    }

    var isFavorites: Bool {
        selectedCategoryID == DigestStore.favoritesID
    }

    var isWeek: Bool {
        selectedCategoryID == DigestStore.weekID
    }

    var selectedDefinition: CategoryDefinition {
        if isOverview { return overviewDefinition }
        if isHotboard { return hotboardDefinition }
        if isFavorites { return favoritesDefinition }
        if isWeek { return weekDefinition }
        return definitions.first(where: { $0.id == selectedCategoryID }) ?? overviewDefinition
    }

    /// 全网热榜快照：只保留有词条的来源。
    var hotBoard: HotBoardSnapshot? {
        guard let snapshot = digest?.hotlists else { return nil }
        let sources = snapshot.sources.filter { !$0.items.isEmpty }
        return sources.isEmpty ? nil : HotBoardSnapshot(updatedAt: snapshot.updatedAt, sources: sources)
    }

    var hotBoardItemCount: Int {
        hotBoard?.sources.reduce(0) { $0 + $1.items.count } ?? 0
    }

    /// NBA 比分快照（数据缺失时为空数组）。
    var nbaGames: [NbaGame] {
        digest?.sports?.nba?.games ?? []
    }

    /// 报纸期数：本地已归档的日报期数。
    var issueNumber: Int {
        availableDateStrings.count
    }

    /// 农历日期（如「九月十二」），用系统中国农历推算，取不到返回 nil。
    var lunarLabel: String? {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        let components = calendar.dateComponents([.month, .day], from: selectedDate)
        guard let month = components.month, let day = components.day,
              (1...12).contains(month), (1...30).contains(day) else { return nil }
        let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月",
                          "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        let dayName: String
        switch day {
        case 1...10: dayName = "初" + digits[day - 1]
        case 11...19: dayName = "十" + digits[day - 11]
        case 20: dayName = "二十"
        case 21...29: dayName = "廿" + digits[day - 21]
        default: dayName = "三十"
        }
        let leap = components.isLeapMonth == true ? "闰" : ""
        return "\(leap)\(monthNames[month - 1])\(dayName)"
    }

    func definition(for categoryID: String) -> CategoryDefinition? {
        definitions.first(where: { $0.id == categoryID })
    }

    var selectedCategory: DigestCategory? {
        guard !isOverview, !isFavorites, !isWeek else { return nil }
        return digest?.categories.first(where: { $0.id == selectedCategoryID })
    }

    var items: [DigestItem] {
        guard let category = selectedCategory else { return [] }
        return visibleItems(in: category, on: dateString)
    }

    private func visibleItems(in category: DigestCategory, on date: String) -> [DigestItem] {
        guard category.id == "tokens" else { return category.items }
        return category.items.filter { item in
            guard let promotion = item.promotion else { return false }
            return date == todayString ? promotion.isCurrent() : promotion.verified
        }
    }

    var categoryGroups: [DigestItemGroup] {
        guard let digest else { return [] }
        return definitions.compactMap { definition in
            guard let category = digest.categories.first(where: { $0.id == definition.id }) else {
                return nil
            }
            return DigestItemGroup(
                definition: definition,
                brief: category.brief,
                items: visibleItems(in: category, on: digest.date)
            )
        }
    }

    var featuredGroups: [DigestItemGroup] {
        let preferred = ["wire", "ai", "economy", "policy", "infogap", "opensource"]
        return preferred.compactMap { id in
            categoryGroups.first(where: { $0.definition.id == id })
        }
    }

    var topic: DigestTopic? {
        if let topic = digest?.topic,
           !topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return topic
        }
        return fallbackTopic
    }

    var topicRelatedItems: [DigestTopicRelated] {
        guard let ids = topic?.itemIDs, !ids.isEmpty else { return [] }
        let wanted = Set(ids)
        return categoryGroups.flatMap { group in
            group.items.compactMap { item in
                wanted.contains(item.id)
                    ? DigestTopicRelated(definition: group.definition, item: item)
                    : nil
            }
        }
    }

    // MARK: - 24小时重磅深读（虎嗅早报风 + 中外双视角对比）

    var brief: DigestBrief? {
        guard let brief = digest?.brief,
              !brief.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return brief
    }

    var editionHeadline: String {
        if let hl = brief?.headline, !hl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hl
        }
        if let topicTitle = digest?.topic?.title, !topicTitle.isEmpty {
            return "过去 24 小时全球焦点：\(topicTitle)"
        }
        return "过去 24 小时全球科技、政经与产业核心动态全景梳理"
    }

    var deepStories: [DigestDeepStory] {
        if let stories = brief?.deepStories, !stories.isEmpty {
            return stories
        }
        // 针对旧日期 JSON 自动从核心栏目合成深度卡片，保证历史日期同样拥有虎嗅早报式双视角排版
        let priorityOrder = ["ai", "wire", "economy", "policy", "infogap", "opensource"]
        var generated: [DigestDeepStory] = []
        var idx = 1
        for cid in priorityOrder {
            guard let group = categoryGroups.first(where: { $0.definition.id == cid }),
                  let topItem = group.items.first else { continue }
            generated.append(
                DigestDeepStory(
                    id: "fallback-story-\(idx)",
                    tag: "\(group.definition.name) · 24h 焦点",
                    title: topItem.title,
                    lead: topItem.summary,
                    globalPerspective: topItem.interpretation,
                    domesticPerspective: topItem.perspective ?? topItem.takeaway,
                    impact: topItem.takeaway,
                    sources: [topItem.source],
                    url: topItem.url,
                    categoryID: group.definition.id,
                    itemID: topItem.id
                )
            )
            idx += 1
            if generated.count >= 5 { break }
        }
        return generated
    }

    var briefEntries: [DigestBriefEntry] {
        guard let brief else { return [] }
        return brief.points.map { point in
            // 旧简报可能只有历史栏目名没有 ID；通过当期归档反查 ID。
            let legacyID = digest?.categories.first(where: { $0.name == point.category })?.id
            let definition = definitions.first(where: { $0.id == point.categoryID })
                ?? definitions.first(where: { $0.name == point.category })
                ?? definitions.first(where: { $0.id == legacyID })
            let item = definition.flatMap { def in
                digest?.categories
                    .first(where: { $0.id == def.id })?
                    .items
                    .first(where: { $0.id == point.itemID })
            }
            return DigestBriefEntry(point: point, definition: definition, item: item)
        }
    }

    var filteredBriefEntries: [DigestBriefEntry] {
        let entries = briefEntries
        if overviewPulseFilter == "all" {
            return entries
        }
        return entries.filter { entry in
            let cid = entry.definition?.id ?? entry.point.categoryID ?? ""
            switch overviewPulseFilter {
            case "global":
                return ["wire", "economy"].contains(cid)
            case "tech":
                return ["ai", "infogap", "opensource"].contains(cid)
            case "policy":
                return cid == "policy"
            default:
                return true
            }
        }
    }

    var opportunities: [DigestOpportunity] {
        Array((brief?.opportunities ?? []).prefix(3))
    }

    func opportunityEntry(_ opportunity: DigestOpportunity) -> DigestBriefEntry? {
        guard let itemID = opportunity.itemID, !itemID.isEmpty else { return nil }
        for group in categoryGroups {
            if let item = group.items.first(where: { $0.id == itemID }) {
                return DigestBriefEntry(
                    point: DigestBriefPoint(
                        category: group.definition.name,
                        categoryID: group.definition.id,
                        itemID: item.id,
                        text: opportunity.why ?? item.takeaway
                    ),
                    definition: group.definition,
                    item: item
                )
            }
        }
        return nil
    }

    var topEntries: [DigestBriefEntry] {
        let fromBrief = Array(briefEntries.filter { $0.item != nil }.prefix(6))
        if fromBrief.count >= 3 {
            return fromBrief
        }
        let ranked = categoryGroups
            .filter { $0.definition.id != "tokens" }
            .flatMap { group in group.items.map { (group, $0) } }
            .sorted { ($0.1.score ?? 0) > ($1.1.score ?? 0) }
            .prefix(6)
        return ranked.map { pair in
            DigestBriefEntry(
                point: DigestBriefPoint(
                    category: pair.0.definition.name,
                    categoryID: pair.0.definition.id,
                    itemID: pair.1.id,
                    text: pair.1.takeaway
                ),
                definition: pair.0.definition,
                item: pair.1
            )
        }
    }

    // MARK: - 一周

    var weeklyItems: [WeeklyItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [WeeklyItem] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dateString(for: date)
            guard availableDateStrings.contains(key) else { continue }
            let url = dataDirectory.appendingPathComponent("\(key).json")
            guard let loaded = decodeDigest(at: url) else { continue }
            for category in loaded.categories {
                guard let definition = definitions.first(where: { $0.id == category.id }) else { continue }
                for item in visibleItems(in: category, on: loaded.date) {
                    result.append(
                        WeeklyItem(
                            date: key,
                            definition: definition,
                            item: item,
                            isFavorite: isFavorite(item, categoryID: category.id, date: key)
                        )
                    )
                }
            }
        }
        return result
    }

    var weeklyGroups: [WeeklyGroup] {
        let all = weeklyItems
        var groups: [WeeklyGroup] = []
        for definition in definitions {
            let items = all.filter { $0.definition.id == definition.id }
            guard !items.isEmpty else { continue }

            var picked = items.filter(\.isFavorite)
            var seen = Set(picked.map(\.id))

            let byDate = Dictionary(grouping: items.filter { !seen.contains($0.id) }, by: \.date)
                .sorted { $0.key > $1.key }
            var round = 0
            while picked.count < 6 {
                var added = false
                for (_, dayItems) in byDate {
                    let sorted = dayItems.sorted { ($0.item.score ?? 0) > ($1.item.score ?? 0) }
                    if round < sorted.count {
                        let entry = sorted[round]
                        if seen.insert(entry.id).inserted {
                            picked.append(entry)
                        }
                        added = true
                    }
                    if picked.count >= 6 { break }
                }
                if !added { break }
                round += 1
            }
            groups.append(WeeklyGroup(definition: definition, items: Array(picked.prefix(6))))
        }
        return groups
    }

    var weeklyDayCount: Int {
        Set(weeklyItems.map(\.date)).count
    }

    var weeklyPeriodTitle: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: start)) – \(formatter.string(from: today))"
    }

    func openWeeklyItem(_ entry: WeeklyItem) {
        if let date = isoDayFormatter.date(from: entry.date) {
            followsLatest = entry.date == todayString
            selectedDate = Calendar.current.startOfDay(for: date)
            load(dateString: entry.date)
        }
        searchText = ""
        selectedCategoryID = entry.definition.id
        pendingItemID = entry.item.id
    }

    // MARK: - 天气

    // MARK: - 配置读写（前后端共用 config.json）

    func loadConfig() {
        let url = baseRoot.appendingPathComponent("config.json")
        let raw: [String: Any]
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            raw = object
        } else {
            raw = [:]
        }
        let modules = raw["modules"] as? [String: Any] ?? [:]
        let broadcast = raw["broadcast"] as? [String: Any] ?? [:]
        let appearance = raw["appearance"] as? [String: Any] ?? [:]
        let weather = raw["weather"] as? [String: Any] ?? [:]

        var catalog: [ModuleEntry] = []
        if let list = modules["catalog"] as? [[String: Any]] {
            for entry in list {
                guard let id = entry["id"] as? String,
                      let name = entry["name"] as? String else { continue }
                catalog.append(ModuleEntry(
                    id: id, name: name,
                    icon: entry["icon"] as? String ?? "circle",
                    colorHex: entry["color"] as? String ?? "#666666",
                    group: entry["group"] as? String ?? "其他",
                    broadcastDefault: entry["broadcast"] as? Bool ?? false))
            }
        }
        // 「限时赠送 / 免费模型汇总」已整体下线，不再自动补进栏目表。
        moduleCatalog = catalog.isEmpty ? DigestStore.fallbackCatalog : catalog
        let valid = Set(moduleCatalog.map(\.id))

        let configuredEnabled = (modules["enabled"] as? [String])?.filter { valid.contains($0) }
        enabledModuleIDs = configuredEnabled ?? DigestStore.defaultEnabled.filter { valid.contains($0) }
        let configuredBroadcast = (broadcast["modules"] as? [String])?.filter { valid.contains($0) }
        broadcastModuleIDs = configuredBroadcast ?? DigestStore.defaultBroadcast.filter { valid.contains($0) }

        broadcastMaxItems = broadcast["max_items_per_module"] as? Int ?? 3
        includeWeatherInBroadcast = broadcast["include_weather"] as? Bool ?? true
        includeHotTopicsInBroadcast = broadcast["include_hot_topics"] as? Bool ?? true
        includeSportsInBroadcast = broadcast["include_sports"] as? Bool ?? false

        showHotlists = modules["show_hotlists"] as? Bool ?? true
        showSportsBoard = modules["show_sports"] as? Bool ?? true
        showTopic = modules["show_topic"] as? Bool ?? true
        showOpportunities = modules["show_opportunities"] as? Bool ?? false

        weatherEnabled = weather["enabled"] as? Bool ?? true
        weatherCity = weather["city"] as? String ?? raw["city"] as? String ?? "杭州富阳"
        weatherLatitude = weather["latitude"] as? Double ?? raw["latitude"] as? Double ?? 30.05
        weatherLongitude = weather["longitude"] as? Double ?? raw["longitude"] as? Double ?? 119.95
        if let skinID = appearance["skin"] as? String,
           PlanetSkin(rawValue: skinID) != nil {
            skin = skinID
        }
    }

    func saveConfig() {
        let url = baseRoot.appendingPathComponent("config.json")
        var raw: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            raw = object
        }
        var weather = raw["weather"] as? [String: Any] ?? [:]
        weather["enabled"] = weatherEnabled
        weather["city"] = weatherCity
        weather["latitude"] = weatherLatitude
        weather["longitude"] = weatherLongitude
        raw["weather"] = weather
        // 顶层字段保留，兼容后端旧读取路径
        raw["city"] = weatherCity
        raw["latitude"] = weatherLatitude
        raw["longitude"] = weatherLongitude

        var appearance = raw["appearance"] as? [String: Any] ?? [:]
        appearance["skin"] = skin
        appearance["mode"] = appearanceMode
        raw["appearance"] = appearance

        var modules = raw["modules"] as? [String: Any] ?? [:]
        modules["enabled"] = enabledModuleIDs
        modules["show_hotlists"] = showHotlists
        modules["show_sports"] = showSportsBoard
        modules["show_topic"] = showTopic
        modules["show_opportunities"] = showOpportunities
        raw["modules"] = modules

        var broadcast = raw["broadcast"] as? [String: Any] ?? [:]
        broadcast["modules"] = broadcastModuleIDs.filter { enabledModuleIDs.contains($0) }
        broadcast["max_items_per_module"] = broadcastMaxItems
        broadcast["include_weather"] = includeWeatherInBroadcast
        broadcast["include_hot_topics"] = includeHotTopicsInBroadcast
        broadcast["include_sports"] = includeSportsInBroadcast
        raw["broadcast"] = broadcast

        guard let data = try? JSONSerialization.data(
            withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try data.write(to: url, options: .atomic)
            statusMessage = "设置已保存，下次生成日报时生效"
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    func toggleModule(_ id: String) {
        if let index = enabledModuleIDs.firstIndex(of: id) {
            enabledModuleIDs.remove(at: index)
            broadcastModuleIDs.removeAll { $0 == id }
        } else {
            enabledModuleIDs.append(id)
        }
        if selectedCategoryID == id && !enabledModuleIDs.contains(id) {
            selectedCategoryID = DigestStore.overviewID
        }
    }

    func toggleBroadcastModule(_ id: String) {
        guard enabledModuleIDs.contains(id) else { return }
        if let index = broadcastModuleIDs.firstIndex(of: id) {
            broadcastModuleIDs.remove(at: index)
        } else {
            broadcastModuleIDs.append(id)
        }
    }

    func loadWeather() {
        guard weatherEnabled else {
            weatherDays = []
            weatherFailed = false
            return
        }
        guard !weatherLoading else { return }
        let config = weatherConfig()
        weatherCity = config.city
        weatherLoading = true
        weatherFailed = false

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(config.latitude)),
            URLQueryItem(name: "longitude", value: String(config.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else {
            weatherLoading = false
            weatherFailed = true
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.weatherLoading = false
                guard let data,
                      let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else {
                    self.weatherFailed = true
                    return
                }
                let daily = response.daily
                let count = min(daily.temperature2mMax.count, daily.temperature2mMin.count, daily.weatherCode.count)
                var days: [WeatherDay] = []
                for index in 0..<min(daily.time.count, count) {
                    days.append(
                        WeatherDay(
                            date: daily.time[index],
                            maxTemp: daily.temperature2mMax[index],
                            minTemp: daily.temperature2mMin[index],
                            weatherCode: daily.weatherCode[index]
                        )
                    )
                }
                self.weatherDays = days
                self.weatherFailed = days.isEmpty
            }
        }.resume()
    }

    private func weatherConfig() -> WeatherConfig {
        // 直接读当前设置，用户改完城市无需重启即可刷新
        WeatherConfig(city: weatherCity, latitude: weatherLatitude, longitude: weatherLongitude)
    }

    private var fallbackTopic: DigestTopic? {
        let all: [(group: DigestItemGroup, item: DigestItem)] = categoryGroups.flatMap { group in
            group.items.map { (group: group, item: $0) }
        }
        guard !all.isEmpty else { return nil }

        var tagCounts: [String: Int] = [:]
        for pair in all {
            for tag in pair.item.tags ?? [] {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                tagCounts[trimmed, default: 0] += 1
            }
        }

        let topTag = tagCounts
            .filter { $0.value >= 2 }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .first?.key

        let selected: [(group: DigestItemGroup, item: DigestItem)]
        let title: String
        let summary: String

        if let topTag {
            let related = all.filter { ($0.item.tags ?? []).contains(topTag) }
            selected = related.count >= 3 ? related : all
            title = "跨栏目联动：\(String(topTag.prefix(16))) 的多维脉络"
            summary = "今天有 \(related.count) 条内容都提到「\(topTag)」。下面把相关事实和判断放在一起，方便快速建立上下文。"
        } else {
            selected = all
            title = "跨栏目联动：值得连起来看的三条线索"
            summary = "今天从 \(categoryGroups.filter { !$0.items.isEmpty }.count) 个栏目中选出 \(all.count) 条内容，下面把最值得连着看的部分放在一起。"
        }

        let points = selected.prefix(3).map {
            "\($0.group.definition.name)：\($0.item.takeaway)"
        }
        guard !points.isEmpty else { return nil }

        return DigestTopic(
            title: title,
            summary: summary,
            points: Array(points),
            tags: topTag.map { [$0] },
            itemIDs: selected.prefix(5).map { $0.item.id }
        )
    }

    var filteredItems: [DigestItem] {
        filter(items)
    }

    var searchResultCount: Int {
        archiveResults.count
    }

    var archiveResultDayCount: Int {
        Set(archiveResults.map(\.date)).count
    }

    /// 早上打开 App 还没有今天的日报时，自动在后台补生成一次（每天最多触发一次）。
    private func scheduleAutoGenerateIfNeeded() {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (6...23).contains(hour), digest?.date != todayString else { return }
        let flagKey = "dailydigest.autogenerate.date"
        guard UserDefaults.standard.string(forKey: flagKey) != todayString else { return }
        UserDefaults.standard.set(todayString, forKey: flagKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.digest?.date != self.todayString, !self.isGenerating else { return }
            self.generateNow()
        }
    }

    /// 归档全文搜索：防抖后扫描本地所有日期。
    private func scheduleArchiveSearch() {
        archiveSearchWork?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            archiveResults = []
            isArchiveSearching = false
            return
        }
        isArchiveSearching = true
        let work = DispatchWorkItem { [weak self] in
            self?.runArchiveSearch(query: query)
        }
        archiveSearchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func runArchiveSearch(query: String) {
        var hits: [ArchiveSearchHit] = []
        for date in availableDateStrings.sorted(by: >) {
            guard let digest = cachedDigest(for: date) else { continue }
            for category in digest.categories {
                guard let definition = definitions.first(where: { $0.id == category.id }) else { continue }
                for item in filter(visibleItems(in: category, on: date), query: query) {
                    hits.append(ArchiveSearchHit(date: date, definition: definition, item: item))
                }
            }
        }
        archiveResults = hits
        isArchiveSearching = false
    }

    private func cachedDigest(for date: String) -> Digest? {
        if let cached = archiveCache[date] { return cached }
        guard let decoded = decodeDigest(at: dataDirectory.appendingPathComponent("\(date).json")) else { return nil }
        if archiveCache.count > 120 { archiveCache.removeAll() }
        archiveCache[date] = decoded
        return decoded
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var categoryBrief: String {
        if selectedCategoryID == "tokens" {
            if !isToday { return "历史活动归档，反映当日核验规则，不代表现在仍可领取。" }
            if items.isEmpty { return "当前没有在有效期内且近24小时核验通过的词元赠送活动；下次更新会自动重新核验，不沿用旧权益。" }
        }
        return selectedCategory?.brief ?? ""
    }

    var overviewReadingMinutes: Int {
        let briefCount = (brief?.summary.count ?? 0) + briefEntries.reduce(0) { $0 + $1.point.text.count }
        let opportunityCount = opportunities.reduce(0) { $0 + ($1.why?.count ?? 0) + ($1.how?.count ?? 0) }
        var hotCount = 0
        if deepStories.isEmpty {
            for entry in topEntries.prefix(5) {
                hotCount += entry.item?.title.count ?? 0
                hotCount += entry.item?.summary.count ?? 0
            }
        } else {
            for story in deepStories.prefix(5) {
                hotCount += story.title.count
                hotCount += story.lead.count
            }
        }
        return max(1, Int(ceil(Double(briefCount + opportunityCount + hotCount) / 360.0)))
    }

    var selectedReadingMinutes: Int {
        readingMinutes(for: items)
    }

    func readingMinutes(for items: [DigestItem]) -> Int {
        let characters = items.reduce(0) { partial, item in
            partial + item.title.count + item.summary.count
                + item.takeaway.count + item.interpretation.count
        }
        return max(1, Int(ceil(Double(characters) / 420.0)))
    }

    private func filter(_ items: [DigestItem], query rawQuery: String? = nil) -> [DigestItem] {
        let query = (rawQuery ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            let searchable = [
                item.title,
                item.originalTitle ?? "",
                item.source,
                item.summary,
                item.takeaway,
                item.interpretation,
                item.perspective ?? "",
                (item.tags ?? []).joined(separator: " "),
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    var totalCount: Int {
        digest?.categories.reduce(0) { $0 + $1.items.count } ?? 0
    }

    func count(for categoryID: String) -> Int {
        digest?.categories.first(where: { $0.id == categoryID })?.items.count ?? 0
    }

    var dateString: String {
        isoDayFormatter.string(from: selectedDate)
    }

    func dateString(for date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    var todayString: String {
        isoDayFormatter.string(from: Calendar.current.startOfDay(for: Date()))
    }

    var isToday: Bool {
        dateString == todayString
    }

    var canGoNext: Bool {
        selectedDate < Calendar.current.startOfDay(for: Date())
    }

    var dateTitle: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: selectedDate)
        let currentYear = calendar.component(.year, from: Date())
        if year == currentYear {
            return chineseTitleFormatter.string(from: selectedDate)
        }
        return chineseTitleWithYearFormatter.string(from: selectedDate)
    }

    /// 刊头用：日期与星期分开放置，便于宋体大字排版。
    var mastheadDate: String {
        mastheadDateFormatter.string(from: selectedDate)
    }

    var mastheadWeekday: String {
        mastheadWeekdayFormatter.string(from: selectedDate)
    }

    var dateSubtitle: String {
        if isGenerating {
            return "正在抓取国内外信源并生成多维解读…"
        }
        guard let digest else {
            return "这一天还没有日报"
        }
        guard let generated = parseISO8601(digest.generatedAt) else {
            return "共 \(totalCount) 条全球动态"
        }
        return "更新于 \(timeFormatter.string(from: generated)) · 共 \(totalCount) 条"
    }

    var generatedTimeText: String? {
        guard let digest,
              let generated = parseISO8601(digest.generatedAt) else {
            return nil
        }
        return "更新于 \(timeFormatter.string(from: generated))"
    }

    var disclaimer: String? {
        switch selectedCategoryID {
        case "economy":
            return "以下内容仅为公开信息整理与编辑解读，不构成投资建议。市场有风险，决策请独立判断。"
        case "health":
            return "以下内容仅为健康信息摘要与编辑解读，不构成医疗建议。不要据此自行停药或改变治疗方案；如有不适，请咨询专业医生。"
        case "policy":
            return "以下内容仅为公开政策信息梳理与编辑解读，不构成官方解读。具体执行口径、适用范围和申报条件，请以官方原文及主管部门答复为准。"
        default:
            return nil
        }
    }

    // MARK: - Loading

    func loadInitial() {
        followsLatest = true
        let latestURL = dataDirectory.appendingPathComponent("latest.json")
        if let latestDigest = decodeDigest(at: latestURL) {
            apply(latestDigest)
            loadedFileModification = fileModificationDate(of: latestURL)
            refreshAvailableDates()
            return
        }
        if let newest = newestDataFileName() {
            let newestURL = dataDirectory.appendingPathComponent("\(newest).json")
            if let newestDigest = decodeDigest(at: newestURL) {
                apply(newestDigest)
                loadedFileModification = fileModificationDate(of: newestURL)
                refreshAvailableDates()
                return
            }
        }
        digest = nil
        refreshAvailableDates()
    }

    func reload() {
        if followsLatest {
            loadedFileModification = nil
            refreshOnActivate()
        } else {
            load(dateString: dateString)
        }
    }

    func load(dateString: String) {
        isLoading = true
        defer { isLoading = false }

        let url = dataDirectory.appendingPathComponent("\(dateString).json")
        if let loaded = decodeDigest(at: url) {
            apply(loaded)
            loadedFileModification = fileModificationDate(of: url)
            errorMessage = nil
            statusMessage = nil
        } else {
            digest = nil
            loadedFileModification = nil
            errorMessage = "这一天还没有日报。点右上角“立即更新”生成今天的版本。"
        }
        refreshAvailableDates()
    }

    func selectDate(_ date: Date) {
        followsLatest = dateString(for: date) == todayString
        selectedDate = Calendar.current.startOfDay(for: date)
        if isFavorites {
            selectedCategoryID = DigestStore.overviewID
        }
        searchText = ""
        pendingItemID = nil
        load(dateString: dateString)
    }

    func refreshAvailableDates() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: dataDirectory,
            includingPropertiesForKeys: nil
        ) else {
            availableDateStrings = []
            return
        }

        var dates = Set<String>()
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            if isoDayFormatter.date(from: name) != nil {
                dates.insert(name)
            }
        }
        availableDateStrings = dates
    }

    func previousDay() {
        followsLatest = false
        guard let date = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = Calendar.current.startOfDay(for: date)
        load(dateString: dateString)
    }

    func nextDay() {
        guard canGoNext,
              let date = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        followsLatest = dateString(for: date) == todayString
        selectedDate = Calendar.current.startOfDay(for: date)
        load(dateString: dateString)
    }

    func goToday() {
        followsLatest = true
        selectedDate = Calendar.current.startOfDay(for: Date())
        load(dateString: dateString)
    }

    func refreshOnActivate() {
        // Date 本身不发布变更，跨天后也要刷新日期按钮和归档日历。
        objectWillChange.send()
        refreshAvailableDates()
        guard !isGenerating, followsLatest else { return }
        let todayURL = dataDirectory.appendingPathComponent("\(todayString).json")
        let latestURL = dataDirectory.appendingPathComponent("latest.json")
        for url in [todayURL, latestURL] {
            guard let modification = fileModificationDate(of: url),
                  let candidate = decodeDigest(at: url),
                  isoDayFormatter.date(from: candidate.date) != nil,
                  candidate.date <= todayString else { continue }
            if digest?.date != candidate.date || loadedFileModification != modification {
                apply(candidate)
                loadedFileModification = modification
                errorMessage = nil
                statusMessage = nil
            }
            return
        }
    }

    // MARK: - Generation

    func generateNow() {
        guard !isGenerating else { return }
        followsLatest = true
        guard fileManager.isExecutableFile(atPath: backendScript.path) else {
            errorMessage = "找不到生成脚本：\(backendScript.path)"
            return
        }

        isGenerating = true
        errorMessage = nil
        statusMessage = "正在抓取全球与国内信源，生成 24h 深度早报与语音，通常需要 2–4 分钟…"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [backendScript.path]

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LANG"] = "zh_CN.UTF-8"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isGenerating = false
                if finished.terminationStatus == 0 {
                    let today = self.todayString
                    self.selectedDate = Calendar.current.startOfDay(for: Date())
                    self.load(dateString: today)
                    if self.digest == nil {
                        self.loadInitial()
                    }
                    if self.digest != nil {
                        self.statusMessage = "更新完成，已同步今日 24 小时全球早报（共 \(self.totalCount) 条）。"
                        self.errorMessage = nil
                    } else {
                        self.errorMessage = "生成进程已结束，但没有读到今天的数据。请查看日志。"
                    }
                } else {
                    self.errorMessage = "生成失败（退出码 \(finished.terminationStatus)）。请查看 logs 目录中的日志。"
                }
            }
        }

        do {
            try process.run()
            generationProcess = process
        } catch {
            isGenerating = false
            errorMessage = "无法启动生成脚本：\(error.localizedDescription)"
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(dataDirectory)
    }

    func openLogFolder() {
        let logs = baseRoot.appendingPathComponent("logs", isDirectory: true)
        NSWorkspace.shared.open(logs)
    }

    // MARK: - 收藏与专题

    var favoritesPath: URL {
        baseRoot.appendingPathComponent("favorites.json")
    }

    func isFavorite(_ item: DigestItem, categoryID: String, date: String) -> Bool {
        let key = favoriteKey(item: item, categoryID: categoryID, date: date)
        return favorites.contains(where: { $0.key == key })
    }

    func toggleFavorite(_ item: DigestItem, categoryID: String, date: String) {
        let key = favoriteKey(item: item, categoryID: categoryID, date: date)
        if let index = favorites.firstIndex(where: { $0.key == key }) {
            favorites.remove(at: index)
        } else {
            favorites.append(
                FavoriteEntry(
                    key: key,
                    date: date,
                    categoryID: categoryID,
                    savedAt: favoriteTimestampFormatter.string(from: Date()),
                    item: item
                )
            )
            favorites.sort { $0.savedAt > $1.savedAt }
        }
        saveFavorites()
    }

    func removeFavorite(_ entry: FavoriteEntry) {
        favorites.removeAll { $0.key == entry.key }
        saveFavorites()
    }

    func openItem(itemID: String, categoryID: String, date: String? = nil) {
        guard !categoryID.isEmpty else { return }
        searchText = ""
        if let date, let day = isoDayFormatter.date(from: date) {
            followsLatest = date == todayString
            selectedDate = Calendar.current.startOfDay(for: day)
            load(dateString: date)
        }
        selectedCategoryID = categoryID
        pendingItemID = itemID
    }

    func openFavorite(_ entry: FavoriteEntry) {
        if let date = isoDayFormatter.date(from: entry.date) {
            followsLatest = entry.date == todayString
            selectedDate = Calendar.current.startOfDay(for: date)
            load(dateString: entry.date)
        }
        searchText = ""
        selectedCategoryID = entry.categoryID
        pendingItemID = entry.item.id
    }

    private func favoriteKey(item: DigestItem, categoryID: String, date: String) -> String {
        "\(date)|\(categoryID)|\(item.id)"
    }

    private func loadFavorites() {
        guard let data = try? Data(contentsOf: favoritesPath),
              let decoded = try? JSONDecoder().decode([FavoriteEntry].self, from: data) else {
            favorites = []
            return
        }
        favorites = decoded.sorted { $0.savedAt > $1.savedAt }
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? fileManager.createDirectory(
            at: favoritesPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: favoritesPath, options: .atomic)
    }

    // MARK: - Helpers

    private func decodeDigest(at url: URL) -> Digest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Digest.self, from: data)
    }

    private func fileModificationDate(of url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private func apply(_ loaded: Digest) {
        digest = loaded
        if let date = isoDayFormatter.date(from: loaded.date) {
            selectedDate = Calendar.current.startOfDay(for: date)
        }
        if !isOverview, !isFavorites, !isWeek, !isHotboard,
           !loaded.categories.contains(where: { $0.id == selectedCategoryID }),
           let first = loaded.categories.first {
            selectedCategoryID = first.id
        }
    }

    private func newestDataFileName() -> String? {
        guard let files = try? fileManager.contentsOfDirectory(
            at: dataDirectory,
            includingPropertiesForKeys: nil
        ) else { return nil }

        let pattern = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
        let names = files.compactMap { url -> String? in
            let name = url.deletingPathExtension().lastPathComponent
            let range = NSRange(location: 0, length: name.utf16.count)
            return pattern.firstMatch(in: name, range: range) != nil ? name : nil
        }
        return names.sorted().last
    }

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
