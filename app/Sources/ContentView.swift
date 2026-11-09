import AppKit
import Combine
import SwiftUI

final class HoverModel: ObservableObject {
    @Published var isOn: Bool = false
}

final class VoicePopoverModel: ObservableObject {
    @Published var isShowing = false
}

final class SchedulePopoverModel: ObservableObject {
    @Published var isShowing = false
    @Published var enabled = false
    @Published var hour = 9
    @Published var minute = 10
    @Published var error: String?

    func prepare(from player: TTSPlayer) {
        let parts = player.autoPlayTime.split(separator: ":")
        hour = parts.count == 2 ? Int(parts[0]) ?? 9 : 9
        minute = parts.count == 2 ? Int(parts[1]) ?? 10 : 10
        enabled = player.autoPlayEnabled
        error = nil
        isShowing = true
    }
}

final class CalendarPopoverModel: ObservableObject {
    @Published var isShowing: Bool = false
    @Published var displayedMonth: Date = Date()
}

final class MastheadModel: ObservableObject {
    @Published var isSearchFieldShown = false
}

/// 速览页顶部分段控件：简报 | 热榜 | 天气 | 一周，默认停在「简报」。
final class OverviewSegmentModel: ObservableObject {
    @Published var selection = "brief"
}

/// 「原文」Popover 开关。
final class OriginalPopoverModel: ObservableObject {
    @Published var isShowing = false
}

// MARK: - 英文兜底（全中文第一：标题不含中文时 12px 灰斜体 + 「未翻译」角标，永不加粗）

extension String {
    /// 标题是否含中文（翻译失败兜底判定，与两轮规范一致的正则）。
    var containsChinese: Bool {
        range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil
    }

    /// 机会/线索标题的机器前缀（本地兜底路径加的），判定语言前先剥离。
    private var strippedMachinePrefix: String {
        var text = self
        for prefix in ["待验证线索：", "跟进线索：", "待验证线索:", "跟进线索:", "机会信号："] {
            while text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
            }
        }
        return text
    }

    /// 标题是否可按中文正常展示：剥离机器前缀后再判中文，避免「待验证线索：DoorDash…」被误判。
    ///
    /// 防护「非前缀型中英混排」：中文只剩零星几个字、却带 ≥2 个英文功能词的（英文句子主体），
    /// 仍按英文兜底渲染；「DiffuSpace 开源 Clover-35B…」这类中文标题带英文专名的不受影响（专名豁免）。
    var isChineseTitle: Bool {
        let text = strippedMachinePrefix
        guard text.containsChinese else { return false }
        let chineseCount = text.unicodeScalars
            .filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            .count
        guard chineseCount <= 2 else { return true }
        let words = Set(
            text.lowercased()
                .components(separatedBy: CharacterSet(charactersIn: " \n\t,.:;!?()[]\"'—-"))
                .filter { !$0.isEmpty }
        )
        let englishSentenceWords: Set<String> = [
            "the", "a", "an", "of", "to", "and", "said", "will", "is", "are", "was", "were",
            "it", "its", "has", "have", "had", "in", "on", "for", "with", "that", "after",
            "as", "at", "by", "from", "but", "not", "over", "amid", "into", "about",
        ]
        return words.intersection(englishSentenceWords).count < 2
    }

    /// 正文是否嵌入未翻译英文句子（≥2 个独立英文功能词）。
    /// 机会信号 why/how 由本地流水线生成，可能把英文原句直接拼进中文正文
    /// （如「DoorDash said that it is open to…。这是一条待验证的需求线索」），
    /// 数据内容 UI 无法折叠，只能按第二轮规范标注无法翻译。
    var containsUntranslatedEnglish: Bool {
        let words = Set(
            lowercased()
                .components(separatedBy: CharacterSet(charactersIn: " \n\t,.:;!?()[]\"'—-、。；：！？（）《》「」·…"))
                .filter { !$0.isEmpty }
        )
        let englishSentenceWords: Set<String> = [
            "the", "a", "an", "of", "to", "and", "said", "will", "is", "are", "was", "were",
            "it", "its", "has", "have", "had", "in", "on", "for", "with", "that", "after",
            "as", "at", "by", "from", "but", "not", "over", "amid", "into", "about",
        ]
        return words.intersection(englishSentenceWords).count >= 2
    }
}

/// 条目标题字号：中文按栏目样式渲染；英文兜底一律 12px regular（永不大于 12px、永不加粗）。
private func entryTitleFont(hasChinese: Bool, chineseWeight: Font.Weight = .medium) -> Font {
    .system(size: hasChinese ? 15 : 12, weight: hasChinese ? chineseWeight : .regular)
}

/// 「未翻译」角标（默认用于标题；正文嵌英文时用 label 区分）。
struct UntranslatedBadge: View {
    var label: String = "未翻译"
    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(PlanetTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(PlanetTheme.rule, lineWidth: 0.5))
            .fixedSize()
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(store)
        } detail: {
            DetailView()
                .environmentObject(store)
        }
        .navigationSplitViewStyle(.balanced)
        // accent 纪律：B7503A 仅用于侧栏指示条 / 电台卡播放键 / 简报序号，全局控件统一墨色
        .tint(PlanetTheme.ink)
        .foregroundStyle(PlanetTheme.ink)
        .frame(minWidth: 1_040, minHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshOnActivate()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            store.refreshOnActivate()
        }
    }
}

// MARK: - 侧栏（速览 / 环球 / 政策 / 洞见 / 生活 / 一周）

struct SidebarView: View {
    @EnvironmentObject private var store: DigestStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var settingsPresentation = SettingsPresentation()

