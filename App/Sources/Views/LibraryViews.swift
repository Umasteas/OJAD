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
                        description: Text("在单词详情页点右上角的星标即可收藏。")
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

/// What the user can read out when search misbehaves on the phone: whether the
/// bundled dictionary opened, and how long the last lookups took.
struct DictionaryStatusSection: View {
    @Environment(Library.self) private var library
    @State private var testing = false

    var body: some View {
        let diagnostics = library.diagnostics
        Section {
            LabeledContent("状态", value: diagnostics.stateText)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dictionary-state")
            if diagnostics.state == .loaded {
                LabeledContent("词数", value: "\(diagnostics.words)")
                if let version = diagnostics.version {
                    LabeledContent("JMdict", value: version)
                }
                LabeledContent("文件", value: ByteCountFormatter.string(fromByteCount: Int64(diagnostics.fileSize), countStyle: .file))
                LabeledContent("打开耗时", value: diagnostics.openDuration.millisecondsText)
            }
            if let timing = diagnostics.lastSuggestion {
                LabeledContent("上次候选「\(timing.query)」", value: "\(timing.results) 个 · \(timing.milliseconds)")
            }
            if let timing = diagnostics.lastSearch {
                LabeledContent("上次查询「\(timing.query)」", value: "\(timing.results) 条 · \(timing.milliseconds)")
            }
            ForEach(Array(diagnostics.selfTest.enumerated()), id: \.offset) { _, timing in
                LabeledContent("自检「\(timing.query)」", value: "\(timing.results) · \(timing.milliseconds)")
            }
            if diagnostics.state == .loaded {
                Button(testing ? "正在自检…" : "运行自检") {
                    testing = true
                    Task {
                        await library.runSelfTest()
                        testing = false
                    }
                }
                .disabled(testing)
            }
        } header: {
            Text("词典状态")
        } footer: {
            Text("遇到问题时，请截图这一节。耗时是从输入到拿到结果的时间，正常应在几毫秒以内。")
        }
    }
}

extension DictionaryDiagnostics {
    var stateText: String {
        switch state {
        case .loaded: "已加载（离线）"
        case .missing: "未找到词典文件"
        case .failed(let message): "打开失败：\(message)"
        }
    }
}

struct AboutView: View {
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
                    Text("大部分例句及其英文、中文翻译来自 Tatoeba（2026-10-31 的数据），作者见 tatoeba.org 上的各例句页面。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://www.phontron.com/kftt/")!) {
                        LabeledContent("KFTT", value: "CC BY-SA 3.0")
                    }
                    Text("补充例句来自 Kyoto Free Translation Task：NICT「Wikipedia 日英京都関連文書対訳コーパス」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("数据来源")
                } footer: {
                    Text("本 App 完全离线，不发出任何网络请求。活用形的重音由本 App 按规则从辞書形重音推导，不是 OJAD 的原始数据。")
                }

                DictionaryStatusSection()

                Section {
                    Link(destination: URL(string: "https://www.gavo.t.u-tokyo.ac.jp/ojad/")!) {
                        LabeledContent("OJAD", value: "東京大学 峯松研究室・齋藤研究室")
                    }
                } header: {
                    Text("致谢")
                } footer: {
                    Text("界面和音高曲线仿照 OJAD（オンライン日本語アクセント辞書）。本 App 仅供个人学习，不使用任何音频或合成语音。")
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
