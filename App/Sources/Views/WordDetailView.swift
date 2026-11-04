import OJADKit
import SwiftData
import SwiftUI

struct WordDetailView: View {
    let entry: WordEntry
    @Environment(Library.self) private var library
    @Query private var favorites: [FavoriteWord]
    @State private var examples: LoadState<[ExampleSentence]> = .loading

    init(entry: WordEntry) {
        self.entry = entry
        let id = entry.id
        _favorites = Query(filter: #Predicate<FavoriteWord> { $0.wordID == id })
    }

    private var isFavorite: Bool { !favorites.isEmpty }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.headword).font(.title2.bold())
                    Text(entry.category.displayName).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("活用形") {
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
        .task { await loadExamples(refresh: false) }
    }

    @ViewBuilder
    private var examplesSection: some View {
        Section {
            switch examples {
            case .loading:
                HStack {
                    ProgressView()
                    Text("正在加载例句…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).foregroundStyle(.secondary)
                    Button("重试") { Task { await loadExamples(refresh: true) } }
                }
            case .loaded(let sentences) where sentences.isEmpty:
                Text("Tatoeba 中没有找到包含「\(entry.exampleSearchTerm)」的例句。")
                    .foregroundStyle(.secondary)
            case .loaded(let sentences):
                ForEach(sentences) { sentence in
                    NavigationLink(value: sentence) {
                        ExampleSentenceRow(sentence: sentence)
                    }
                }
            }
        } header: {
            Text("例句")
        } footer: {
            Text("例句来自 Tatoeba（CC BY 2.0 FR）。点开一句可查看スズキクン分析的语调曲线。")
        }
    }

    private func loadExamples(refresh: Bool) async {
        if case .loaded = examples, !refresh { return }
        if refresh { examples = .loading }
        do {
            examples = .loaded(try await library.exampleSentences(for: entry, refresh: refresh))
        } catch {
            examples = .failed(error.userMessage)
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
