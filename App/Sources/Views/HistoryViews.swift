import OJADKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(Library.self) private var library
    @Query(sort: \HistoryEntry.lastSearchedAt, order: .reverse) private var history: [HistoryEntry]
    @State private var confirmingClear = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if history.isEmpty {
                    ContentUnavailableView("没有查询记录", systemImage: "clock", description: Text("查过的单词会出现在这里。"))
                } else {
                    List {
                        ForEach(history) { item in
                            // Value-based so the list re-sorting (opening a query bumps
                            // its timestamp) doesn't disturb the pushed screen.
                            DeletableHistoryRow(item: item) { path.append(SearchQuery(text: item.query)) }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(history[index]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("历史")
            .appDestinations()
            .toolbar {
                if !history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("全部清除", role: .destructive) { confirmingClear = true }
                            .tint(.red)
                    }
                }
            }
            .confirmationDialog("清除全部查询记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("清除全部记录", role: .destructive) { try? library.clearHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("共 \(history.count) 条。收藏不受影响。")
            }
        }
    }
}

/// A history row that opens its query, with an ✕ at the far right that removes just
/// this entry. Swipe-to-delete still works on the row.
struct DeletableHistoryRow: View {
    let item: HistoryEntry
    let open: () -> Void
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HistoryRow(item: item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { try? library.removeHistory(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除「\(item.query)」")
        }
    }
}
