import OJADKit
import SwiftData
import SwiftUI

struct WordDetailView: View {
    let entry: WordEntry
    @Environment(Library.self) private var library
    @Query private var favorites: [FavoriteWord]
    @State private var word: DictionaryWord?
    /// nil until read from the dictionary (off the main thread, a few ms).
    @State private var examples: [SenseExamples]?

    init(entry: WordEntry) {
        self.entry = entry
        _favorites = Query(filter: FavoriteWord.matching(entry))
    }

    private var isFavorite: Bool { !favorites.isEmpty }

    private var conjugationGroups: [ConjugationGroup] { ConjugationGroup.groups(for: entry) }

    /// Wiktionary's Chinese that fits no single sense, else the first sense's.
    private var chineseSummary: String? {
        word?.chinese ?? examples?.lazy.compactMap { $0.sense?.chinese }.first
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.headword).font(.title2.bold())
                    Text(entry.category.displayName).font(.subheadline).foregroundStyle(.secondary)
                    if let gloss = word?.gloss {
                        Text(gloss).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if let chinese = chineseSummary {
                        Text(chinese).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                            .accessibilityIdentifier("chinese-summary")
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ConjugationGroupsView(groups: conjugationGroups)

                if entry.isOffline {
                    NavigationLink { AccentDerivationView() } label: {
                        Label("重音是怎样推导的", systemImage: "info.circle")
                    }
                }
            } header: {
                ConjugationHeader(groups: conjugationGroups)
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
            let details = await library.details(for: entry)
            word = details.word
            examples = SenseExamples.group(details.examples, senses: details.senses)
        }
    }

    @ViewBuilder
    private var examplesSection: some View {
        if let examples {
            let senseCount = examples.filter { $0.sense != nil }.count
            if examples.allSatisfy({ $0.examples.isEmpty }) {
                Section("释义与例句") {
                    ForEach(examples) { group in
                        if let sense = group.sense { SenseHeader(sense: sense, count: senseCount) }
                    }
                    Text("离线语料中没有「\(entry.exampleSearchTerm)」的例句。").foregroundStyle(.secondary)
                }
            } else {
                ForEach(examples) { group in
                    Section {
                        ForEach(group.examples) { ExampleSentenceRow(sentence: $0) }
                        if group.examples.isEmpty {
                            Text("此义项暂无例句").font(.footnote).foregroundStyle(.tertiary)
                        }
                    } header: {
                        if let sense = group.sense {
                            SenseHeader(sense: sense, count: senseCount)
                        } else {
                            Text("未标明义项的例句")
                        }
                    } footer: {
                        if group.id == examples.last?.id {
                            Text("例句来自 Tatoeba（CC BY 2.0 FR）和 KFTT（CC BY-SA 3.0），按 JMdict 义项归类。中文释义来自中文维基词典（CC BY-SA 4.0），标「同形词」的取自 CC-CEDICT（CC BY-SA 4.0）。")
                        }
                    }
                }
            }
        }
    }
}

/// `① to eat` and its Chinese `吃；吃喝，饮食` — numbered like JMdict; the number is left
/// out for single-sense words.
struct SenseHeader: View {
    let sense: WordSense
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count > 1 ? "\(Self.circled(sense.number)) \(sense.gloss)" : sense.gloss)
            if let chinese = sense.chinese {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(chinese)
                    if sense.chineseSource == .cedict {
                        GlossTag(text: "同形词")
                    }
                }
                .padding(.leading, count > 1 ? 20 : 0)
            }
        }
        .textCase(nil)
        .accessibilityIdentifier("sense-\(sense.number)")
    }

    static func circled(_ number: Int) -> String {
        (1...20).contains(number) ? String(Character(UnicodeScalar(0x2460 + number - 1)!)) : "(\(number))"
    }
}

struct ExampleSentenceRow: View {
    let sentence: ExampleSentence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sentence.japanese).font(.body).textSelection(.enabled)
            if let english = sentence.english {
                Text(english).font(.subheadline).foregroundStyle(.secondary)
            }
            if let chinese = sentence.chinese {
                Text(chinese).font(.subheadline).foregroundStyle(.secondary)
            }
            if let note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Says when the sense or the sentence itself was matched by a heuristic.
    private var note: String? {
        let source = sentence.source == .kftt ? "KFTT" : nil
        let basis: String? = switch sentence.basis {
        case .gloss: "义项按英译推测"
        case .text: "原文匹配，未经词典标注"
        case .tagged, .jmdict, .single, .unassigned: nil
        }
        let chinese = sentence.chinese != nil && sentence.chineseViaEnglish ? "中文译自英译" : nil
        let parts = [basis, chinese, source].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// How the conjugation table is made, and how often it agrees with OJAD.
struct AccentDerivationView: View {
    var body: some View {
        List {
            Section {
                Text("辞書形的重音来自 Kanjium，其余活用形由本 App 按 OJAD 的活用规则推导，完全离线，个别词可能与 OJAD 不同。")
            }
            Section("辞書形以外的活用形与 OJAD 原站对照（510 个词，2026-11-04 记录）") {
                LabeledContent("动词", value: "3522 / 3556 个活用形一致")
                LabeledContent("い形容词", value: "800 / 800 个活用形一致")
                LabeledContent("な形容词", value: "380 / 392 个活用形一致")
            }
        }
        .navigationTitle("重音推导")
        .navigationBarTitleDisplayMode(.inline)
    }
}
