import OJADKit
import SwiftData
import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(Library.self) private var library
    @Query(sort: \HistoryEntry.lastSearchedAt, order: .reverse) private var history: [HistoryEntry]
    @State private var text = ""
    @State private var submitted: String?
    @State private var suggestions: [DictionaryWord] = []
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let submitted {
                    SearchResultsView(query: submitted)
                        .id(submitted)
                } else {
                    recent
                }
            }
            .navigationTitle("查询")
            .appDestinations()
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "漢字・かな・romaji")
            .searchSuggestions {
                ForEach(suggestions) { word in
                    Button { open(word) } label: {
                        SuggestionRow(word: word)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("suggestion")
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { submit(text) }
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty { submitted = nil }
            }
            .task(id: text) { await updateSuggestions() }
        }
    }

    /// Waits for a pause in typing; each keystroke cancels the previous task.
    private func updateSuggestions() async {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != submitted else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let words = await library.suggestions(for: typed)
        guard !Task.isCancelled else { return }
        suggestions = words
    }

    private func submit(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        suggestions = []
        text = query
        submitted = query
    }

    private func open(_ word: DictionaryWord) {
        submit(word.written)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        path.append(word.entry)
    }

    @ViewBuilder
    private var recent: some View {
        if history.isEmpty {
            ContentUnavailableView(
                "查一个单词",
                systemImage: "waveform.path",
                description: Text("输入漢字、かな或罗马字（例如 tabe），从候选词中选一个，查看各活用形的重音和音高曲线。无需联网。")
            )
        } else {
            List {
                Section("最近查询") {
                    ForEach(history.prefix(20)) { item in
                        Button { submit(item.query) } label: {
                            HistoryRow(item: item)
                        }
                        .tint(.primary)
                    }
                }
            }
        }
    }
}

/// One autocomplete candidate: spelling, accented reading and a short gloss.
struct SuggestionRow: View {
    let word: DictionaryWord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.written).font(.body.weight(.semibold))
                Text(word.notation).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(word.wordClass.category.displayName).font(.caption2).foregroundStyle(.tertiary)
            }
            if let gloss = word.gloss {
                Text(gloss).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct HistoryRow: View {
    let item: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.query).font(.headline)
            if !item.summary.isEmpty {
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Lists the offline dictionary's entries for one query, with OJAD itself one tap away.
struct SearchResultsView: View {
    let query: String
    @Environment(Library.self) private var library
    @State private var state: LoadState<[WordEntry]> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("查询失败", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded(let entries) where entries.isEmpty:
                ContentUnavailableView {
                    Label("离线词典中没有「\(query)」", systemImage: "magnifyingglass")
                } description: {
                    Text("试试辞書形或其他写法（漢字／かな），或者在线查询 OJAD。")
                } actions: {
                    NavigationLink("在线查询 OJAD", value: OnlineQuery(text: query))
                }
            case .loaded(let entries):
                List {
                    Section {
                        ForEach(entries) { entry in
                            NavigationLink(value: entry) {
                                WordRow(entry: entry)
                            }
                        }
                    }
                    if library.dictionary == nil {
                        Section {
                            Label("离线词典没有加载，以上是 OJAD 的在线结果。详情见「关于 → 词典状态」。", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Section {
                            NavigationLink(value: OnlineQuery(text: query)) {
                                Label("在线查询 OJAD", systemImage: "globe")
                            }
                        } footer: {
                            Text("离线结果由词典数据推导。想和 OJAD 原站核对时再在线查询（需联网）。")
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        if case .loaded = state { return }
        do {
            state = .loaded(try await library.search(query))
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

/// OJAD's own result page for a query, fetched live and cached.
struct OnlineResultsView: View {
    let query: String
    @Environment(Library.self) private var library
    @State private var state: LoadState<[WordEntry]> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("正在查询 OJAD…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("查询失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        state = .loading
                        Task { await load(refresh: true) }
                    }
                }
            case .loaded(let entries) where entries.isEmpty:
                ContentUnavailableView(
                    "OJAD 中没有找到「\(query)」",
                    systemImage: "magnifyingglass",
                    description: Text("OJAD 主要收录教材词汇。试试辞書形或其他写法（漢字／かな）。")
                )
            case .loaded(let entries):
                List(entries) { entry in
                    NavigationLink(value: entry) {
                        WordRow(entry: entry)
                    }
                }
                .refreshable { await load(refresh: true) }
            }
        }
        .navigationTitle("OJAD：\(query)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(refresh: false) }
    }

    private func load(refresh: Bool) async {
        if case .loaded = state, !refresh { return }
        do {
            state = .loaded(try await library.searchOnline(query, refresh: refresh))
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

struct WordRow: View {
    let entry: WordEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.headword).font(.headline)
                Spacer()
                Text(entry.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reading = entry.dictionaryReading {
                PitchReadingView(reading: reading, moraWidth: 20, curveHeight: 22)
            }
        }
        .padding(.vertical, 4)
    }
}

enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

extension Error {
    var userMessage: String {
        switch self as Error {
        case OJADError.invalidQuery, TatoebaError.invalidQuery:
            "请输入要查询的内容。"
        case OJADError.httpStatus(let code), TatoebaError.httpStatus(let code):
            "服务器返回了错误（HTTP \(code)），请稍后再试。"
        case OJADError.unexpectedPage:
            "OJAD 返回的页面无法识别，可能是网站改版了。"
        case TatoebaError.unexpectedResponse:
            "Tatoeba 返回的数据无法识别。"
        case let error as URLError where error.code == .notConnectedToInternet:
            "没有网络连接。"
        case let error as URLError where error.code == .timedOut:
            "请求超时，请稍后再试。"
        default:
            localizedDescription
        }
    }
}

struct SearchQuery: Hashable {
    let text: String
}

struct OnlineQuery: Hashable {
    let text: String
}

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: WordEntry.self) { WordDetailView(entry: $0) }
            .navigationDestination(for: ExampleSentence.self) { SentenceDetailView(sentence: $0) }
            .navigationDestination(for: SearchQuery.self) { query in
                SearchResultsView(query: query.text)
                    .navigationTitle(query.text)
            }
            .navigationDestination(for: OnlineQuery.self) { OnlineResultsView(query: $0.text) }
    }
}
