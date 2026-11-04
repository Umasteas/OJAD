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
                            // Value-based so the list re-sorting (opening a query bumps
                            // its timestamp) doesn't disturb the pushed screen.
                            NavigationLink(value: SearchQuery(text: item.query)) {
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

extension OfflineDictionary {
    /// `115893 词 · JMdict 3.6.2 2026-11-02`
    var summary: String {
        var parts = [metadata["words"].map { "\($0) 词" } ?? ""]
        if let jmdict = metadata["jmdict"] { parts.append("JMdict \(jmdict)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
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
                Section {
                    Link(destination: URL(string: "https://github.com/mifunetoshiro/kanjium")!) {
                        LabeledContent("Kanjium", value: "CC BY-SA 4.0")
                    }
                    Text("辞書形重音与词频来自 Kanjium。The pitch accent notation, verb particle data, phonetics, homonyms and other additions or modifications to EDICT, KANJIDIC or KRADFILE were provided by Uros O. through his free database.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://www.edrdg.org/edrdg/licence.html")!) {
                        LabeledContent("JMdict", value: "CC BY-SA 4.0")
                    }
                    Text("词条、词性与英文释义来自 Electronic Dictionary Research and Development Group 的 JMdict（经 jmdict-simplified 转换）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://tatoeba.org")!) {
                        LabeledContent("Tatoeba", value: "CC BY 2.0 FR")
                    }
                    Text("例句及其翻译来自 Tatoeba，作者见各例句页面。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let dictionary = library.dictionary {
                        LabeledContent("离线词典", value: dictionary.summary)
                    }
                } header: {
                    Text("离线数据")
                } footer: {
                    Text("活用形的重音由本 App 按规则从辞書形重音推导，不是 OJAD 的原始数据。")
                }

                Section("在线功能（可选）") {
                    Link(destination: URL(string: "https://www.gavo.t.u-tokyo.ac.jp/ojad/")!) {
                        LabeledContent("OJAD", value: "東京大学 峯松研究室・齋藤研究室")
                    }
                    Text("「在线查询 OJAD」和スズキクン语调分析会请求 OJAD（オンライン日本語アクセント辞書）。依照其使用条款，本 App 仅供个人学习，不使用任何音频或合成语音。")
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
                    Text("在线查过的结果会保存在本机，以减少对 OJAD 和 Tatoeba 的请求。收藏、历史和离线词典不受影响。")
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
