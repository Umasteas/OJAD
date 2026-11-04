import OJADKit
import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FavoriteWord.addedAt, order: .reverse) private var favorites: [FavoriteWord]

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏",
                        systemImage: "star",
                        description: Text("在单词详情页点右上角的星标即可收藏，收藏后无需联网也能查看。")
                    )
                } else {
                    List {
                        ForEach(favorites) { favorite in
                            if let entry = favorite.entry {
                                NavigationLink(value: entry) {
                                    WordRow(entry: entry)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(favorites[index]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("收藏")
            .appDestinations()
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(Library.self) private var library
    @Query(sort: \HistoryEntry.lastSearchedAt, order: .reverse) private var history: [HistoryEntry]
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    ContentUnavailableView("没有查询记录", systemImage: "clock", description: Text("查过的单词会出现在这里。"))
                } else {
                    List {
                        ForEach(history) { item in
                            NavigationLink {
                                SearchResultsView(query: item.query)
                                    .navigationTitle(item.query)
                            } label: {
                                HistoryRow(item: item)
                            }
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
                    Button("清空", role: .destructive) { confirmingClear = true }
                }
            }
            .confirmationDialog("清空全部查询记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { try? library.clearHistory() }
            }
        }
    }
}

struct AboutView: View {
    @Environment(Library.self) private var library
    @State private var cacheCleared = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("数据来源") {
                    Link(destination: URL(string: "https://www.gavo.t.u-tokyo.ac.jp/ojad/")!) {
                        LabeledContent("OJAD", value: "東京大学 峯松研究室・齋藤研究室")
                    }
                    Text("单词重音与スズキクン分析来自 OJAD（オンライン日本語アクセント辞書）。依照其使用条款，本 App 仅供个人学习，不使用任何音频或合成语音。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://tatoeba.org")!) {
                        LabeledContent("Tatoeba", value: "CC BY 2.0 FR")
                    }
                    Text("例句及其翻译来自 Tatoeba，作者见各例句页脚。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/scinfu/SwiftSoup")!) {
                        LabeledContent("SwiftSoup", value: "MIT")
                    }
                }

                Section {
                    Button(cacheCleared ? "缓存已清除" : "清除缓存") {
                        try? library.clearCache()
                        cacheCleared = true
                    }
                    .disabled(cacheCleared)
                } footer: {
                    Text("查过的结果会保存在本机，以减少对 OJAD 和 Tatoeba 的请求。收藏不受影响。")
                }

                Section {
                    LabeledContent("版本", value: version)
                    Link("源代码", destination: URL(string: "https://github.com/Umasteas/OJAD")!)
                }
            }
            .navigationTitle("关于")
        }
    }
}
