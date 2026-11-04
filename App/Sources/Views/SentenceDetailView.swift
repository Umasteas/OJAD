import OJADKit
import SwiftUI

/// An example sentence; on request, スズキクン's accent phrases redrawn as pitch curves.
struct SentenceDetailView: View {
    let sentence: ExampleSentence
    @Environment(Library.self) private var library
    /// nil until requested: スズキクン is OJAD's online analyzer.
    @State private var analysis: LoadState<SentenceAnalysis>?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(sentence.text).font(.title3).textSelection(.enabled)
                    ForEach(translations, id: \.id) { translation in
                        Text(translation.text).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Link(attribution, destination: sentence.url)
                    .font(.footnote)
            }

            Section {
                switch analysis {
                case nil:
                    Button {
                        Task { await load(refresh: false) }
                    } label: {
                        Label("在线请求スズキクン语调分析", systemImage: "waveform.path")
                    }
                case .loading?:
                    HStack {
                        ProgressView()
                        Text("正在请求スズキクン分析…").foregroundStyle(.secondary)
                    }
                case .failed(let message)?:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message).foregroundStyle(.secondary)
                        Button("重试") { Task { await load(refresh: true) } }
                    }
                case .loaded(let result)?:
                    ForEach(Array(result.sentences.joined().enumerated()), id: \.offset) { _, phrase in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phrase.text).font(.caption).foregroundStyle(.secondary)
                            ScrollingPitchReading(
                                reading: phrase.reading,
                                model: .phrase,
                                phraseIndex: phrase.phraseIndex,
                                isQuestion: phrase.isQuestion,
                                curveHeight: 48
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("语调（スズキクン）")
            } footer: {
                Text("需联网：句子会发送给 OJAD スズキクン 分析，结果在本机重绘并缓存，不使用任何合成语音。机器分析可能有误。")
            }
        }
        .navigationTitle("例句")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if analysis == nil, let cached = library.cachedAnalysis(of: sentence.text) {
                analysis = .loaded(cached)
            }
        }
    }

    private var attribution: String {
        var parts = ["Tatoeba #\(sentence.id)"]
        if let owner = sentence.owner { parts.append(owner) }
        parts.append(sentence.license ?? "CC BY 2.0 FR")
        let translators = translations.compactMap(\.owner)
        if !translators.isEmpty {
            parts.append("翻译：" + translators.joined(separator: "、"))
        }
        return parts.joined(separator: " · ")
    }

    /// Simplified Chinese and English, at most one of each.
    private var translations: [ExampleSentence.Translation] {
        var seen = Set<String>()
        let preferred = [sentence.preferredTranslation].compactMap { $0 } + sentence.translations
        return preferred.filter { seen.insert($0.lang).inserted }
    }

    private func load(refresh: Bool) async {
        analysis = .loading
        do {
            analysis = .loaded(try await library.analysis(of: sentence.text, refresh: refresh))
        } catch {
            analysis = .failed(error.userMessage)
        }
    }
}