    private var sidebarBackground: Color {
        PlanetTheme.sidebar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            settingsStrip
            HairlineDivider()
                .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(store.sidebarGroups.enumerated()), id: \.offset) { index, group in
                        Text(group.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(PlanetTheme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, index == 0 ? 10 : 16)
                            .padding(.bottom, 6)

                        ForEach(group.definitions) { definition in
                            sidebarButton(
                                definition,
                                // 侧栏降噪：不再挂任何数字徽标，让层级只靠分组与选中态表达
                                count: nil,
                                isSelected: isSelected(definition)
                            ) {
                                select(definition)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 8)

            HairlineDivider()
                .padding(.horizontal, 16)

            sidebarButton(
                store.weekDefinition,
                count: nil,
                isSelected: store.isWeek && !store.isSearching
            ) {
                select(store.weekDefinition)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HairlineDivider()
                .padding(.horizontal, 16)

            footer
        }
        .background(sidebarBackground)
        .navigationSplitViewColumnWidth(min: 216, ideal: 228, max: 250)
        .sheet(isPresented: $settingsPresentation.showing) {
            SettingsView()
                .environmentObject(store)
        }
        .onAppear {
            // 调试/快捷入口：open -a 行星日报 --args --open-settings
            if CommandLine.arguments.contains("--open-settings") {
                settingsPresentation.showing = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DailyDigestOpenSettings"))) { _ in
            // 报头右侧「外观与设置」按钮走通知，避免在主内容区重复挂 sheet
            settingsPresentation.showing = true
        }
    }

    /// 侧栏顶部常驻的偏好设置入口 + 皮肤快捷切换，打开 App 第一眼就能看到。
    private var settingsStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                settingsPresentation.showing = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PlanetTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(
                            PlanetTheme.accent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("偏好设置")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(PlanetTheme.ink)
                        Text("栏目 · 播报 · 外观")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PlanetTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PlanetTheme.muted)
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .refinedCard(cornerRadius: 13)

            Menu {
                ForEach(PlanetSkin.allCases) { skin in
                    Button {
                        store.skin = skin.rawValue
                        store.saveConfig()
                    } label: {
                        HStack {
                            Text(skin.title)
                            if store.skin == skin.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 11, weight: .medium))
                    Text("皮肤：\(PlanetSkin.current.title)")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(PlanetTheme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.7)
                )
            }
            .menuStyle(.borderlessButton)
            .help("立即切换皮肤，无需重启")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func select(_ definition: CategoryDefinition) {
        store.searchText = ""
        store.selectedCategoryID = definition.id
    }

    private func isSelected(_ definition: CategoryDefinition) -> Bool {
        if definition.id == DigestStore.overviewID {
            return store.isOverview || store.isSearching
        }
        if definition.id == DigestStore.hotboardID {
            return !store.isSearching && store.isHotboard
        }
        if definition.id == DigestStore.favoritesID {
            return !store.isSearching && store.isFavorites
        }
        return !store.isSearching && store.selectedCategoryID == definition.id
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMark(size: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text("行星日报")
                    .font(.system(size: 16.5, weight: .bold))
                    .tracking(1.6)
                Text("每天一册 · 读懂今天")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(PlanetTheme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func sidebarButton(
        _ definition: CategoryDefinition,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SidebarRow(definition: definition, count: count, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        if store.isGenerating { return "正在更新日报" }
        if store.errorMessage != nil, store.digest != nil { return "上次更新失败" }
        if store.digest == nil { return "这一天还没有日报" }
        return "数据已同步"
    }

    private var statusColor: Color {
        if store.isGenerating { return .orange }
        if store.errorMessage != nil, store.digest != nil { return .red.opacity(0.8) }
        if store.digest == nil { return .secondary.opacity(0.5) }
        return .green.opacity(0.8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PlanetTheme.secondary)
                Spacer()
            }

            if let digest = store.digest {
                Text("数据日期 \(digest.date)")
                    .font(.system(size: 10))
                    .foregroundStyle(PlanetTheme.muted)
            }

            HStack(spacing: 12) {
                Button {
                    store.openDataFolder()
                } label: {
                    Label("数据", systemImage: "folder")
                }
                .buttonStyle(.borderless)

                Button {
                    store.openLogFolder()
                } label: {
                    Label("日志", systemImage: "doc.text")
                }
                .buttonStyle(.borderless)

                Button {
                    settingsPresentation.showing = true
                } label: {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
            }
            .font(.system(size: 10))
            .foregroundStyle(PlanetTheme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

struct AppMark: View {
    let size: CGFloat
    var body: some View { PlanetBrandMark(size: size) }
}

struct SidebarRow: View {
    let definition: CategoryDefinition
    /// nil 表示不挂数字徽标；只有「今日速览」传具体条数。
    let count: Int?
    let isSelected: Bool
    @StateObject private var hover = HoverModel()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: definition.icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? PlanetTheme.accent : PlanetTheme.secondary)
                .frame(width: 20)

            Text(definition.name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? PlanetTheme.ink : Color.primary)

            Spacer(minLength: 4)

            if let count {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? PlanetTheme.ink : PlanetTheme.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? PlanetTheme.selection
                        : Color.primary.opacity(hover.isOn ? 0.04 : 0)
                )
        )
        // 选中态朱砂侧条，不单靠底色区分
        .background(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(PlanetTheme.accent)
                    .frame(width: 3, height: 17)
                    .offset(x: -9)
            }
        }
        // 动效白名单：侧栏 hover 不做动画，仅瞬时高亮
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hover.isOn = $0 }
    }
}

// MARK: - 主内容

struct DetailView: View {
    @EnvironmentObject private var store: DigestStore
    @Environment(\.colorScheme) private var colorScheme

    private var canvasBackground: Color {
        PlanetTheme.canvas
    }

    var body: some View {
        VStack(spacing: 0) {
            // 速览页顶部合并为报头两行（报头行 + 元信息行，见 MastheadView）；
            // 其余栏目页与搜索结果页仍使用 DetailHeader。
            if store.isSearching || !store.isOverview {
                DetailHeader()
                HairlineDivider()
            }

            if store.isGenerating {
                StatusBanner(
                    icon: "arrow.triangle.2.circlepath",
                    text: store.statusMessage ?? "正在抓取来源并生成解读…",
                    tint: store.selectedDefinition.color,
                    showsProgress: true
                )
            } else if let status = store.statusMessage, store.errorMessage == nil {
                StatusBanner(
                    icon: "checkmark.circle.fill",
                    text: status,
                    tint: .green,
                    showsProgress: false
                )
            }

            if let error = store.errorMessage, store.digest != nil {
                ErrorBanner(text: error)
            }

            Group {
                if store.isSearching {
                    GlobalSearchView()
                } else if store.isOverview {
                    OverviewView()
                } else if store.isHotboard {
                    HotBoardView()
                } else if store.isFavorites {
                    FavoritesView()
                } else if store.isWeek {
                    WeekView()
                } else {
                    CategoryDetailView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            // 纸面右上角的极淡暖光：让纯色画布有呼吸感，不随皮肤变化而突兀
            ZStack {
                canvasBackground
                RadialGradient(
                    colors: [PlanetTheme.accent.opacity(0.075), Color.clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 760
                )
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - 顶部栏

struct DetailHeader: View {
    @EnvironmentObject private var store: DigestStore
    @StateObject private var calendarModel = CalendarPopoverModel()

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                HeaderIconButton(
                    systemImage: "chevron.left",
                    help: "前一天（⌘←）",
                    disabled: store.isGenerating
                ) {
                    store.previousDay()
                }

                HeaderIconButton(
                    systemImage: "chevron.right",
                    help: "后一天（⌘→）",
                    disabled: !store.canGoNext || store.isGenerating
                ) {
                    store.nextDay()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(store.selectedDefinition.name)
                        .font(.system(size: 15, weight: .semibold))

                    Button {
                        calendarModel.isShowing.toggle()
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(calendarModel.isShowing ? store.selectedDefinition.color : .secondary)
                            .frame(width: 22, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(calendarModel.isShowing ? 0.08 : 0.04))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("按日历选择历史日报")
                    .popover(isPresented: $calendarModel.isShowing, arrowEdge: .bottom) {
                        ArchiveCalendarView(model: calendarModel)
                            .environmentObject(store)
                    }

                    if !store.isToday {
                        Button("回到今天") {
                            store.goToday()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .font(.system(size: 10))
                    }
                }

                Text("\(store.dateTitle) · \(store.dateSubtitle)")
                    .font(.system(size: 10))
                    .foregroundStyle(PlanetTheme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            SearchField(
                text: $store.searchText,
                prompt: "搜索全部栏目"
            )
            .frame(width: 210)

            Button {
                store.generateNow()
            } label: {
                HStack(spacing: 8) {
                    if store.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(store.isGenerating ? "更新中…" : "立即更新")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isGenerating)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }
}

struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    var disabled: Bool = false
    let action: () -> Void
    @StateObject private var hover = HoverModel()

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .quaternary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hover.isOn && !disabled ? 0.06 : 0))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .onHover { hover.isOn = $0 }
    }
}

struct ArchiveCalendarView: View {
    @EnvironmentObject private var store: DigestStore
    @ObservedObject var model: CalendarPopoverModel

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        cal.firstWeekday = 2
        return cal
    }()

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(monthFormatter.string(from: model.displayedMonth))
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveNextMonth)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PlanetTheme.muted)
                        .frame(height: 18)
                }

                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(PlanetTheme.ink)
                    .frame(width: 5, height: 5)
                Text("共存档 \(store.availableDateStrings.count) 期")
                    .font(.system(size: 10))
                    .foregroundStyle(PlanetTheme.secondary)
                Spacer()
                if !store.isToday {
                    Button("今天") {
                        store.goToday()
                        model.isShowing = false
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
            }
        }
        .padding(16)
        .frame(width: 256)
        .onAppear {
            model.displayedMonth = store.selectedDate
            store.refreshAvailableDates()
        }
    }

    private var canMoveNextMonth: Bool {
        guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
              let shownMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: model.displayedMonth)) else {
            return false
        }
        return shownMonth < currentMonth
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: model.displayedMonth) {
            model.displayedMonth = next
        }
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: model.displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: model.displayedMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                result.append(date)
            }
        }
        return result
    }

    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let key = store.dateString(for: date)
        let hasDigest = store.availableDateStrings.contains(key)
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())

        return Button {
            store.selectDate(date)
            model.isShowing = false
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(
                        // accent 纪律：日历选中态用墨底纸字（双规则线同款），不再借道栏目色/朱砂
                        isSelected ? PlanetTheme.paper : (isFuture ? Color.secondary.opacity(0.35) : Color.primary)
                    )
                Circle()
                    .fill(isSelected ? PlanetTheme.paper : (hasDigest ? PlanetTheme.ink : .clear))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? PlanetTheme.ink
                            : (hasDigest ? Color.primary.opacity(0.04) : .clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PlanetTheme.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - 卡片修饰器（晨版印刷：纸面 + 单层投影，分隔交给发丝线）

struct DigestCard: ViewModifier {
    var interactive: Bool = true
    func body(content: Content) -> some View {
        // 全局统一走 RefinedLook：纸面高光 + 细描边 + 双层柔和投影 + hover 微抬
        content.modifier(RefinedSurface(interactive: interactive, cornerRadius: 15))
    }
}

extension View {
    func digestCard(interactive: Bool = true) -> some View {
        modifier(DigestCard(interactive: interactive))
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.75)
    }
}

// MARK: - 版块眉标（朱砂 kicker + 英文小标 + 等宽元信息 + 发丝线）

struct SectionHeader<Trailing: View>: View {
    let kicker: String
    var english: String = ""
    var meta: String? = nil
    var trailing: Trailing

    init(
        kicker: String,
        english: String = "",
        meta: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.kicker = kicker
        self.english = english
        self.meta = meta
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                // 眉标：墨色圆角短竖标 + 更大更清晰的中文字号
                Capsule()
                    .fill(PlanetTheme.ink)
                    .frame(width: 3, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                Text(kicker)
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(PlanetTheme.ink)
                Spacer(minLength: 12)
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(PlanetTheme.muted)
                }
                trailing
            }
            // 淡出的发丝线，比整条实线更轻；english 装饰小标不再渲染，保持全中文界面
            GradientRule(strength: 0.30)
        }
    }
}

// MARK: - 热榜共享小组件（印章标签、热度条、榜单行）

struct HotBadge: View {
    let badge: String

    static func color(for badge: String) -> Color {
        // accent 纪律：热搜印章不再用朱砂，统一墨色
        PlanetTheme.ink
    }

    private var isSolid: Bool { ["爆", "沸", "热"].contains(badge) }

    var body: some View {
        let color = Self.color(for: badge)
        Text(badge)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSolid ? Color.white : color)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(isSolid ? color : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(isSolid ? Color.clear : color.opacity(0.7), lineWidth: 0.8)
            )
            .fixedSize()
    }
}

struct HeatBar: View {
    let fraction: Double?

    var body: some View {
        if let fraction {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10)).frame(width: 44, height: 3)
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: max(4, 44 * min(max(fraction, 0), 1)), height: 3)
            }
        }
    }
}

struct HotRankRow: View {
    let index: Int
    let entry: HotListEntry
    let heatFraction: Double?
    var twoLineTitle: Bool = false
    @StateObject private var hover = HoverModel()

    private var rankColor: Color {
        switch index {
        case 1: return PlanetTheme.ink
        case 2, 3: return PlanetTheme.secondary
        default: return PlanetTheme.muted
        }
    }

