import Foundation

/// One part of a word's headword with its accented readings: `治る` with `なꜜおる`,
/// `治ります` with `なおりꜜます`.
public struct HeadlineForm: Sendable, Hashable {
    public let written: String
    /// Every accent variant listed for the form; empty when the entry has no such form.
    public let readings: [AccentedReading]

    public init(written: String, readings: [AccentedReading]) {
        self.written = written
        self.readings = readings
    }

    /// True when the written part is just the kana of its only reading (`する`),
    /// so showing it again above the marked kana would only repeat it.
    public var isKanaOnly: Bool {
        readings.count == 1 && readings[0].kana == written
    }
}

extension WordEntry {
    /// The headword's parts (dictionary form, then the polite form for verbs and adjectives)
    /// paired with the readings of the matching conjugated forms.
    public var headlineForms: [HeadlineForm] {
        let parts = headword.split(separator: "・").map(String.init)
        let kinds = ["jisho", "masu"]
        return parts.enumerated().map { index, part in
            let kind = index < kinds.count ? kinds[index] : nil
            let readings = forms.first { $0.kind == kind }?.readings ?? []
            return HeadlineForm(written: part, readings: readings)
        }
    }
}
