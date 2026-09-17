import AppKit
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case clipboard = "剪贴板"
    case screenshots = "截图"
    var id: String { rawValue }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case clipboard = "剪贴板"
    case mirror = "显示器镜像"
    var id: String { rawValue }
}

struct HistoryPanelView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var pasteService: PasteService
    let onPaste: (HistoryItem) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    @ObservedObject var displayStore: DisplayStore
    let onTabChange: (PanelTab) -> Void

    @State private var query = ""
    @State private var filter: HistoryFilter = .all
    @State private var selectedID: HistoryItem.ID?
    @State private var tab: PanelTab = .clipboard
    @FocusState private var searchFocused: Bool

    private var filteredItems: [HistoryItem] {
        store.items.filter { item in
            let filterMatches = switch filter {
            case .all: true
            case .clipboard: item.kind != .screenshot
            case .screenshots: item.kind == .screenshot
            }
            let queryMatches = query.isEmpty || item.searchableText.localizedCaseInsensitiveContains(query)
            return filterMatches && queryMatches
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            if tab == .clipboard {
                header
                Divider()
                if filteredItems.isEmpty { emptyState } else { historyList }
                Divider()
                footer
            } else {
                MirrorTabView(store: displayStore)
            }
        }
        .frame(minWidth: 700, minHeight: 540)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
        .onAppear { selectFirstAndFocus() }
        .onReceive(NotificationCenter.default.publisher(for: .focusHistorySearch)) { _ in selectFirstAndFocus() }
        .onReceive(NotificationCenter.default.publisher(for: .showMirrorTab)) { _ in tab = .mirror }
        .onChange(of: tab) { onTabChange($0) }
        .onReceive(NotificationCenter.default.publisher(for: .moveHistorySelectionUp)) { _ in moveSelection(by: -1) }
        .onReceive(NotificationCenter.default.publisher(for: .moveHistorySelectionDown)) { _ in moveSelection(by: 1) }
        .onReceive(NotificationCenter.default.publisher(for: .pasteHistorySelection)) { _ in pasteSelected() }
        .onReceive(NotificationCenter.default.publisher(for: .deleteHistorySelection)) { _ in deleteSelected() }
        .onChange(of: filteredItems) { newValue in
            if !newValue.contains(where: { $0.id == selectedID }) { selectedID = newValue.first?.id }
        }
        .onExitCommand(perform: onClose)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 285)
            Spacer()
            if tab == .mirror {
                Circle().fill(displayStore.isMirroring ? .green : .secondary.opacity(0.35)).frame(width: 7, height: 7)
                Text(displayStore.isMirroring
                     ? "镜像中"
                     : (displayStore.displays.count < 2 ? "未检测到外接显示器" : "扩展显示模式"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                TextField("搜索剪贴板与截图", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium))
                    .focused($searchFocused)
                    .onSubmit { pasteSelected() }
                Text("⌘ ⇧ V")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15).frame(height: 56)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(searchFocused ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 2))

            HStack {
                Picker("", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 285)
                Spacer()
                Text("↑↓ 选择").foregroundStyle(.secondary)
                Text("↩ 复制").foregroundStyle(.secondary)
                Text("⌫ 删除").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(18)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedID) {
                ForEach(groupedItems) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            HistoryRow(item: item, isSelected: item.id == selectedID)
                                .tag(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedID = item.id }
                                .onTapGesture(count: 2) { onPaste(item) }
                                .contextMenu {
                                    Button(item.isPinned ? "取消固定" : "固定") { store.togglePinned(item) }
                                    Button("删除", role: .destructive) { store.delete(item) }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedID) { id in if let id { proxy.scrollTo(id) } }
            .onDeleteCommand { deleteSelected() }
        }
    }

    private var groupedItems: [HistorySection] {
        let calendar = Calendar.current
        var groups: [HistorySection] = []
        for item in filteredItems {
            let label = calendar.isDateInToday(item.createdAt) ? "今天" : calendar.isDateInYesterday(item.createdAt) ? "昨天" : item.createdAt.formatted(.dateTime.month().day())
            if groups.last?.title == label { groups[groups.count - 1].items.append(item) } else { groups.append(HistorySection(title: label, items: [item])) }
        }
        return groups
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: filter == .screenshots ? "photo.on.rectangle" : "clipboard")
                .font(.system(size: 38)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? "历史记录会出现在这里" : "没有匹配的记录").font(.headline)
            Text(query.isEmpty ? "复制文字、图片，或在系统中截一张图试试。" : "换个关键词或筛选条件。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text("正在记录").foregroundStyle(.secondary)
            Spacer()
            if let notice = pasteService.notice { Text(notice).foregroundStyle(.orange) }
            Text("复制后回到原应用，按 ⌘V 粘贴").foregroundStyle(.tertiary)
        }
        .font(.system(size: 12)).padding(.horizontal, 18).frame(height: 40)
    }

    private func selectFirstAndFocus() {
        query = ""
        selectedID = filteredItems.first?.id
        DispatchQueue.main.async { searchFocused = true }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let index = selectedID.flatMap { id in filteredItems.firstIndex { $0.id == id } } ?? 0
        selectedID = filteredItems[min(max(index + offset, 0), filteredItems.count - 1)].id
    }

    private func pasteSelected() {
        guard let item = filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first else { return }
        onPaste(item)
    }

    private func deleteSelected() {
        guard let item = filteredItems.first(where: { $0.id == selectedID }) else { return }
        store.delete(item)
    }
}

private struct HistorySection: Identifiable {
    let title: String
    var items: [HistoryItem]
    var id: String { title }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            thumbnail.frame(width: 96, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.displayTitle).font(.system(size: 15, weight: .medium)).lineLimit(2)
                    if item.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 6) {
                    Text(item.kind.title)
                    if !item.detailText.isEmpty { Text("·"); Text(item.detailText) }
                    Text("·"); Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isSelected {
                Text("回车复制").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Color.accentColor, in: Capsule())
            }
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = item.image {
            Image(nsImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.09))
                .overlay(Image(systemName: item.kind.symbol).font(.system(size: 22)).foregroundStyle(Color.accentColor))
        }
    }
}