    var body: some View {
        Button {
            if let url = URL(string: entry.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(rankColor)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 28, alignment: .trailing)

                if let badge = entry.badge {
                    HotBadge(badge: badge)
                }

                Text(entry.title)
                    .font(entryTitleFont(hasChinese: entry.title.isChineseTitle, chineseWeight: .semibold))
                    .italic(!entry.title.isChineseTitle)
                    .foregroundStyle(entry.title.isChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                    .lineLimit(twoLineTitle ? 2 : 1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !entry.title.isChineseTitle {
                    UntranslatedBadge()
                }

                if let trend = HotListEntry.trend(currentRank: index, prevRank: entry.prevRank) {
                    Text(trend.symbol)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(
                            trend.isFlat ? PlanetTheme.muted
                                : (trend.isUp ? PlanetTheme.ink : PlanetTheme.secondary)
                        )
                        .fixedSize()
                }

                if let heat = entry.heat, !heat.isEmpty {
                    HStack(spacing: 8) {
                        HeatBar(fraction: heatFraction)
                        Text(heat)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(PlanetTheme.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PlanetTheme.muted)
                    .opacity(hover.isOn ? 0.9 : 0.3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hover.isOn ? 0.04 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .help(entry.title)
        .accessibilityLabel("第\(index)名，\(entry.title)，\(entry.heat ?? "")")
    }
}

// MARK: - 速览页（单列主文流：报头 → 电台卡 → 分段控件[简报|热榜|天气|一周] → 版块内容）

struct OverviewView: View {
    @EnvironmentObject private var store: DigestStore
    @StateObject private var segment = OverviewSegmentModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if store.digest == nil {
                    EmptyDigestView()
                } else {
                    // 报头三行：大日期/星期/天气 + 期数/条数/更新时间 + 今日提要
                    MastheadView()

                    // 电台卡（深蓝重色块，各版块常驻）
                    TTSBar(player: store.tts, date: store.dateString)
                        .id("tts-\(store.dateString)-\(store.appearanceMode)")

                    // 今日栏目卡片墙：勾选的模块（含游戏资讯）在首页直接露出，
                    // 不再只藏在侧栏分组里；顺序跟随偏好设置里的启用顺序。
                    ModulesBoard()

                    // 顶部分段控件：热榜/天气/一周收纳为次级页签，默认停在「简报」
                    segmentPicker

                    segmentContent
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if store.weatherDays.isEmpty {
                store.loadWeather()
            }
            store.tts.load(
                date: store.dateString,
                generation: store.digest?.generatedAt ?? ""
            )
        }
        .onChange(of: store.dateString) { _, _ in
            store.tts.load(
                date: store.dateString,
                generation: store.digest?.generatedAt ?? ""
            )
        }
        .onChange(of: store.digest?.generatedAt) { _, _ in
            store.tts.reloadIfNeeded(
                date: store.dateString,
                generation: store.digest?.generatedAt ?? ""
            )
        }
        .id("overview-\(store.dateString)")
    }

    private var segmentPicker: some View {
        Picker("版块", selection: $segment.selection) {
            Text("简报").tag("brief")
            if store.showHotlists { Text("热榜").tag("hotboard") }
            if store.showSportsBoard { Text("赛事").tag("sports") }
            if store.weatherEnabled { Text("天气").tag("weather") }
            Text("一周").tag("week")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch segment.selection {
        case "hotboard" where store.showHotlists: hotboardSegment.transition(segmentFade)
        case "sports" where store.showSportsBoard: sportsSegment.transition(segmentFade)
        case "weather" where store.weatherEnabled: weatherSegment.transition(segmentFade)
        case "week": weekSegment.transition(segmentFade)
        default: briefFlow.transition(segmentFade)
        }
    }

    /// 动效白名单之三：切页淡入，0.2s ease-out。
    private var segmentFade: AnyTransition {
        .opacity.animation(.easeOut(duration: 0.2))
    }

    /// 简报为唯一主角；机会信号、今日热点深读、今日专题依次排在简报展开区之后。
    private var briefFlow: some View {
        VStack(alignment: .leading, spacing: 24) {
            BriefCard()

            if store.showOpportunities && !store.opportunities.isEmpty {
                OpportunitiesBand()
            }

            if !store.topEntries.isEmpty {
                DeepStoriesSection()
            }

            if store.showTopic, let topic = store.topic {
                TopicCard(topic: topic, related: store.topicRelatedItems)
                    .id("topic-\(store.dateString)")
            }
        }
    }

    private var hotboardSegment: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let board = store.hotBoard {
                HotBoardSummaryCard(board: board)
            } else {
                VStack(spacing: 8) {
                    Text("这一天还没有热榜快照")
                        .font(.system(size: 15, weight: .medium))
                    Text("点右上角“立即更新”重新生成即可收录微博热搜与知乎热榜。")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
    }

    private var sportsSegment: some View {
        SportsBoardView()
    }

    private var weatherSegment: some View {
        Group {
            if store.weatherDays.isEmpty {
                Text("暂无天气数据")
                    .font(.system(size: 12))
                    .foregroundStyle(PlanetTheme.secondary)
            } else {
                WeatherSection()
            }
        }
    }

    private var weekSegment: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.weeklyGroups) { group in
                WeekCategoryBlock(group: group)
            }
        }
    }
}

// MARK: - 报头两行（报头行：大日期+星期+天气+右侧热榜/一周/搜索入口；元信息行：期数·条数·更新时间）

struct MastheadView: View {
    @EnvironmentObject private var store: DigestStore
    @StateObject private var calendarModel = CalendarPopoverModel()
    @StateObject private var model = MastheadModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            metaRow
                .padding(.top, 10)

            // 报纸双规则线：粗线 + 淡出发丝线
            VStack(spacing: 5) {
                Rectangle()
                    .fill(PlanetTheme.ink)
                    .frame(height: 2)
                GradientRule(strength: 0.24)
            }
            .padding(.top, 14)

            // 打开第一屏的「编辑部一句话」，本地数据，零网络
            EditorLead()
        }
    }

    // 报头行：‹ › 大日期 星期 · 城市 温度 天气 ……… [热榜] [一周] [搜索]
    private var headerRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                HeaderIconButton(
                    systemImage: "chevron.left",
                    help: "前一天（⌘←）",
                    disabled: store.isGenerating
                ) {
                    store.previousDay()
                }

                HeaderIconButton(
                    systemImage: "chevron.right",
                    help: "后一天（⌘→）",
                    disabled: !store.canGoNext || store.isGenerating
                ) {
                    store.nextDay()
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.mastheadDate)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(PlanetTheme.ink)
                Text(store.mastheadWeekday)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(PlanetTheme.secondary)
                if let weather = store.weatherDays.first {
                    // spec 版式：杭州 12°C 晴（°C 单位 + 中文天气文字）
                    Text("· \(store.weatherCity) \(Int(weather.minTemp.rounded()))~\(Int(weather.maxTemp.rounded()))°C \(weather.conditionLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                }
            }

            Spacer(minLength: 16)

            if model.isSearchFieldShown {
                SearchField(text: $store.searchText, prompt: "搜索全部栏目")
                    .frame(width: 220)
                Button {
                    model.isSearchFieldShown = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("收起搜索")
            } else {
                // 报头降噪：热榜/一周已在下方分段控件里，这里保留设置与搜索两个入口
                HStack(spacing: 8) {
                    MastheadPill(title: "外观与设置") {
                        NotificationCenter.default.post(
                            name: Notification.Name("DailyDigestOpenSettings"),
                            object: nil
                        )
                    }
                    MastheadPill(title: "搜索") {
                        model.isSearchFieldShown = true
                    }
                }
            }
        }
    }

    // 元信息行：第 N 期 · 共 46 条 · 农历… · 更新于 20:19 ……… [日历] [回到今天] [立即更新]
    private var metaRow: some View {
        HStack(spacing: 8) {
            Text(metaText)
                .font(.system(size: 11))
                .foregroundStyle(PlanetTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Button {
                    calendarModel.isShowing.toggle()
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(calendarModel.isShowing ? PlanetTheme.secondary : PlanetTheme.muted)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(calendarModel.isShowing ? 0.08 : 0.04))
                        )
                }
                .buttonStyle(.plain)
                .help("按日历选择历史日报")
                .popover(isPresented: $calendarModel.isShowing, arrowEdge: .bottom) {
                    ArchiveCalendarView(model: calendarModel)
                        .environmentObject(store)
                }

                if !store.isToday {
                    Button("回到今天") {
                        store.goToday()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .font(.system(size: 10))
                }

                Button {
                    store.generateNow()
                } label: {
                    HStack(spacing: 4) {
                        if store.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(store.isGenerating ? "更新中…" : "立即更新")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.isGenerating)
            }
        }
    }

    /// 元信息行文案：期数 · 条数 · 农历 · 更新时间
    private var metaText: String {
        var parts: [String] = ["第 \(store.issueNumber) 期", "共 \(store.totalCount) 条"]
        if let lunar = store.lunarLabel {
            parts.append("农历" + lunar)
        }
        if let generated = store.generatedTimeText {
            parts.append(generated)
        }
        return parts.joined(separator: " · ")
    }
}

private struct MastheadPill: View {
    let title: String
    let action: () -> Void
    @StateObject private var hover = HoverModel()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: title.contains("设置") ? "slider.horizontal.3" : "magnifyingglass")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(hover.isOn ? PlanetTheme.ink : PlanetTheme.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hover.isOn ? 0.075 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hover.isOn ? 0.13 : 0.055), lineWidth: 0.7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}

// MARK: - 今日播报（深蓝电台卡：大圆播放键 + 波形章节进度 + 下一章预告 + 功能 chips）

struct TTSBar: View {
    @ObservedObject var player: TTSPlayer
    let date: String
    @StateObject private var voicePopover = VoicePopoverModel()
    @StateObject private var schedulePopover = SchedulePopoverModel()

