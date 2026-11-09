import SwiftUI
import Combine

// 本构建用裸 swiftc，@State 宏不可用；统一沿用代码库的 ObservableObject 模式。
final class SettingsForm: ObservableObject {
    @Published var cityInput: String = ""
    @Published var latInput: String = ""
    @Published var lonInput: String = ""
    @Published var saved: Bool = false
}

final class SettingsPresentation: ObservableObject {
    @Published var showing: Bool = false
}

// MARK: - 偏好设置
// 所有开关都写回 config.json，后端下次生成与播报即按新设置执行。

struct SettingsView: View {
    @EnvironmentObject private var store: DigestStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = SettingsForm()

    private let cityPresets: [(String, Double, Double)] = [
        ("杭州富阳", 30.05, 119.95),
        ("北京", 39.90, 116.40),
        ("上海", 31.23, 121.47),
        ("广州", 23.13, 113.26),
        ("深圳", 22.54, 114.06),
        ("成都", 30.57, 104.07),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PlanetTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("偏好设置")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PlanetTheme.ink)
                    Text("栏目、播报、皮肤与天气都由你决定")
                        .font(.system(size: 11))
                        .foregroundStyle(PlanetTheme.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PlanetTheme.secondary)
                        .padding(7)
                        .background(PlanetTheme.selection, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            HairlineDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    moduleSection
                    broadcastSection
                    skinSection
                    weatherSection
                    appearanceSection
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)

            HairlineDivider()

