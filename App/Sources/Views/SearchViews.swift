import OJADKit
import SwiftData
import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(Library.self) private var library
    @Query(sort: \HistoryEntry.lastSearchedAt, order: .reverse) private var history: [HistoryEntry]
    @State private var text = ""
    @State private var submitted: String?
    @State private var suggestions: [SearchSuggestion] = []
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
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "漢字・かな・romaji・中文・English")
            .searchSuggestions {
                ForEach(suggestions) { suggestion in
                    Button { open(suggestion.word) } label: {
                        SuggestionRow(suggestion: suggestion)
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
                description: Text("输入漢字、かな或罗马字（例如 tabe），也可以输入中文或英文意思（例如「吃」或 eat），从候选词中选一个，查看各活用形的重音和音高曲线。无需联网。")
            )
        } else {
            List {
                Section("最近查询") {
                    ForEach(history.prefix(20)) { item in
                        DeletableHistoryRow(item: item) { submit(item.query) }
                    }
                }
            }
        }
    }
}

/// One autocomplete candidate: spelling, accented reading and a short gloss; for a word
/// found by meaning, the gloss that matched and which language it is in.
struct SuggestionRow: View {
    let suggestion: SearchSuggestion

    private var word: DictionaryWord { suggestion.word }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.written).font(.body.weight(.semibold))
                Text(word.notation).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(word.wordClass.category.displayName).font(.caption2).foregroundStyle(.tertiary)
            }
            switch suggestion {
            case .word(let word):
                if let gloss = word.gloss {
                    Text(gloss).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            case .meaning(let match):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    GlossTag(text: match.tag)
                    Text(match.gloss).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// A small grey label saying where a gloss comes from (`中文释义`, `经英文`).
struct GlossTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
    }
}

extension GlossMatch {
    /// Which gloss matched: the word's Chinese, its English, or English that CC-CEDICT
    /// translates as the typed Chinese (search only; the row shows the English).
    var tag: String {
        if viaEnglish { return "经英文" }
        return language == .chinese ? "中文释义" : "英文释义"
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

/// Lists the offline dictionary's entries for one query.
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
                    Text("试试辞書形或其他写法（漢字／かな）。")
                }
            case .loaded(let entries):
                List(entries) { entry in
                    NavigationLink(value: entry) {
                        WordRow(entry: entry)
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
        switch self {
        case is DictionaryUnavailable:
            "离线词典没有加载，详情见「关于 → 词典状态」。重新安装最新版通常可以解决。"
        default:
            localizedDescription
        }
    }
}

struct SearchQuery: Hashable {
    let text: String
}

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: WordEntry.self) { WordDetailView(entry: $0) }
            .navigationDestination(for: SearchQuery.self) { query in
                SearchResultsView(query: query.text)
                    .navigationTitle(query.text)
            }
    }
}