    private var currentSpeedLabel: String {
        TTSPlayer.speeds.first(where: { abs($0.value - player.rate) < 0.01 })?.label
            ?? String(format: "%.2g×", player.rate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 第一行：大号圆形播放键（播放中 0.2s ease-out 呼吸）+ 正在播 · 第 x/y 章 · 章节名 + 倍速胶囊
            HStack(spacing: 12) {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying ? 0 : 1)
                        .frame(width: 52, height: 52)
                        .background(PlanetTheme.accent, in: Circle())
                        .shadow(color: PlanetTheme.accent.opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .scaleEffect(player.isPlaying ? 1.04 : 1.0)
                .animation(
                    player.isPlaying
                        ? .easeOut(duration: 0.2).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                    value: player.isPlaying
                )
                .buttonStyle(.plain)
                .disabled(!player.hasAudio || player.isGeneratingVoice)
                .opacity(player.hasAudio && !player.isGeneratingVoice ? 1 : 0.45)
                .accessibilityLabel(player.isPlaying ? "暂停今日播报" : "播放今日播报")
                .help(player.isPlaying ? "暂停播报" : "播放今日完整节目")

                Text(stationTitle)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(PlanetTheme.whiteInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Menu {
                    ForEach(TTSPlayer.speeds, id: \.label) { speed in
                        Button("\(speed.label) 倍速") { player.setRate(speed.value) }
                    }
                } label: {
                    Text(currentSpeedLabel)
                }
                .playerChipMenu()
                .help("播放倍速")
                .disabled(!player.hasAudio)
            }

            // 第二行：波形进度条（已播 whiteInk，未播半透明；轻点跳章节，拖动微调）
            RadioWaveform(
                progress: player.progress,
                duration: player.duration,
                chapters: player.chapters,
                enabled: player.hasAudio,
                scrubbingFraction: $player.scrubbingFraction,
                scrubLabelProvider: { player.scrubLabel(for: $0) },
                onSeek: { player.seek(to: $0) },
                onJumpToChapter: { player.jumpToChapter($0) }
            )

            // 第三行：下一章灰字预告 + 右下角功能 chips
            HStack(spacing: 8) {
                if !stationFooter.isEmpty {
                    Text(stationFooter)
                        .font(.system(size: 10))
                        .foregroundStyle(PlanetTheme.whiteInk.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Button { player.restartFromBeginning() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .playerChip()
                    .disabled(!player.hasAudio)
                    .help("从头听")
                    .accessibilityLabel("从头听")

                    // 第一轮 spec「右下角保留倍速胶囊与音色入口」：倍速胶囊同时保留在右下角
                    //（第一行右侧另有倍速 Menu，对应第二轮目标版式；两处操作同一 player.rate）
                    Menu {
                        ForEach(TTSPlayer.speeds, id: \.label) { speed in
                            Button("\(speed.label) 倍速") { player.setRate(speed.value) }
                        }
                    } label: {
                        Text(currentSpeedLabel)
                    }
                    .playerChipMenu()
                    .help("播放倍速")
                    .disabled(!player.hasAudio)

                    Button { voicePopover.isShowing.toggle() } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .playerChip()
                    .help("选择播报音色")
                    .accessibilityLabel("选择播报音色")

                    Button {
                        schedulePopover.prepare(from: player)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .semibold))
                            Text(player.autoPlayEnabled ? player.autoPlayTime : "定时")
                        }
                    }
                    .playerChip()
                    .accessibilityLabel("设置定时播报")
                    .help(player.autoPlayEnabled ? "每天 \(player.autoPlayTime) 自动播报" : "自动播报已关闭")
                    .popover(isPresented: $schedulePopover.isShowing, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("定时播报").font(.system(size: 15, weight: .semibold))
                            Toggle("每天自动播放", isOn: $schedulePopover.enabled)
                                .font(.system(size: 12))
                            HStack(spacing: 8) {
                                Text("播放时间")
                                Spacer()
                                Picker("小时", selection: $schedulePopover.hour) {
                                    ForEach(0..<24, id: \.self) { value in
                                        Text(String(format: "%02d", value)).tag(value)
                                    }
                                }
                                .labelsHidden().frame(width: 66)
                                Text(":")
                                Picker("分钟", selection: $schedulePopover.minute) {
                                    ForEach(0..<60, id: \.self) { value in
                                        Text(String(format: "%02d", value)).tag(value)
                                    }
                                }
                                .labelsHidden().frame(width: 66)
                            }
                            .font(.system(size: 12))
                            .accessibilityElement(children: .contain)
                            Text("使用本机时间；关闭应用后也会按设置播放。")
                                .font(.system(size: 10)).foregroundStyle(PlanetTheme.secondary)
                            if let error = schedulePopover.error {
                                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                            }
                            HStack {
                                Spacer()
                                Button("取消") { schedulePopover.isShowing = false }
                                Button("保存") {
                                    let time = String(format: "%02d:%02d", schedulePopover.hour, schedulePopover.minute)
                                    if player.saveScheduledPlayback(enabled: schedulePopover.enabled, time: time) {
                                        schedulePopover.isShowing = false
                                    } else {
                                        schedulePopover.error = "保存失败，请检查配置文件。"
                                    }
                                }.buttonStyle(.borderedProminent)
                            }
                            .font(.system(size: 12))
                        }
                        .padding(20).frame(width: 300)
                        .foregroundStyle(PlanetTheme.ink)
                        .background(PlanetTheme.paper)
                    }

                    if !player.chapters.isEmpty {
                        Button {
                            player.showChaptersDrawer.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: player.showChaptersDrawer ? "chevron.up" : "list.number")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("节目单 \(player.chapters.count)")
                            }
                            .fixedSize()
                        }
                        .playerChip()
                        .accessibilityLabel(player.showChaptersDrawer ? "收起播报章节" : "展开播报章节")
                    }
                }
            }

            if player.showChaptersDrawer && !player.chapters.isEmpty {
                Rectangle().fill(PlanetTheme.whiteInk.opacity(0.18)).frame(height: 0.5)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(Array(player.chapters.enumerated()), id: \.element.id) { index, chapter in
                        Button { player.jumpToChapter(chapter) } label: {
                            HStack(spacing: 8) {
                                Text(String(format: "%02d", index+1)).monospacedDigit()
                                    .foregroundStyle(PlanetTheme.whiteInk.opacity(0.6))
                                Text(chapter.title)
                                Spacer(minLength: 8)
                                Text(chapter.startFormatted).monospacedDigit()
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(PlanetTheme.whiteInk)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(PlanetTheme.whiteInk.opacity(player.activeChapter == chapter ? 0.13 : 0),
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let status = player.voiceStatus {
                HStack(spacing: 8) {
                    if player.isGeneratingVoice { ProgressView().controlSize(.small) }
                    Text(status).font(.system(size: 12)).foregroundStyle(PlanetTheme.whiteInk.opacity(0.9))
                }
            }
            if player.voiceMissing {
                Text("系统未安装中文语音。请到「系统设置 → 辅助功能 → 朗读内容」下载婷婷。")
                    .font(.system(size: 12)).foregroundStyle(Color(hex: "#F3C5AF"))
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(PlanetTheme.whiteInk)
            }
            if let error = player.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(Color(hex: "#F3C5AF"))
            }
        }
        .padding(20)
        .background {
            // 电台卡：深靛底 + 左上斜向柔光，让它像一块独立的仪表而不是一条横幅
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(PlanetTheme.navy)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.105), Color.white.opacity(0.025), Color.clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 7)
        .popover(isPresented: $voicePopover.isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择播报音色").font(.system(size: 15, weight: .semibold))
                Text("试听后选择；选择会重新生成 \(date) 的播报。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(TTSPlayer.voices, id: \.id) { voice in
                    HStack {
                        Button {
                            player.previewVoice(voice.id)
                        } label: {
                            Label(player.previewingVoice == voice.id ? "停止试听" : "试听",
                                  systemImage: player.previewingVoice == voice.id ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                        .accessibilityLabel("\(voice.label)\(player.previewingVoice == voice.id ? "停止试听" : "试听")")
                        Text(voice.label)
                            .font(.system(size: 12))
                        Spacer()
                        Button(player.voiceCode == voice.id ? "重新生成" : "选择") {
                            player.selectVoice(voice.id, date: date)
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: 12))
                        .disabled(player.isGeneratingVoice)
                        if player.voiceCode == voice.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .help("当前所选音色")
                        }
                    }
                }
                Text("当前音频：\(player.voiceName) · 所选音色：\(TTSPlayer.voices.first(where: { $0.id == player.voiceCode })?.label ?? player.voiceCode)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if let status = player.voiceStatus {
                    Text(status).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(PlanetTheme.ink)
            .tint(PlanetTheme.ink)
            .padding(20).frame(width: 440)
            .background(PlanetTheme.paper)
            .onDisappear { player.stopPreview() }
        }
        .environment(\.colorScheme, .dark)
    }

    /// 第一行文案：正在播/已暂停 · 第 x/y 章 · 章节名；无音频时给出状态说明。
    private var stationTitle: String {
        if !player.hasAudio {
            return player.isGeneratingVoice ? "正在合成今日节目…" : "音频暂未生成，请检查服务状态后重试"
        }
        var parts: [String] = [player.isPlaying ? "正在播" : "已暂停"]
        if let active = player.activeChapter,
           let index = player.chapters.firstIndex(where: { $0.id == active.id }) {
            parts.append("第 \(index + 1)/\(player.chapters.count) 章")
            parts.append(active.title)
        }
        return parts.joined(separator: " · ")
    }

    /// 第三行文案：下一章预告；无下一章时退化为时长与音色信息。
    private var stationFooter: String {
        if let next = nextChapter {
            return "下一章 · \(next.title)"
        }
        if player.hasAudio {
            return "\(player.durationLabel) · \(player.voiceName)朗读"
        }
        return ""
    }

    private var nextChapter: TTSChapter? {
        guard let active = player.activeChapter,
              let index = player.chapters.firstIndex(where: { $0.id == active.id }),
              index + 1 < player.chapters.count else { return nil }
        return player.chapters[index + 1]
    }
}

extension View {
    /// 播报条上的浅色功能 chip。
    func playerChip() -> some View {
        self
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(PlanetTheme.whiteInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PlanetTheme.whiteInk.opacity(0.12))
            )
            .buttonStyle(.plain)
    }

    /// 菜单版 chip（Menu 不能套 buttonStyle）。
    func playerChipMenu() -> some View {
        self
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(PlanetTheme.whiteInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PlanetTheme.whiteInk.opacity(0.12))
            )
            .menuStyle(.borderlessButton)
            .fixedSize()
    }
}

/// 波形进度条：静态柱状（确定性振幅），已播 whiteInk、未播半透明；
/// 轻点跳到所在章节起点，拖动连续微调进度，亮色刻度为章节起点。
struct RadioWaveform: View {
    let progress: Double
    let duration: Double
    let chapters: [TTSChapter]
    let enabled: Bool
    @Binding var scrubbingFraction: Double?
    let scrubLabelProvider: (Double) -> String
    let onSeek: (Double) -> Void
    let onJumpToChapter: (TTSChapter) -> Void

    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 4
    private static let amplitudes: [CGFloat] = [
        0.42, 0.68, 0.35, 0.82, 0.55, 0.95, 0.48, 0.72, 0.38, 0.88,
        0.60, 0.44, 0.78, 0.52, 0.92, 0.40, 0.66, 0.85, 0.50, 0.74,
        0.36, 0.90, 0.58, 0.46, 0.80, 0.62, 0.94, 0.43, 0.70, 0.54,
        0.86, 0.39, 0.76, 0.49, 0.68, 0.84, 0.45, 0.91, 0.57, 0.73,
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let displayProgress = scrubbingFraction ?? progress
            let pitch = Self.barWidth + Self.barGap
            let barCount = max(12, Int((width + Self.barGap) / pitch))

            ZStack(alignment: .leading) {
                HStack(spacing: Self.barGap) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(
                                (CGFloat(index) + 0.5) * pitch <= width * min(max(displayProgress, 0), 1)
                                    ? PlanetTheme.whiteInk
                                    : PlanetTheme.whiteInk.opacity(0.28)
                            )
                            .frame(width: Self.barWidth, height: Self.barHeight(index: index))
                    }
                }

