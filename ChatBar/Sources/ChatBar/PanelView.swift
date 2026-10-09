import AppKit
import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published var focusNonce = 0
}

struct PanelView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var state: PanelState
    let onOpen: (ChatItem) -> Void
    @FocusState private var searchFocused: Bool

    static func filter(_ items: [ChatItem], _ query: String) -> [ChatItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let hay = (item.title + " " + item.source.label).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        let results = Self.filter(store.items, state.query)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Найти чат…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($searchFocused)
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider()

            if results.isEmpty {
                Text(store.items.isEmpty ? "Загружаю чаты…" : "Ничего не найдено")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                                ChatRow(item: item, selected: idx == state.selection)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpen(item) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: state.selection) { _, new in
                        if results.indices.contains(new) { proxy.scrollTo(results[new].id) }
                    }
                }
            }

            if let err = store.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(2).padding(8)
            }
        }
        .frame(width: 680, height: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: state.query) { _, _ in state.selection = 0 }
        .onChange(of: state.focusNonce) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }
}

struct ChatRow: View {
    let item: ChatItem
    let selected: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.icon(for: item.source))
                .resizable()
                .frame(width: 22, height: 22)
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(item.source.label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(item.updated > 0 ? Self.relative.localizedString(for: item.updatedDate, relativeTo: Date()) : "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for source: ChatSource) -> NSImage {
        let path = source.appPath
        if let img = cache[path] { return img }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache[path] = img
        return img
    }
}
