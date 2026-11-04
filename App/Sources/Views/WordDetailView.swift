import OJADKit
import SwiftData
import SwiftUI

struct WordDetailView: View {
    let entry: WordEntry
    @Environment(Library.self) private var library
    @Query private var favorites: [FavoriteWord]
    @State private var word: DictionaryWord?
    @State private var offlineExamples: [ExampleSentence] = []
    /// nil until the user asks Tatoeba for more.
    @State private var onlineExamples: LoadState<[ExampleSentence]>?

    init(entry: WordEntry) {
        self.entry = entry
        _favorites = Query(filter: FavoriteWord.matching(entry))
    }

    private var isFavorite: Bool { !favorites.isEmpty }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.headword).font(.title2.bold())
                    Text(entry.category.displayName).font(.subheadline).foregroundStyle(.secondary)
                    if let gloss = word?.gloss {
                        Text(gloss).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(entry.forms, id: \.kind) { form in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(form.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(form.readings.enumerated()), id: \.offset) { _, reading in
                            ScrollingPitchReading(reading: reading)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if entry.isOffline {
                    NavigationLink(value: OnlineQuery(text: entry.exampleSearchTerm)) {
                        Label("在线核对 OJAD", systemImage: "globe")
                    }
                }
            } header: {
                Text("活用形")
            } footer: {
                if entry.isOffline {
                    Text("重音由离线词典（辞書形重音 + 活用规则）推导，个别词可能与 OJAD 略有不同。")
                }
            }

            examplesSection
        }
        .navigationTitle(entry.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    try? library.toggleFavorite(entry)
                } label: {
                    Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "star.fill" : "star")
                }
                .tint(isFavorite ? Color.yellow : nil)
            }
        }
        .task {
            word = library.dictionaryWord(for: entry)
            offlineExamples = library.offlineExamples(for: entry)
        }
    }

    @ViewBuilder
    private var examplesSection: some View {
        Section {
            ForEach(offlineExamples) { sentence in
                NavigationLink(value: sentence) {
                    ExampleSentenceRow(sentence: sentence)
                }
            }
            switch onlineExamples {
            case nil:
                if offlineExamples.isEmpty {
                    Text("离线词典中没有「\(entry.exampleSearchTerm)」的例句。").foregroundStyle(.secondary)
                }
                Button {
                    Task { await loadOnlineExamples(refresh: false) }
                } label: {
                    Label("在线加载更多例句（含中文翻译）", systemImage: "globe")
                }
            case .loading?:
                HStack {
                    ProgressView()
                    Text("正在加载例句…").foregroundStyle(.secondary)
                }
            case .failed(let message)?:
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).foregroundStyle(.secondary)
                    Button("重试") { Task { await loadOnlineExamples(refresh: true) } }
                }
            case .loaded(let sentences)?:
                let known = Set(offlineExamples.map(\.id))
                let more = sentences.filter { !known.contains($0.id) }
                if more.isEmpty {
                    Text("Tatoeba 中没有更多包含「\(entry.exampleSearchTerm)」的例句。").foregroundStyle(.secondary)
                }
                ForEach(more) { sentence in
                    NavigationLink(value: sentence) {
                        ExampleSentenceRow(sentence: sentence)
                    }
                }
            }
        } header: {
            Text("例句")
        } footer: {
            Text("例句来自 Tatoeba（CC BY 2.0 FR），离线例句经 JMdict 收录、附英文翻译。点开一句可在线请求スズキクン语调分析。")
        }
    }

    private func loadOnlineExamples(refresh: Bool) async {
        onlineExamples = .loading
        do {
            onlineExamples = .loaded(try await library.onlineExamples(for: entry, refresh: refresh))
        } catch {
            onlineExamples = .failed(error.userMessage)
        }
    }
}

struct ExampleSentenceRow: View {
    let sentence: ExampleSentence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sentence.text).font(.body)
            if let translation = sentence.preferredTranslation {
                Text(translation.text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