                if duration > 0 {
                    ForEach(chapters) { chapter in
                        let fraction = min(max(chapter.start / duration, 0), 1)
                        if fraction > 0.01 && fraction < 0.99 {
                            Rectangle()
                                .fill(PlanetTheme.whiteInk.opacity(0.55))
                                .frame(width: 1.5, height: 26)
                                .offset(x: width * fraction)
                                .help("\(chapter.title)（\(chapter.startFormatted)）")
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        // 拖动 = 连续微调进度
                        if abs(value.translation.width) > 6 {
                            let fraction = min(max(value.location.x / width, 0), 1)
                            scrubbingFraction = fraction
                            onSeek(fraction)
                        }
                    }
                    .onEnded { value in
                        guard enabled else { return }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        // 轻点 = 跳转所在章节
                        if abs(value.translation.width) <= 6, let chapter = chapter(atFraction: fraction) {
                            onJumpToChapter(chapter)
                        } else {
                            onSeek(fraction)
                        }
                        scrubbingFraction = nil
                    }
            )
        }
        .frame(height: 28)
        .help("轻点跳转章节，拖动微调进度（亮色刻度为章节起点）")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播报进度")
        .accessibilityValue(scrubLabelProvider(progress))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: onSeek(min(1, progress + 15 / max(duration, 1)))
            case .decrement: onSeek(max(0, progress - 15 / max(duration, 1)))
            @unknown default: break
            }
        }
    }

    private static func barHeight(index: Int) -> CGFloat {
        8 + 14 * amplitudes[index % amplitudes.count]
    }

    /// 与 TTSPlayer.chapter(at:) 同一套就近归属逻辑：返回轻点位置所在的章节。
    private func chapter(atFraction fraction: Double) -> TTSChapter? {
        guard duration > 0, !chapters.isEmpty else { return nil }
        let seconds = duration * min(max(fraction, 0), 1)
        var matched = chapters[0]
        for chapter in chapters {
            if seconds + 0.3 >= chapter.start {
                matched = chapter
            } else {
                break
            }
        }
        return matched
    }
}

// MARK: - NBA 赛事页（ESPN 公开数据：进行中 / 昨夜战报 / 今日赛程，北京时间）

struct NbaBadge: View {
    var size: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hex: "#1D428A"))
            .frame(width: size, height: size)
            .overlay(
                Text("NBA")
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            )
    }
}

struct SportsBoardView: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("NBA 赛场")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(PlanetTheme.ink)
                        Text("比分 · 赛程")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                        Spacer(minLength: 8)
                        Text("时间为北京时间")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(PlanetTheme.muted)
                    }
                    .padding(.bottom, 6)
                    Text("比分随每次生成更新；点击右上角“立即更新”刷新最新战况。")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                        .padding(.bottom, 12)
                    VStack(spacing: 4) {
                        Rectangle().fill(PlanetTheme.ink).frame(height: 2.5)
                        Rectangle().fill(Color.primary.opacity(0.14)).frame(height: 0.75)
                    }
                }

                if store.nbaGames.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(PlanetTheme.secondary)
                        Text("这一天没有赛事快照")
                            .font(.system(size: 15, weight: .medium))
                        Text("点右上角“立即更新”即可收录 NBA 比分与赛程。")
                            .font(.system(size: 12))
                            .foregroundStyle(PlanetTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 64)
                } else {
                    let games = store.nbaGames
                    let live = games.filter { $0.state == "in" }
                    let finished = games.filter { $0.state == "post" }
                    let upcoming = games.filter { $0.state == "pre" }
                    if !live.isEmpty {
                        SportsGroupCard(header: "进行中", detail: nil, games: live)
                    }
                    if !finished.isEmpty {
                        SportsGroupCard(header: "昨夜战报", detail: nil, games: finished)
                    }
                    if !upcoming.isEmpty {
                        SportsGroupCard(header: "今日赛程", detail: nil, games: upcoming)
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }
}

struct SportsGroupCard: View {
    let header: String
    let detail: String?
    let games: [NbaGame]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                NbaBadge(size: 20)
                Text(header)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PlanetTheme.ink)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(PlanetTheme.muted)
                }
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HairlineDivider().padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    NbaGameRow(game: game)
                    if index < games.count - 1 {
                        HairlineDivider().padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .digestCard(interactive: false)
    }
}

struct NbaGameRow: View {
    let game: NbaGame

    private var homeWins: Bool {
        guard let home = game.homeScore, let away = game.awayScore else { return false }
        return home >= away
    }

    private func teamRow(name: String, score: Int?, isWinner: Bool) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 13, weight: isWinner && game.state != "pre" ? .semibold : .regular))
                .foregroundStyle(isWinner && game.state != "pre" ? PlanetTheme.ink : PlanetTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let score, game.state != "pre" {
                Text("\(score)")
                    .font(.system(size: 15, weight: isWinner ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(isWinner ? PlanetTheme.ink : PlanetTheme.secondary)
            } else {
                Text("—")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(PlanetTheme.muted)
            }
        }
    }

    private var statusText: String {
        switch game.state {
        case "in": return game.detail ?? "进行中"
        case "post": return "已结束"
        default: return game.startText
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                teamRow(name: game.awayName, score: game.awayScore, isWinner: game.state != "pre" && game.awayWins)
                teamRow(name: game.homeName, score: game.homeScore, isWinner: game.state != "pre" && !game.awayWins)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(statusText)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(game.state == "in" ? PlanetTheme.ink : PlanetTheme.muted)
                .fixedSize()
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 机会信号通栏横带（三列，绿色语义洗色；嵌在双栏头版与深读之间）

struct OpportunitiesBand: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12, weight: .medium))
                Text("机会信号")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(store.opportunities.count) 条跟进线索")
                    .font(.system(size: 10))
            }
            // 灰阶纪律：机会信号带不再用绿色语义洗色，电台卡保持全页唯一重色块
            .foregroundStyle(PlanetTheme.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
                spacing: 16
            ) {
                ForEach(store.opportunities) { opportunity in
                    OpportunityRow(opportunity: opportunity, linked: store.opportunityEntry(opportunity))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PlanetTheme.paper)
        )
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }
}

// MARK: - 一日简报（单列新闻条：accent 序号 + 中文标题 + 来源·时间 + 「原文」Popover，默认 5 条可展开）

struct BriefCard: View {
    @EnvironmentObject private var store: DigestStore
    @StateObject private var expansion = TopicExpansion()