            HStack(spacing: 12) {
                Text(form.saved ? "已保存，下次生成生效" : "改动只会写入本机配置文件")
                    .font(.system(size: 11))
                    .foregroundStyle(PlanetTheme.muted)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
                Button("保存并重新生成") {
                    commitWeather()
                    store.saveConfig()
                    form.saved = true
                    store.generateNow()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(PlanetTheme.navy)
                Button("仅保存") {
                    commitWeather()
                    store.saveConfig()
                    form.saved = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 660, height: 720)
        .background(PlanetTheme.canvas)
        .onAppear {
            form.cityInput = store.weatherCity
            form.latInput = String(store.weatherLatitude)
            form.lonInput = String(store.weatherLongitude)
        }
    }

    // MARK: 模块自选

    private var groupedModules: [(String, [ModuleEntry])] {
        var seen: Set<String> = []
        var result: [(String, [ModuleEntry])] = []
        for group in ["要闻", "科技", "生活", "兴趣", "活动"] {
            let entries = store.moduleCatalog.filter { $0.group == group }
            if !entries.isEmpty {
                result.append((group, entries))
                seen.formUnion(entries.map(\.id))
            }
        }
        let rest = store.moduleCatalog.filter { !seen.contains($0.id) }
        if !rest.isEmpty { result.append(("其他", rest)) }
        return result
    }

    private var moduleSection: some View {
        settingsCard("模块自选", subtitle: "关掉的栏目不会出现在侧栏、日报和语音里") {
            ForEach(groupedModules, id: \.0) { group, entries in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(PlanetTheme.muted)
                    ForEach(entries) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(PlanetTheme.category(entry.id))
                                .frame(width: 18)
                            Text(entry.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PlanetTheme.ink)
                            Spacer()
                            Button {
                                store.toggleBroadcastModule(entry.id)
                            } label: {
                                Text(store.broadcastModuleIDs.contains(entry.id) ? "播报中" : "不播报")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(
                                        store.broadcastModuleIDs.contains(entry.id)
                                            ? PlanetTheme.accent : PlanetTheme.muted
                                    )
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(PlanetTheme.selection, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!store.enabledModuleIDs.contains(entry.id))
                            Toggle("", isOn: Binding(
                                get: { store.enabledModuleIDs.contains(entry.id) },
                                set: { _ in store.toggleModule(entry.id) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            Text("提示：右侧「播报中」只影响语音，不影响日报里是否显示。")
                .font(.system(size: 10))
                .foregroundStyle(PlanetTheme.muted)
        }
    }

    // MARK: 语音播报

    private var broadcastSection: some View {
        settingsCard("语音播报", subtitle: "只播勾选的重点栏目；羊毛与免费额度不进口播") {
            Stepper("每个栏目最多 \(store.broadcastMaxItems) 条", value: $store.broadcastMaxItems, in: 1...6)
                .font(.system(size: 12))
                .foregroundStyle(PlanetTheme.ink)
            Divider().background(PlanetTheme.rule)
            Toggle("播报开头念天气", isOn: $store.includeWeatherInBroadcast)
            Toggle("播报里带一句全网热榜", isOn: $store.includeHotTopicsInBroadcast)
            Toggle("播报里加一段赛事比分", isOn: $store.includeSportsInBroadcast)
            Text("节目结构：开场 → 今日重点 → 热点背景 → 勾选栏目 → 收尾")
                .font(.system(size: 10))
                .foregroundStyle(PlanetTheme.muted)
        }
        .foregroundStyle(PlanetTheme.ink)
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: 皮肤

    private var skinSection: some View {
        settingsCard("皮肤", subtitle: "换配色不改变排版，随时可切回") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(PlanetSkin.allCases) { skin in
                    Button {
                        store.skin = skin.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PlanetTheme.color(skin.palette.canvas.0, skin.palette.canvas.1))
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(PlanetTheme.color(skin.palette.ink.0, skin.palette.ink.1))
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(PlanetTheme.color(skin.palette.accent.0, skin.palette.accent.1))
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(PlanetTheme.color(skin.palette.muted.0, skin.palette.muted.1))
                                        .frame(height: 3)
                                }
                                .padding(10)
                            }
                            .frame(height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        store.skin == skin.rawValue ? PlanetTheme.accent : PlanetTheme.rule,
                                        lineWidth: store.skin == skin.rawValue ? 2 : 1
                                    )
                            )
                            Text(skin.title)
                                .font(.system(size: 10, weight: store.skin == skin.rawValue ? .semibold : .regular))
                                .foregroundStyle(PlanetTheme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let current = PlanetSkin(rawValue: store.skin) {
                Text(current.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(PlanetTheme.muted)
            }
        }
    }

    // MARK: 天气

    private var weatherSection: some View {
        settingsCard("天气", subtitle: "显示在报头，并决定播报开头的天气播报") {
            Toggle("启用天气", isOn: $store.weatherEnabled)
            Divider().background(PlanetTheme.rule)
            HStack(spacing: 10) {
                Text("城市")
                    .frame(width: 48, alignment: .leading)
                TextField("例如 杭州富阳", text: $form.cityInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitWeather)
            }
            HStack(spacing: 10) {
                Text("经纬度")
                    .frame(width: 48, alignment: .leading)
                TextField("纬度", text: $form.latInput)
                    .textFieldStyle(.roundedBorder)
                TextField("经度", text: $form.lonInput)
                    .textFieldStyle(.roundedBorder)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(cityPresets, id: \.0) { name, lat, lon in
                    Button(name) {
                        form.cityInput = name
                        form.latInput = String(lat)
                        form.lonInput = String(lon)
                        commitWeather()
                        store.loadWeather()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 10))
                }
            }
        }
        .foregroundStyle(PlanetTheme.ink)
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: 外观与其它

    private var appearanceSection: some View {
        settingsCard("外观与版块", subtitle: "深浅模式、热榜与其它可选版块") {
            Picker("深浅模式", selection: $store.appearanceMode) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented)
            Divider().background(PlanetTheme.rule)
            Toggle("显示热榜速览", isOn: $store.showHotlists)
            Toggle("显示赛事比分板", isOn: $store.showSportsBoard)
            Toggle("显示今日专题", isOn: $store.showTopic)
            Toggle("显示机会信号", isOn: $store.showOpportunities)
        }
        .foregroundStyle(PlanetTheme.ink)
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: 通用卡片

    private func settingsCard<Content: View>(
        _ title: String, subtitle: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PlanetTheme.ink)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(PlanetTheme.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .background(PlanetTheme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PlanetTheme.rule, lineWidth: 0.5)
            )
        }
    }

    private func commitWeather() {
        let trimmed = form.cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
        store.weatherCity = trimmed.isEmpty ? "杭州富阳" : trimmed
        if let lat = Double(form.latInput) { store.weatherLatitude = lat }
        if let lon = Double(form.lonInput) { store.weatherLongitude = lon }
    }
}
