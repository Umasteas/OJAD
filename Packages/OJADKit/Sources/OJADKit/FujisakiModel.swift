import Foundation

/// One point of a pitch contour.
public struct PitchSample: Sendable, Hashable {
    /// Horizontal position in morae (0 = start of the first mora).
    public let position: Double
    /// F0-like level above the phrase baseline. Same scale for every curve drawn
    /// with one model, so curves of different forms are comparable side by side.
    public let level: Double

    public init(position: Double, level: Double) {
        self.position = position
        self.level = level
    }
}

/// The Fujisaki F0 model with the parameter presets OJAD uses for its curves.
///
/// Implemented from the published model (phrase command `Gp`, accent command `Ga`)
/// and OJAD's preset values, so curves look the same as on the site.
public struct FujisakiModel: Sendable {
    /// Lead time of the phrase command before the first mora, in ms.
    let start: Double
    /// Duration of one mora, in ms.
    let moraDuration: Double
    /// Phrase-command amplitude for the first, second and later phrases.
    let phraseAmplitudes: (Double, Double, Double)
    /// Accent amplitude for a falling (起伏) first accent, per phrase group.
    let fallingAmplitudes: (Double, Double, Double)
    /// Accent amplitude for a first accent that never falls (平板), per phrase group.
    let flatAmplitudes: (Double, Double, Double)
    let laterAccentAmplitude: Double
    let secondaryAccentAmplitude: Double
    let questionAmplitude: Double
    let accentDelay: Double
    /// Morae before the end where the question rise starts.
    let questionLead: Double
    let alpha: Double
    let beta: Double
    let gain: Double
    /// Sampling step, in morae.
    public let step: Double
    /// Where OJAD puts the baseline when drawing: `y = (displayOffset - level) * height`.
    public let displayOffset: Double

    /// OJAD's `set_type("word")` preset (単語検索 curves).
    public static let word = FujisakiModel(
        start: 110, moraDuration: 100,
        phraseAmplitudes: (0.3, 0.3, 0.3),
        fallingAmplitudes: (0.5, 0.5, 0.5),
        flatAmplitudes: (0.5, 0.5, 0.5),
        laterAccentAmplitude: 0.1, secondaryAccentAmplitude: 0.1,
        questionAmplitude: 15, accentDelay: 0.5, questionLead: 0,
        alpha: 5.0, beta: 40, gain: 0.8, step: 0.2, displayOffset: 0.9
    )

    /// OJAD's `set_type("phrase")` preset (スズキクン sentence curves).
    public static let phrase = FujisakiModel(
        start: 220, moraDuration: 100,
        phraseAmplitudes: (0.3, 0.25, 0.25),
        fallingAmplitudes: (0.2, 0.2, 0.2),
        flatAmplitudes: (0.2, 0.2, 0.2),
        laterAccentAmplitude: 0.15, secondaryAccentAmplitude: 0.1,
        questionAmplitude: 15, accentDelay: 0.5, questionLead: 1.2,
        alpha: 3.0, beta: 30, gain: 1.0, step: 0.1, displayOffset: 0.9
    )

    /// Samples the contour for one accent phrase.
    ///
    /// - Parameters:
    ///   - accent: One value per mora as OJAD emits it (`[0,1,0]`): 0 = low, >0 = high;
    ///     integers number the accent commands, fractions mark secondary accents.
    ///   - phraseIndex: Position of the phrase in its sentence; later phrases start lower.
    ///   - isQuestion: Adds the final rise of a question.
    public func contour(accent: [Double], phraseIndex: Int = 0, isQuestion: Bool = false) -> [PitchSample] {
        guard !accent.isEmpty else { return [] }
        let morae = Double(accent.count)
        let baseline = amplitude(phraseAmplitudes, phraseIndex) * gp(start + morae * moraDuration)
        var samples: [PitchSample] = []
        // Accumulated rather than multiplied so the sample positions match OJAD's loop.
        var point = 0.0
        while point < morae + 0.3 {
            samples.append(PitchSample(position: point, level: f0(at: point, accent, phraseIndex, isQuestion) - baseline))
            point += step
        }
        return samples
    }

    private func f0(at point: Double, _ accent: [Double], _ phraseIndex: Int, _ isQuestion: Bool) -> Double {
        let t = moraDuration * point
        var value = amplitude(phraseAmplitudes, phraseIndex) * gp(start + t)

        let falling = amplitude(fallingAmplitudes, phraseIndex)
        let flat = amplitude(flatAmplitudes, phraseIndex)
        let firstCommand = accent.firstIndex(of: 1)
        let firstFall = firstCommand.flatMap { start in accent[start...].firstIndex(of: 0) }

        var previousHigh = false
        for (i, command) in accent.enumerated() {
            let high = command > 0
            if high != previousHigh {
                let onset = t - (Double(i) - accentDelay) * moraDuration
                if high {
                    if i == firstCommand {
                        value += (firstFall == nil ? flat : falling) * ga(onset)
                    } else if command.isWhole {
                        value += laterAccentAmplitude * ga(onset)
                    } else {
                        value += secondaryAccentAmplitude * ga(onset)
                    }
                } else {
                    if i == firstFall {
                        value -= falling * ga(onset)
                    } else if accent[i - 1].isWhole {
                        value -= laterAccentAmplitude * ga(onset)
                    } else {
                        value -= secondaryAccentAmplitude * ga(onset)
                    }
                }
            }
            if point < Double(i) { break }
            previousHigh = high
        }

        if isQuestion {
            value += questionAmplitude * gq(t - (morae(accent) - questionLead) * moraDuration)
        }
        return value * gain
    }

    private func morae(_ accent: [Double]) -> Double { Double(accent.count) }

    private func amplitude(_ values: (Double, Double, Double), _ phraseIndex: Int) -> Double {
        switch phraseIndex {
        case 0: values.0
        case 1: values.1
        default: values.2
        }
    }

    /// Phrase-command response.
    private func gp(_ ms: Double) -> Double {
        guard ms > 0 else { return 0 }
        let t = ms / 1000
        return alpha * alpha * t * exp(-alpha * t)
    }

    /// Accent-command step response.
    private func ga(_ ms: Double) -> Double {
        guard ms > 0 else { return 0 }
        let t = ms / 1000
        return 1 - (1 + beta * t) * exp(-beta * t)
    }

    /// Question rise.
    private func gq(_ ms: Double) -> Double {
        guard ms > 0 else { return 0 }
        let t = ms / 1000
        return t * t
    }
}

private extension Double {
    var isWhole: Bool { truncatingRemainder(dividingBy: 1) == 0 }
}
