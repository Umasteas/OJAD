import OJADKit
import SwiftUI

/// A reading drawn the way OJAD does: the pitch curve above, kana below with a line
/// over high morae and a red drop after the accent nucleus.
struct PitchReadingView: View {
    let reading: AccentedReading
    var model: FujisakiModel = .word
    var phraseIndex = 0
    var isQuestion = false
    var moraWidth: CGFloat = 24
    var curveHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PitchCurve(
                samples: model.contour(accent: reading.accentCommands, phraseIndex: phraseIndex, isQuestion: isQuestion),
                displayOffset: model.displayOffset,
                moraWidth: moraWidth
            )
            .frame(width: moraWidth * (CGFloat(reading.morae.count) + 0.3), height: curveHeight)

            HStack(spacing: 0) {
                ForEach(Array(reading.morae.enumerated()), id: \.offset) { _, mora in
                    MoraCell(mora: mora)
                        .frame(width: moraWidth)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.notation)
    }
}

struct PitchCurve: View {
    let samples: [PitchSample]
    let displayOffset: Double
    let moraWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let first = samples.first else { return }
            func point(_ sample: PitchSample) -> CGPoint {
                let y = (displayOffset - sample.level) * size.height
                return CGPoint(x: CGFloat(sample.position) * moraWidth, y: min(max(y, 1), size.height - 1))
            }
            var path = Path()
            path.move(to: point(first))
            for sample in samples.dropFirst() {
                path.addLine(to: point(sample))
            }
            context.stroke(
                path,
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

/// One kana mora with OJAD's marks: a line over it when high, red when it is the
/// accent nucleus, followed by a red drop.
struct MoraCell: View {
    let mora: Mora
    var font: Font = .title3
    /// Fill the width the parent gives (the curve's mora grid) rather than hugging the kana.
    var fillsWidth = true

    var body: some View {
        Text(mora.text)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .padding(.horizontal, fillsWidth ? 0 : 1)
            .padding(.top, 5)
            .overlay(alignment: .top) {
                if mora.isHigh {
                    Rectangle()
                        .fill(mora.isNucleus ? Color.red : Color.primary)
                        .frame(height: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if mora.isNucleus {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: 12)
                }
            }
    }
}

/// Horizontal scrolling for readings wider than the screen (long conjugations, phrases).
struct ScrollingPitchReading: View {
    let reading: AccentedReading
    var model: FujisakiModel = .word
    var phraseIndex = 0
    var isQuestion = false
    var curveHeight: CGFloat = 30

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            PitchReadingView(
                reading: reading,
                model: model,
                phraseIndex: phraseIndex,
                isQuestion: isQuestion,
                curveHeight: curveHeight
            )
            .padding(.vertical, 2)
        }
    }
}

extension WordCategory {
    var displayName: String {
        switch self {
        case .verb: "动词"
        case .iAdjective: "い形容词"
        case .naAdjective: "な形容词"
        case .noun: "名词"
        }
    }
}
