import OJADKit
import SwiftData
import SwiftUI

struct SearchView: View {
    @Query(sort: \HistoryEntry.lastSearchedAt, order: .reverse) private var history: [HistoryEntry]
    @State private var text = ""
    @State private var submitted: String?

    var body: some View {
        NavigationStack {
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
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "单词（漢字・かな）")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { submit(text) }
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty { submitted = nil }
            }
        }
    }

    private func submit(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        text = query
        submitted = query
    }

    @ViewBuilder
    private var recent: some View {
        if history.isEmpty {
            ContentUnavailableView(
                "查一个单词",
                systemImage: "waveform.path",
                description: Text("输入辞書形，例如「食べる」「高い」「学校」，查看各活用形的重音和音高曲线。")
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

/// Loads and lists the OJAD entries for one query.
struct SearchResultsView: View {
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
                    "没有找到「\(query)」",
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
        .task { await load(refresh: false) }
    }

    private func load(refresh: Bool) async {
        if case .loaded = state, !refresh { return }
        do {
            state = .loaded(try await library.search(query, refresh: refresh))
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

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: WordEntry.self) { WordDetailView(entry: $0) }
            .navigationDestination(for: ExampleSentence.self) { SentenceDetailView(sentence: $0) }
            .navigationDestination(for: SearchQuery.self) { query in
                SearchResultsView(query: query.text)
                    .navigationTitle(query.text)
            }
    }
}