    private let collapsedCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 英文只出现在「原文」Popover：眉标不再带英文小标
            SectionHeader(kicker: "今日简报")
            if let brief = store.brief {
                let entries = orderedEntries
                let visible = expansion.isExpanded ? entries : Array(entries.prefix(collapsedCount))
                VStack(alignment: .leading, spacing: 0) {
                    if let headline = brief.headline, !headline.isEmpty {
                        // 英文兜底：导语若是未翻译英文，同样收敛为 12px 灰斜体 + 「未翻译」角标
                        let headlineIsChinese = headline.isChineseTitle
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(headline)
                                .font(entryTitleFont(hasChinese: headlineIsChinese, chineseWeight: .bold))
                                .italic(!headlineIsChinese)
                                .lineSpacing(4)
                                .foregroundStyle(headlineIsChinese ? PlanetTheme.ink : PlanetTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            if !headlineIsChinese {
                                UntranslatedBadge()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            BriefNewsRow(index: index + 1, entry: entry, title: displayTitle(of: entry))
                            if index < visible.count - 1 {
                                // 强制规范：新闻条分隔线用 0.5px rule 色（与今日热点行一致）
                                Rectangle()
                                    .fill(PlanetTheme.rule)
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.top, 8)

                    if expansion.isExpanded, !brief.summary.isEmpty {
                        Text(brief.summary)
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .foregroundStyle(PlanetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    if entries.count > collapsedCount || !brief.summary.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { expansion.isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(expandedLabel(total: entries.count))
                                Image(systemName: expansion.isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    } else {
                        Spacer(minLength: 12)
                    }
                }
                .digestCard(interactive: false)
            }
        }
    }

    /// 未翻译条目（标题不含中文）排序沉底，其余保持原有顺序。
    private var orderedEntries: [DigestBriefEntry] {
        store.briefEntries.enumerated()
            .sorted { a, b in
                let aChinese = hasChineseTitle(a.element)
                let bChinese = hasChineseTitle(b.element)
                if aChinese != bChinese { return aChinese }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    private func hasChineseTitle(_ entry: DigestBriefEntry) -> Bool {
        displayTitle(of: entry).isChineseTitle
    }

    /// 行标题：取「——」前的中文导语，否则整句 point.text。
    private func displayTitle(of entry: DigestBriefEntry) -> String {
        let parts = entry.point.text.components(separatedBy: "——")
        let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return parts.count > 1 && !title.isEmpty && entry.item != nil ? title : entry.point.text
    }

    private func expandedLabel(total: Int) -> String {
        if expansion.isExpanded { return "收起" }
        var parts: [String] = []
        if total > collapsedCount { parts.append("还有 \(total - collapsedCount) 条 · 展开全部") }
        let hasSummary = (store.brief?.summary ?? "").isEmpty == false
        if hasSummary { parts.append("编辑导语") }
        return parts.joined(separator: " · ")
    }
}

struct BriefNewsRow: View {
    @EnvironmentObject private var store: DigestStore
    let index: Int
    let entry: DigestBriefEntry
    let title: String
    @StateObject private var hover = HoverModel()
    @StateObject private var originalPopover = OriginalPopoverModel()
    // 本构建用裸 swiftc，无法展开 @State 宏；沿用代码库的 ObservableObject 模式
    @StateObject private var expansion = TopicExpansion()

    private var isExpanded: Bool { expansion.isExpanded }

    private var hasChineseTitle: Bool {
        title.isChineseTitle
    }

    /// 元信息行：来源 · 相对时间；无条目时退化为栏目名。
    private var metaText: String {
        var parts: [String] = []
        if let item = entry.item {
            if !item.source.isEmpty { parts.append(item.source) }
            if let time = item.time, !time.isEmpty { parts.append(time) }
        } else if let definition = entry.definition {
            parts.append(definition.name)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(PlanetTheme.accent)
                    .frame(width: 20, alignment: .leading)
                    .padding(.top, 4)

                // 主区：整条点击行内展开「要点 + takeaway」（强制规范），不再跳栏
                Button {
                    guard entry.item != nil else { return }
                    withAnimation(.easeOut(duration: 0.2)) { expansion.isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(title)
                                .font(entryTitleFont(hasChinese: hasChineseTitle))
                                .italic(!hasChineseTitle)
                                .foregroundStyle(hasChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if !hasChineseTitle {
                                UntranslatedBadge()
                            }
                        }

                        if !metaText.isEmpty {
                            Text(metaText)
                                .font(.system(size: 10))
                                .foregroundStyle(PlanetTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(entry.item == nil)
                .accessibilityLabel("\(isExpanded ? "收起" : "展开")第\(index)条：\(title)，\(metaText)")

                if entry.item != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { expansion.isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PlanetTheme.muted)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "收起第\(index)条详情" : "展开第\(index)条详情")

                    // 行尾「原文」胶囊：Popover 显示英文原标题与原摘要（独立按钮，避免与行点击嵌套）
                    originalButton
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover.isOn && entry.item != nil ? 0.04 : 0)))

            // 展开区：摘要（要点）+ takeaway（为什么值得看），跳转栏目降级为链接
            if isExpanded, let item = entry.item {
                VStack(alignment: .leading, spacing: 8) {
                    if !item.summary.isEmpty {
                        briefField("要点", text: item.summary)
                    }
                    if !item.takeaway.isEmpty {
                        briefField("为什么值得看", text: item.takeaway)
                    }
                    if let definition = entry.definition {
                        Button("在栏目中查看") {
                            store.openItem(itemID: item.id, categoryID: definition.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PlanetTheme.secondary)
                    }
                }
                .padding(.leading, 52)
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.isOn = $0 }
        .accessibilityElement(children: .contain)
        .help(title)
    }

    private func briefField(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(PlanetTheme.secondary)
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(PlanetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var originalButton: some View {
        Button {
            originalPopover.isShowing.toggle()
        } label: {
            Text("原文")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PlanetTheme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(PlanetTheme.rule, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("查看英文原文标题")
        .popover(isPresented: $originalPopover.isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("原文").font(.system(size: 15, weight: .semibold))
                if let item = entry.item {
                    Text(item.originalTitle ?? item.title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(PlanetTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(PlanetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
            .frame(width: 360)
            .foregroundStyle(PlanetTheme.ink)
            .background(PlanetTheme.paper)
        }
    }
}

struct OpportunityRow: View {
    @EnvironmentObject private var store: DigestStore
    let opportunity: DigestOpportunity
    let linked: DigestBriefEntry?
    @StateObject private var expansion = TopicExpansion()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                // 动效白名单：机会展开为瞬时切换，不加动画
                expansion.isExpanded.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // 英文兜底：机会标题若未翻译，收敛为 12px 灰斜体 + 「未翻译」角标
                    let titleIsChinese = opportunity.displayTitle.isChineseTitle
                    Text(opportunity.displayTitle)
                        .font(entryTitleFont(hasChinese: titleIsChinese, chineseWeight: .semibold))
                        .italic(!titleIsChinese)
                        .foregroundStyle(titleIsChinese ? PlanetTheme.ink : PlanetTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !titleIsChinese {
                        UntranslatedBadge()
                    }
                    Image(systemName: expansion.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PlanetTheme.secondary).padding(.top, 4)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(expansion.isExpanded ? "收起" : "展开")机会：\(opportunity.displayTitle)")
            if let why = opportunity.why, !why.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(why).font(.system(size: 12)).lineSpacing(4)
                        .foregroundStyle(PlanetTheme.secondary)
                        .lineLimit(expansion.isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    // 正文嵌入未翻译英文句子（数据内容限制，无法折叠进 Popover），UI 标注
                    if why.containsUntranslatedEnglish {
                        UntranslatedBadge(label: "含未翻译英文")
                    }
                }
            }
            if expansion.isExpanded {
                HStack(spacing: 12) {
                    if let category = opportunity.category, !category.isEmpty { Text(category) }
                    if let audience = opportunity.audience, !audience.isEmpty { Text(audience) }
                }.font(.system(size: 10)).foregroundStyle(PlanetTheme.secondary)
                if let how = opportunity.how, !how.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Text("怎么跟进").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PlanetTheme.ink).frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(how).font(.system(size: 12)).lineSpacing(4)
                                .foregroundStyle(PlanetTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            if how.containsUntranslatedEnglish {
                                UntranslatedBadge(label: "含未翻译英文")
                            }
                        }
                    }
                }
                if let linked, let item = linked.item, let definition = linked.definition {
                        Button("在栏目中查看") { store.openItem(itemID: item.id, categoryID: definition.id) }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - 今日热点深读（单列新闻条：accent 序号 + 标题 + 元信息行，点击展开摘要与要点）

struct DeepStoriesSection: View {
    @EnvironmentObject private var store: DigestStore

    /// 未翻译条目（标题不含中文）排序沉底，其余保持原有热度顺序。
    /// 先对全量 deepStories 排序再取前 5（对照 BriefCard 的正确顺序），
    /// 避免英文条目占据前 5 时，中文深读条目永远无法浮出。
    private var orderedStories: [DigestDeepStory] {
        func hasChinese(_ story: DigestDeepStory) -> Bool {
            story.title.isChineseTitle
        }
        return Array(
            store.deepStories.enumerated()
                .sorted { a, b in
                    let aChinese = hasChinese(a.element)
                    let bChinese = hasChinese(b.element)
                    if aChinese != bChinese { return aChinese }
                    return a.offset < b.offset
                }
                .map(\.element)
                .prefix(5)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                kicker: "今日热点",
                meta: store.deepStories.isEmpty ? "按热度排序" : "中外双视角深读"
            )
            if !store.deepStories.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(orderedStories.enumerated()), id: \.element.id) { index, story in
                        DeepNewsRow(index: index + 1, story: story)
                        if index < orderedStories.count - 1 {
                            Rectangle()
                                .fill(PlanetTheme.rule)
                                .frame(height: 0.5)
                        }
                    }
                }
                .digestCard(interactive: false)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.topEntries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        HotRow(index: index + 1, entry: entry)
                    }
                }
                .digestCard(interactive: false)
            }
        }
    }
}

struct DeepNewsRow: View {
    @EnvironmentObject private var store: DigestStore
    let index: Int
    let story: DigestDeepStory
    @StateObject private var hover = HoverModel()
    @StateObject private var expansion = TopicExpansion()

    private var expanded: Bool { expansion.isExpanded }

    private var hasChineseTitle: Bool {
        story.title.isChineseTitle
    }

    /// 元信息行：来源中文名 · 领域标签（数据无相对时间字段，不强造）。
    private var metaText: String {
        var parts: [String] = []
        if let sources = story.sources, !sources.isEmpty {
            parts.append(sources.joined(separator: " · "))
        }
        if !story.tag.isEmpty {
            parts.append(story.tag)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // 动效白名单：热点行展开为瞬时切换（与机会/专题/栏目条一致）
                expansion.isExpanded.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", index))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PlanetTheme.secondary)
                        .frame(width: 20, alignment: .leading)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(story.title)
                                .font(entryTitleFont(hasChinese: hasChineseTitle))
                                .italic(!hasChineseTitle)
                                .foregroundStyle(hasChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                                .lineLimit(expanded ? nil : 2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if !hasChineseTitle {
                                UntranslatedBadge()
                            }
                        }

                        if !metaText.isEmpty {
                            Text(metaText)
                                .font(.system(size: 10))
                                .foregroundStyle(PlanetTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PlanetTheme.muted)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hover.isOn ? 0.04 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover.isOn = $0 }
            .accessibilityLabel("\(expanded ? "收起" : "展开")热点：\(story.title)")
            .help(story.title)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !story.lead.isEmpty {
                        Text(story.lead)
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .foregroundStyle(PlanetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let impact = story.impact, !impact.isEmpty {
                        Text(impact)
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .foregroundStyle(PlanetTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let global = story.globalPerspective, !global.isEmpty {
                        perspective("国际媒体视角", text: global)
                    }
                    if let domestic = story.domesticPerspective, !domestic.isEmpty {
                        perspective("国内产业视角", text: domestic)
                    }
                    if let cid = story.categoryID, let iid = story.itemID, !cid.isEmpty, !iid.isEmpty {
                        Button("在栏目中阅读详情") { store.openItem(itemID: iid, categoryID: cid) }
                            .buttonStyle(.plain).foregroundStyle(PlanetTheme.secondary).font(.system(size: 12))
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func perspective(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(PlanetTheme.ink)
            Text(text).font(.system(size: 12)).lineSpacing(4).foregroundStyle(PlanetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

struct HotRow: View {
    @EnvironmentObject private var store: DigestStore
    let index: Int
    let entry: DigestBriefEntry
    @StateObject private var hover = HoverModel()

    private var rankColor: Color {
        index <= 3 ? PlanetTheme.ink : Color.secondary.opacity(0.55)
    }

    var body: some View {
        Button {
            if let item = entry.item, let definition = entry.definition {
                store.openItem(itemID: item.id, categoryID: definition.id)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(rankColor)
                    .frame(width: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    // 英文兜底：行标题可能是流水线 point.text，统一走 isChineseTitle 判定
                    let rowTitle = entry.item?.title ?? entry.point.text
                    let titleIsChinese = rowTitle.isChineseTitle
                    Text(rowTitle)
                        .font(entryTitleFont(hasChinese: titleIsChinese, chineseWeight: .semibold))
                        .italic(!titleIsChinese)
                        .foregroundStyle(titleIsChinese ? .primary : PlanetTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !titleIsChinese {
                        UntranslatedBadge()
                    }

                    HStack(spacing: 8) {
                        if let definition = entry.definition {
                            Text(definition.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(definition.color)
                        }
                        if let item = entry.item {
                            Text(item.source)
                                .font(.system(size: 10))
                                .foregroundStyle(PlanetTheme.muted)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PlanetTheme.muted)
                    .opacity(hover.isOn ? 0.9 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hover.isOn ? 0.04 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}

// MARK: - 第四块：今日专题（默认折叠成一行可展开）

final class TopicExpansion: ObservableObject {
    @Published var isExpanded: Bool = false
}

struct TopicCard: View {
    @EnvironmentObject private var store: DigestStore
    let topic: DigestTopic
    let related: [DigestTopicRelated]
    @StateObject private var expansion = TopicExpansion()

    private var isExpanded: Bool {
        expansion.isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // 动效白名单：专题展开为瞬时切换，不加动画
                expansion.isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(PlanetTheme.ink)
                        .frame(width: 3, height: 11)
                    Text("今日专题")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(PlanetTheme.secondary)
                        .fixedSize()

                    Text(topic.title)
                        .font(entryTitleFont(hasChinese: topic.title.isChineseTitle, chineseWeight: .semibold))
                        .italic(!topic.title.isChineseTitle)
                        .foregroundStyle(topic.title.isChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    if !topic.title.isChineseTitle {
                        UntranslatedBadge()
                    }

                    Spacer(minLength: 8)

                    Text(isExpanded ? "收起" : "展开")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PlanetTheme.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PlanetTheme.muted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    HairlineDivider()

                    Text(topic.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(topic.points.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PlanetTheme.secondary)
                                    .padding(.top, 4)
                                Text(point)
                                    .font(.system(size: 12))
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if !related.isEmpty {
                        HairlineDivider()

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 210), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(Array(related.prefix(4))) { entry in
                                TopicRelatedChip(related: entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .digestCard(interactive: false)
        .onChange(of: store.dateString) { _, _ in
            expansion.isExpanded = false
        }
    }
}

struct TopicRelatedChip: View {
    @EnvironmentObject private var store: DigestStore
    let related: DigestTopicRelated
    @StateObject private var hover = HoverModel()

    var body: some View {
        Button {
            store.openItem(
                itemID: related.item.id,
                categoryID: related.definition.id
            )
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(related.definition.color)
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(related.definition.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(related.definition.color)
                    Text(related.item.title)
                        .font(entryTitleFont(hasChinese: related.item.title.isChineseTitle))
                        .italic(!related.item.title.isChineseTitle)
                        .foregroundStyle(related.item.title.isChineseTitle ? .primary : PlanetTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !related.item.title.isChineseTitle {
                        UntranslatedBadge()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hover.isOn ? 0.05 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}

// MARK: - 全网热榜（要知式榜单：宋体大排名 + 印章标签 + 热度值；头版右栏窄卡 + 独立完整页）

struct HotBoardSummaryCard: View {
    @EnvironmentObject private var store: DigestStore
    let board: HotBoardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "全网热榜")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(board.sources.prefix(2).enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        HairlineDivider()
                            .padding(.vertical, 12)
                    }
                    sourceBlock(source)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button {
                        store.searchText = ""
                        store.selectedCategoryID = DigestStore.hotboardID
                    } label: {
                        HStack(spacing: 4) {
                            Text("完整热榜页")
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PlanetTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .digestCard(interactive: false)
        }
    }

    @ViewBuilder
    private func sourceBlock(_ source: HotListSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: source.id == "weibo" ? "flame.fill" : "text.bubble.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PlanetTheme.secondary)
                Text(source.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PlanetTheme.ink)
                Text("\(source.items.count) 条")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PlanetTheme.muted)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            ForEach(Array(source.items.prefix(5).enumerated()), id: \.element.id) { index, entry in
                HotSummaryRow(index: index + 1, entry: entry)
            }
        }
    }
}

struct HotSummaryRow: View {
    let index: Int
    let entry: HotListEntry
    @StateObject private var hover = HoverModel()

    private var rankColor: Color {
        switch index {
        case 1: return PlanetTheme.ink
        case 2, 3: return PlanetTheme.secondary
        default: return PlanetTheme.muted
        }
    }

    var body: some View {
        Button {
            if let url = URL(string: entry.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(rankColor)
                    .frame(width: 16, alignment: .trailing)
                if let badge = entry.badge {
                    HotBadge(badge: badge)
                }
                Text(entry.title)
                    .font(entryTitleFont(hasChinese: entry.title.isChineseTitle, chineseWeight: .semibold))
                    .italic(!entry.title.isChineseTitle)
                    .foregroundStyle(entry.title.isChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !entry.title.isChineseTitle {
                    UntranslatedBadge()
                }
                Spacer(minLength: 8)
                if let heat = entry.heat, !heat.isEmpty {
                    Text(heat)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PlanetTheme.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover.isOn ? 0.04 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .help(entry.title)
        .accessibilityLabel("第\(index)名，\(entry.title)，\(entry.heat ?? "")")
    }
}

struct HotBoardView: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("全网热榜")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(PlanetTheme.ink)
                        Text("微博 · 知乎")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                        Spacer(minLength: 8)
                        if let updated = store.hotBoard?.updatedAt, let text = boardTimeText(updated) {
                            Text("快照 \(text)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(PlanetTheme.muted)
                        }
                    }
                    .padding(.bottom, 8)
                    Text("榜单随每日生成滚动更新；点击词条打开对应平台的讨论页。")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                        .padding(.bottom, 12)
                    VStack(spacing: 4) {
                        Rectangle().fill(PlanetTheme.ink).frame(height: 2.5)
                        Rectangle().fill(Color.primary.opacity(0.14)).frame(height: 0.75)
                    }
                }

                if let board = store.hotBoard {
                    // 强制规范：单列、每来源一个分组标题（不是三套卡片），每条一行
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(board.sources) { source in
                            HotBoardSection(source: source)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "flame")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(PlanetTheme.secondary)
                        Text("这一天还没有热榜快照")
                            .font(.system(size: 15, weight: .medium))
                        Text("点右上角“立即更新”重新生成即可收录微博热搜与知乎热榜。")
                            .font(.system(size: 12))
                            .foregroundStyle(PlanetTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 64)
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private func boardTimeText(_ iso: String) -> String? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "HH:mm"
        return output.string(from: date)
    }
}

/// 热榜分组：分组标题 + 单列榜单行（默认 10 条，「查看全部」行内展开），不是卡片。
struct HotBoardSection: View {
    let source: HotListSource
    @StateObject private var expansion = TopicExpansion()

    private var showsAll: Bool { expansion.isExpanded }

    private let collapsedCount = 10

    private var icon: String {
        source.id == "weibo" ? "flame.fill" : "text.bubble.fill"
    }

    private var visibleItems: [(offset: Int, element: HotListEntry)] {
        showsAll
            ? Array(source.items.enumerated())
            : Array(source.items.prefix(collapsedCount).enumerated())
    }

    var body: some View {
        let maxHeat = source.items.compactMap(\.heatValue).max()
        VStack(alignment: .leading, spacing: 8) {
            // 分组标题（微博 / 知乎）
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PlanetTheme.secondary)
                Text(source.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PlanetTheme.ink)
                Text("\(source.items.count) 条")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PlanetTheme.muted)
                Spacer(minLength: 8)
                if let updated = source.updatedAt, let text = timeText(updated) {
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PlanetTheme.muted)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.element.id) { position, pair in
                    HotRankRow(
                        index: pair.offset + 1,
                        entry: pair.element,
                        heatFraction: heatFraction(pair.element.heatValue, maxHeat)
                    )
                    if position < visibleItems.count - 1 {
                        Rectangle()
                            .fill(PlanetTheme.rule)
                            .frame(height: 0.5)
                    }
                }
            }

            if source.items.count > collapsedCount {
                Button {
                    expansion.isExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(showsAll ? "收起" : "查看全部 \(source.items.count) 条")
                        Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PlanetTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func heatFraction(_ value: Double?, _ max: Double?) -> Double? {
        guard let value, let max, max > 0 else { return nil }
        return value / max
    }

    private func timeText(_ iso: String) -> String? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "HH:mm"
        return output.string(from: date)
    }
}

// MARK: - 全局搜索

struct GlobalSearchView: View {
    @EnvironmentObject private var store: DigestStore

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private var dayGroups: [(date: String, hits: [ArchiveSearchHit])] {
        Dictionary(grouping: store.archiveResults, by: \.date)
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, hits: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("搜索「\(store.searchText)」")
                        .font(.system(size: 22, weight: .bold))
                    Spacer()
                    Text(searchSummary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PlanetTheme.muted)
                }

                if store.archiveResults.isEmpty {
                    SearchEmptyView(query: store.searchText, isSearching: store.isArchiveSearching)
                } else {
                    ForEach(dayGroups, id: \.date) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(dayTitle(group.date))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(PlanetTheme.ink)
                                Text("\(group.hits.count) 条")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(PlanetTheme.muted)
                                Spacer(minLength: 0)
                            }
                            ForEach(group.hits) { hit in
                                ArchiveHitRow(hit: hit)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var searchSummary: String {
        if store.isArchiveSearching && store.archiveResults.isEmpty {
            return "搜索中…"
        }
        return "共 \(store.searchResultCount) 条 · \(store.archiveResultDayCount) 天"
    }

    private func dayTitle(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: date) else { return date }
        return Self.dayFormatter.string(from: day)
    }
}

struct ArchiveHitRow: View {
    @EnvironmentObject private var store: DigestStore
    let hit: ArchiveSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(hit.definition.color)
                    .frame(width: 4, height: 4)
                Text(hit.definition.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PlanetTheme.secondary)
                Spacer(minLength: 8)
                Button {
                    store.openItem(itemID: hit.item.id, categoryID: hit.definition.id, date: hit.date)
                } label: {
                    HStack(spacing: 4) {
                        Text("在栏目中查看")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PlanetTheme.secondary)
                }
                .buttonStyle(.plain)
            }
            ItemCard(
                item: hit.item,
                index: 1,
                accent: hit.definition.color,
                categoryID: hit.definition.id,
                date: hit.date
            )
        }
    }
}

struct SearchEmptyView: View {
    let query: String
    var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            if isSearching {
                ProgressView()
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(PlanetTheme.secondary)
                Text("归档里没有与「\(query)」相关的条目")
                    .font(.system(size: 15, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 收藏

struct FavoritesView: View {
    @EnvironmentObject private var store: DigestStore

    /// 英文兜底：标题不含中文的收藏排序沉底（保持原有相对顺序）。
    private var orderedFavorites: [FavoriteEntry] {
        store.favorites.enumerated()
            .sorted { a, b in
                let aChinese = a.element.item.title.isChineseTitle
                let bChinese = b.element.item.title.isChineseTitle
                if aChinese != bChinese { return aChinese }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("收藏（\(store.favorites.count)）")
                    .font(.system(size: 22, weight: .bold))

                if store.favorites.isEmpty {
                    EmptyFavoritesView()
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(orderedFavorites.enumerated()), id: \.element.id) { _, entry in
                            FavoriteRow(entry: entry)
                        }
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct FavoriteRow: View {
    @EnvironmentObject private var store: DigestStore
    let entry: FavoriteEntry

    private var definition: CategoryDefinition {
        store.definition(for: entry.categoryID) ?? store.overviewDefinition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PlanetTheme.secondary)
                Text(definition.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(definition.color)
                Spacer()
                Button("查看") {
                    store.openFavorite(entry)
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
                Button {
                    store.removeFavorite(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.item.title)
                    .font(entryTitleFont(hasChinese: entry.item.title.isChineseTitle, chineseWeight: .semibold))
                    .italic(!entry.item.title.isChineseTitle)
                    .foregroundStyle(entry.item.title.isChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.item.title.isChineseTitle {
                    UntranslatedBadge()
                }
            }
            Text(entry.item.summary)
                .font(.system(size: 12))
                .foregroundStyle(PlanetTheme.secondary)
        }
        .padding(16)
        .digestCard()
    }
}

struct EmptyFavoritesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(PlanetTheme.secondary)
            Text("还没有收藏的条目")
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .digestCard(interactive: false)
    }
}

// MARK: - 栏目详情

final class CategoryExpansionModel: ObservableObject {
    @Published var expandedIDs: Set<String> = []
}

struct CategoryDetailView: View {
    @EnvironmentObject private var store: DigestStore
    @StateObject private var expansion = CategoryExpansionModel()

    /// 英文兜底：标题不含中文的条目排序沉底（保持原有相对顺序）。
    private var orderedItems: [DigestItem] {
        store.filteredItems.enumerated()
            .sorted { a, b in
                let aChinese = a.element.title.isChineseTitle
                let bChinese = b.element.title.isChineseTitle
                if aChinese != bChinese { return aChinese }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CategoryHeaderView()

                    if let disclaimer = store.disclaimer {
                        DisclaimerBanner(text: disclaimer, tint: store.selectedDefinition.color)
                    }

                    if store.filteredItems.isEmpty {
                        EmptyCategoryView()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                                ItemCard(
                                    item: item,
                                    index: index + 1,
                                    accent: store.selectedDefinition.color,
                                    categoryID: store.selectedDefinition.id,
                                    date: store.dateString,
                                    isGrouped: true,
                                    isExpanded: expansion.expandedIDs.contains(item.id),
                                    onToggle: { toggle(item.id) }
                                )
                                .id(item.id)
                                if index < orderedItems.count - 1 {
                                    HairlineDivider()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .digestCard(interactive: false)
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .onAppear { scrollToPending(proxy: proxy) }
            .onChange(of: store.pendingItemID) { _, _ in scrollToPending(proxy: proxy) }
            .onChange(of: store.filteredItems.map(\.id)) { _, _ in scrollToPending(proxy: proxy) }
            .onChange(of: store.selectedCategoryID) { _, _ in
                expansion.expandedIDs.removeAll()
                scrollToPending(proxy: proxy)
            }
            .onChange(of: store.dateString) { _, _ in
                expansion.expandedIDs.removeAll()
                scrollToPending(proxy: proxy)
            }
        }
    }

    private func toggle(_ id: String) {
        // 动效白名单：栏目条目展开为瞬时切换，不加动画
        if expansion.expandedIDs.contains(id) { expansion.expandedIDs.remove(id) }
        else { expansion.expandedIDs.insert(id) }
    }

    private func scrollToPending(proxy: ScrollViewProxy) {
        guard let target = store.pendingItemID,
              store.filteredItems.contains(where: { $0.id == target }) else { return }
        expansion.expandedIDs.insert(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard store.pendingItemID == target else { return }
            proxy.scrollTo(target, anchor: .top)
            store.pendingItemID = nil
        }
    }
}

struct CategoryHeaderView: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: store.selectedDefinition.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(store.selectedDefinition.color)
                Text(store.selectedDefinition.name)
                    .font(.system(size: 22, weight: .bold))
                Text("共 \(store.items.count) 条 · 约 \(store.selectedReadingMinutes) 分钟阅读")
                    .font(.system(size: 10))
                    .foregroundStyle(PlanetTheme.secondary)
                Spacer()
            }

            if let coverage = store.selectedCategory?.coverage, coverage.total > 0 {
                Text("信源覆盖 \(coverage.available)/\(coverage.total) · 当天累计 \(store.items.count) 条")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PlanetTheme.secondary)
                if let issues = coverage.issues, !issues.isEmpty {
                    Text("暂不可用：" + issues.joined(separator: "、") + (coverage.available == 0 ? "。本次未取得新内容。" : "。其余来源正常更新。"))
                        .font(.system(size: 11))
                        .foregroundStyle(PlanetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !store.categoryBrief.isEmpty {
                Text(store.categoryBrief)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(PlanetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .digestCard(interactive: false)
    }
}

struct StatusBanner: View {
    let icon: String
    let text: String
    let tint: Color
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1))
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

struct DisclaimerBanner: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(PlanetTheme.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

struct EmptyDigestView: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(PlanetTheme.secondary)
            Text("今天还没有日报")
                .font(.system(size: 15, weight: .semibold))
            Button("立即生成") {
                store.generateNow()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 12))
            // accent 纪律：主按钮跟随全局墨色 tint，不再使用栏目色（默认落到朱砂）
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

struct EmptyCategoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(PlanetTheme.secondary)
            Text("这个栏目今天没有合适的条目")
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

// MARK: - 条目卡片（含「与谁有关」、干货、为什么值得看、解读、多维视角）

struct ItemCard: View {
    @EnvironmentObject private var store: DigestStore
    @Environment(\.colorScheme) private var colorScheme
    let item: DigestItem
    let index: Int
    let accent: Color
    let categoryID: String
    let date: String
    var isGrouped: Bool = false
    var isExpanded: Bool = true
    var onToggle: () -> Void = {}

    private var audienceTint: Color {
        colorScheme == .dark && categoryID == "policy" ? Color(hex: "#9DBBE8") : accent
    }
    private var isFavorite: Bool {
        store.isFavorite(item, categoryID: categoryID, date: date)
    }

    var body: some View {
        Group {
            if isGrouped {
                cardContent
            } else {
                cardContent.padding(16).digestCard()
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isGrouped {
                Button(action: onToggle) {
                    HStack(alignment: .top, spacing: 16) {
                        Text(String(format: "%02d", index))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(index <= 3 ? accent : PlanetTheme.muted)
                            .frame(width: 30, alignment: .leading)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(item.title)
                                    .font(entryTitleFont(hasChinese: item.title.isChineseTitle))
                                    .italic(!item.title.isChineseTitle)
                                    .foregroundStyle(item.title.isChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                if !item.title.isChineseTitle {
                                    UntranslatedBadge()
                                }
                            }
                            HStack(spacing: 8) {
                                Text(item.source).lineLimit(1)
                                if let time = item.time, !time.isEmpty {
                                    Text("·")
                                    Text(time)
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(PlanetTheme.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "收起" : "展开")条目：\(item.title)")
                .help(item.originalTitle ?? item.title)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.title)
                        .font(entryTitleFont(hasChinese: item.title.isChineseTitle, chineseWeight: .semibold))
                        .italic(!item.title.isChineseTitle)
                        .foregroundStyle(item.title.isChineseTitle ? PlanetTheme.ink : PlanetTheme.muted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !item.title.isChineseTitle {
                        UntranslatedBadge()
                    }
                }
                .help(item.originalTitle ?? item.title)
                .padding(.bottom, 12)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let audience = item.audience, !audience.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("与谁有关").font(.system(size: 10, weight: .bold))
                                Text(audience).font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(audienceTint)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(audienceTint.opacity(0.12)))
                        }
                        Spacer(minLength: 8)
                        Button {
                            store.toggleFavorite(item, categoryID: categoryID, date: date)
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(isFavorite ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
                    }
                    if categoryID == "tokens", let promotion = item.promotion {
                        Text(date == store.todayString ? (promotion.isCurrent() ? "官方规则已核验 · " + promotion.checkedLabel : "核验已过期，暂不作为领取依据") : "历史活动 · " + promotion.checkedLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                    }
                    if !item.summary.isEmpty {
                        field("要点", icon: "text.alignleft", text: item.summary, tint: accent)
                    }
                    if !item.takeaway.isEmpty {
                        field(categoryID == "tokens" ? "发放与截止" : "为什么值得看", icon: "lightbulb", text: item.takeaway, tint: accent)
                    }
                    if !item.interpretation.isEmpty {
                        field(categoryID == "tokens" ? "门槛与使用范围" : "解读", icon: "quote.opening", text: item.interpretation, tint: accent)
                    }
                    if let perspective = item.perspective, !perspective.isEmpty {
                        field("多维视角对照", icon: "globe.americas.fill", text: perspective, tint: PlanetTheme.category("ai"))
                    }
                    HairlineDivider()
                    HStack(spacing: 8) {
                        if !isGrouped {
                            Text(String(format: "%02d", index))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.quaternary)
                            Text(item.source)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(accent).lineLimit(1)
                            if let time = item.time, !time.isEmpty {
                                Text("·").foregroundStyle(.quaternary)
                                Text(time).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(PlanetTheme.muted)
                            }
                        }
                        if let heat = item.heat, !heat.isEmpty {
                            Text(heat).font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.orange.opacity(0.9))
                        }
                        Spacer(minLength: 8)
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text(categoryID == "tokens" ? "查看官方活动" : "阅读原文")
                                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                                }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(PlanetTheme.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, isGrouped ? 44 : 0)
                .padding(.bottom, isGrouped ? 16 : 0)
            }
        }
    }

    private func field(_ label: String, icon: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .semibold)).tracking(0.6)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.11)))
            Text(text).font(.system(size: 12)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

// MARK: - 一周

struct WeekView: View {
    @EnvironmentObject private var store: DigestStore

    private var groups: [WeeklyGroup] { store.weeklyGroups }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("一周")
                            .font(.system(size: 22, weight: .bold))
                        Text(store.weeklyPeriodTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PlanetTheme.secondary)
                    }
                    Text("过去 7 天的日报回顾：收藏和热度最高的条目，按栏目分组。")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.secondary)
                }

                ForEach(groups) { group in
                    WeekCategoryBlock(group: group)
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }
}

struct WeekCategoryBlock: View {
    @EnvironmentObject private var store: DigestStore
    let group: WeeklyGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: group.definition.icon)
                    .font(.system(size: 12, weight: .semibold))
                    // 灰阶纪律：分组图标不再用栏目色
                    .foregroundStyle(PlanetTheme.secondary)
                Text(group.definition.name)
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(group.items) { entry in
                    Button {
                        store.openWeeklyItem(entry)
                    } label: {
                        HStack(spacing: 12) {
                            Text(entry.date.suffix(5))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(PlanetTheme.muted)
                            Text(entry.item.title)
                                .font(entryTitleFont(hasChinese: entry.item.title.isChineseTitle))
                                .italic(!entry.item.title.isChineseTitle)
                                .foregroundStyle(entry.item.title.isChineseTitle ? .primary : PlanetTheme.muted)
                                .lineLimit(1)
                            if !entry.item.title.isChineseTitle {
                                UntranslatedBadge()
                            }
                            Spacer()
                            Text(entry.item.source)
                                .font(.system(size: 10))
                                .foregroundStyle(PlanetTheme.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .digestCard(interactive: false)
    }
}

struct WeatherSection: View {
    @EnvironmentObject private var store: DigestStore

    var body: some View {
        if !store.weatherDays.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("\(store.weatherCity) · 未来 7 天天气", systemImage: "cloud.sun.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PlanetTheme.secondary)

                HStack(spacing: 8) {
                    ForEach(store.weatherDays.prefix(7)) { day in
                        VStack(spacing: 4) {
                            Text(day.weekdayLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(PlanetTheme.secondary)
                            Image(systemName: day.symbolName)
                                .font(.system(size: 15))
                                // 灰阶纪律：天气图标不再用橙色
                                .foregroundStyle(PlanetTheme.secondary)
                            Text("\(Int(day.minTemp.rounded()))°~\(Int(day.maxTemp.rounded()))°")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
            .padding(16)
            .digestCard(interactive: false)
        }
    }
}
