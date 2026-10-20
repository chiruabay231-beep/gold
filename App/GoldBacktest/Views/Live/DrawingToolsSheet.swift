import SwiftUI

/// Favourite drawing tools, kept as a comma-separated list of raw values.
enum DrawingFavorites {
    static let key = "drawing.favorites"
    static let onChartKey = "drawing.favoritesOnChart"
    static let defaultText = [DrawingTool.trendLine, .horizontalLine, .fibRetracement, .longPosition, .shortPosition,
                              .rectangle, .text].map(\.rawValue).joined(separator: ",")

    static func decode(_ text: String) -> [DrawingTool] {
        text.split(separator: ",").compactMap { DrawingTool(rawValue: String($0)) }
    }

    static func toggled(_ tool: DrawingTool, in text: String) -> String {
        var tools = decode(text)
        if let index = tools.firstIndex(of: tool) { tools.remove(at: index) } else { tools.append(tool) }
        // Keep the order of the tools sheet.
        let order = DrawingTool.categories.flatMap(\.tools)
        return tools.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            .map(\.rawValue).joined(separator: ",")
    }
}

/// "Bản vẽ": every drawing tool by section, like TradingView's sheet:
/// Favourites / all / one section, search, ☆ to favourite.
struct DrawingToolsSheet: View {
    let activeTool: DrawingTool?
    /// Thước ngắm (crosshair) mode of the chart.
    @Binding var crosshair: Bool
    var onPick: (DrawingTool) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(DrawingFavorites.key) private var favoritesText = DrawingFavorites.defaultText
    @AppStorage(DrawingFavorites.onChartKey) private var showOnChart = true
    @AppStorage("drawing.sheetTab") private var tab = Self.favoritesTab
    @State private var query = ""

    private static let favoritesTab = "Yêu thích"
    private static let allTab = "Tất cả"
    private var tabs: [String] { [Self.favoritesTab, Self.allTab] + DrawingTool.categories.map(\.title) }
    private var favorites: [DrawingTool] { DrawingFavorites.decode(favoritesText) }

    /// Sections shown for the current tab or search.
    private var sections: [DrawingTool.Category] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return DrawingTool.categories.compactMap { category in
            let tools = category.tools.filter { tool in
                if !q.isEmpty {
                    return tool.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                        || category.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
                switch tab {
                case Self.favoritesTab: return favorites.contains(tool)
                case Self.allTab: return true
                default: return category.title == tab
                }
            }
            return tools.isEmpty ? nil : DrawingTool.Category(title: category.title, tools: tools)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.self) { name in
                            Button { tab = name } label: {
                                Text(name)
                                    .font(.system(size: 16, weight: tab == name ? .semibold : .regular))
                                    .foregroundColor(tab == name ? .primary : .secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(tab == name ? Color(.secondarySystemBackground) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .opacity(query.isEmpty ? 1 : 0.4)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if query.isEmpty, tab == Self.favoritesTab || tab == Self.allTab {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("CON TRỎ").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                    cursorTile("Mũi tên", "cursorarrow", selected: !crosshair) { crosshair = false }
                                    cursorTile("Thước ngắm", "plus.viewfinder", selected: crosshair) { crosshair = true }
                                }
                            }
                        }
                        if sections.isEmpty {
                            Text(query.isEmpty ? "Chưa có công cụ yêu thích. Bấm ☆ trên một công cụ ở tab Tất cả để thêm."
                                 : "Không tìm thấy công cụ")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 20)
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title.uppercased())
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                    ForEach(section.tools) { tile($0) }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                Divider()
                Toggle(isOn: $showOnChart) {
                    Label("Hiển thị mục yêu thích trên Biểu đồ", systemImage: "star.square.on.square")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm kiếm")
            .navigationTitle("Bản vẽ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func cursorTile(_ title: String, _ image: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: image).font(.system(size: 24)).frame(height: 30)
                Text(title).font(.system(size: 13))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ tool: DrawingTool) -> some View {
        let favorite = favorites.contains(tool)
        let selected = tool == activeTool
        return Button {
            onPick(tool)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 24))
                    .frame(height: 30)
                Text(tool.title)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.horizontal, 4)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Button {
                    favoritesText = DrawingFavorites.toggled(tool, in: favoritesText)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundColor(favorite ? .orange : .secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Favourite tools in a strip on the chart (Bản vẽ → Hiển thị mục yêu thích trên Biểu đồ).
struct FavoriteToolsBar: View {
    @Binding var activeTool: DrawingTool?
    @Binding var crosshair: Bool
    let theme: ChartTheme
    var onMore: () -> Void

    @AppStorage(DrawingFavorites.key) private var favoritesText = DrawingFavorites.defaultText

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Thước ngắm: the crosshair only shows while this is on.
                Button { crosshair.toggle() } label: {
                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: 15))
                        .frame(width: 34, height: 32)
                        .foregroundColor(crosshair ? .white : theme.primaryText)
                        .background(crosshair ? theme.accent : .clear, in: .rect(cornerRadius: 7))
                }
                .accessibilityLabel("Thước ngắm")
                Divider().frame(height: 20)
                ForEach(DrawingFavorites.decode(favoritesText)) { tool in
                    Button { activeTool = activeTool == tool ? nil : tool } label: {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 15))
                            .frame(width: 34, height: 32)
                            .foregroundColor(activeTool == tool ? .white : theme.primaryText)
                            .background(activeTool == tool ? theme.accent : .clear, in: .rect(cornerRadius: 7))
                    }
                    .accessibilityLabel(tool.title)
                }
                Button(action: onMore) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .foregroundColor(theme.text)
                }
                .accessibilityLabel("Tất cả công cụ vẽ")
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: 300)
        .fixedSize(horizontal: true, vertical: false)
        .background(theme.background.opacity(0.95), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.grid, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
