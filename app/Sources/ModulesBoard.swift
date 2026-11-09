import SwiftUI
import AppKit

// MARK: - 今日栏目（速览页第一屏可见的模块卡片墙）
// 设计目标：模块不再只藏在侧栏里，也不再靠说明书式文案解释用法。
// 每张卡只做三件事：认出栏目、看到今天最值得读的三条、点进去。
// 裸 swiftc 构建不使用 @State 宏，交互状态统一用 ObservableObject。

struct ModuleTile: Identifiable {
    let id: String
    let name: String
    let icon: String
    let group: String
    let color: Color
    let count: Int
    let headlines: [String]
}

final class ModuleBoardHover: ObservableObject {
    @Published var isOn: Bool = false
}

final class ModuleBoardModel: ObservableObject {
    @Published var expanded: Bool = false
}

struct ModulesBoard: View {
    @EnvironmentObject private var store: DigestStore
    @StateObject private var model = ModuleBoardModel()

    /// 顺序跟随用户配置里的启用顺序：想让哪个栏目更靠前，直接在偏好设置里调。
    private var tiles: [ModuleTile] {
        var catalog: [String: ModuleEntry] = [:]
        for entry in store.moduleCatalog { catalog[entry.id] = entry }
        var categories: [String: DigestCategory] = [:]
        for category in store.digest?.categories ?? [] { categories[category.id] = category }

        var result: [ModuleTile] = []
        for id in store.enabledModuleIDs {
            guard let entry = catalog[id] else { continue }
            let items = categories[id]?.items ?? []
            result.append(ModuleTile(
                id: id,
                name: entry.name,
                icon: entry.icon,
                group: entry.group,
                color: PlanetTheme.category(id),
                count: items.count,
                headlines: Array(items.prefix(3).map { $0.title })
            ))
        }
        return result
    }

    private func open(_ id: String) {
        store.searchText = ""
        store.selectedCategoryID = id
    }

    private var totalCount: Int {
        tiles.reduce(0) { $0 + $1.count }
    }

    /// 首页默认只铺 6 张卡，避免把今日简报挤到页面最下方；其余一键展开。
    private var visibleTiles: [ModuleTile] {
        model.expanded ? tiles : Array(tiles.prefix(6))
    }

    /// 索引胶囊分两行铺满，全部可见；横向滚动条在 macOS 上很难藏干净，索性不用滚动。
    private var chipRows: [[ModuleTile]] {
        guard !tiles.isEmpty else { return [] }
        let half = (tiles.count + 1) / 2
        return [Array(tiles.prefix(half)), Array(tiles.dropFirst(half))]
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                kicker: "今日栏目",
                meta: "\(tiles.count) 个模块 · \(totalCount) 条中文资讯"
            ) {
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("DailyDigestOpenSettings"),
                        object: nil
                    )
                } label: {
                    HStack(spacing: 4) {
                        Text("管理栏目")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(PlanetTheme.secondary)
                }
                .buttonStyle(.plain)
                .help("增删栏目、换皮肤、改天气")
            }

            // 栏目索引：两行胶囊全部露出，没有横向滚动条；条数交给卡片右上角的徽标
            VStack(alignment: .leading, spacing: 8) {
                ForEach(chipRows.indices, id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(chipRows[row]) { tile in
                            ModuleChip(tile: tile) { open(tile.id) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                ],
                spacing: 14
            ) {
                ForEach(visibleTiles) { tile in
                    ModuleTileCard(tile: tile) { open(tile.id) }
                }
            }

            if tiles.count > 6 {
                Button {
                    model.expanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Text(model.expanded ? "收起栏目" : "展开全部 \(tiles.count) 个栏目")
                            .font(.system(size: 11.5, weight: .medium))
                        Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(PlanetTheme.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(PlanetTheme.paper))
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - 栏目索引胶囊

private struct ModuleChip: View {
    let tile: ModuleTile
    let action: () -> Void
    @StateObject private var hover = ModuleBoardHover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tile.color)
                    .frame(width: 5, height: 5)
                Text(tile.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(hover.isOn ? PlanetTheme.ink : PlanetTheme.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(PlanetTheme.paper))
            .overlay(
                Capsule().strokeBorder(
                    Color.primary.opacity(hover.isOn ? 0.17 : 0.075),
                    lineWidth: 0.7
                )
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .help("打开「\(tile.name)」")
    }
}

// MARK: - 栏目卡：色标图标 + 三条中文标题 + hover 抬升

struct ModuleTileCard: View {
    let tile: ModuleTile
    let action: () -> Void
    @StateObject private var hover = ModuleBoardHover()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tile.color.opacity(hover.isOn ? 0.22 : 0.13))
                        Image(systemName: tile.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tile.color)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(PlanetTheme.ink)
                            .lineLimit(1)
                        Text(tile.group)
                            .font(.system(size: 11))
                            .foregroundStyle(PlanetTheme.muted)
                    }

                    Spacer(minLength: 6)

                    // 条数徽标：卡片右上角的视觉落点，也避免「今日 N 条」在副标题里重复
                    HStack(spacing: 9) {
                        Text("\(tile.count) 条")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tile.color)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(tile.color.opacity(0.13)))
                            .fixedSize()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hover.isOn ? tile.color : PlanetTheme.muted)
                            .opacity(hover.isOn ? 1 : 0.5)
                    }
                }

                GradientRule(strength: 0.16)

                if tile.headlines.isEmpty {
                    Text("今天这个栏目还没有新条目")
                        .font(.system(size: 12))
                        .foregroundStyle(PlanetTheme.muted)
                        .frame(height: 72, alignment: .top)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(tile.headlines.enumerated()), id: \.offset) { index, title in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(tile.color.opacity(0.78))
                                    .fixedSize()
                                Text(title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(PlanetTheme.ink.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                    .frame(height: 72, alignment: .top)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .refinedCard(cornerRadius: 16)
        .onHover { hover.isOn = $0 }
        .help("打开「\(tile.name)」")
    }
}
