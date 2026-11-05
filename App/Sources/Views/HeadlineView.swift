import OJADKit
import SwiftUI

/// The top of the word page: each headword part (`治る`, `治ります`) over its kana with
/// pitch marks, joined by `·`, so the basic readings show without opening the conjugations.
struct WordHeadline: View {
    let entry: WordEntry

    private var forms: [HeadlineForm] { entry.headlineForms }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(forms.enumerated()), id: \.offset) { index, form in
                    if index > 0 {
                        Text("·").font(.title2.bold()).foregroundStyle(.secondary)
                    }
                    HeadlineFormView(form: form)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(forms.enumerated()), id: \.offset) { _, form in
                    HeadlineFormView(form: form)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("headline")
    }

    private var accessibilityText: String {
        forms.map { form in
            ([form.written] + form.readings.map(\.notation)).joined(separator: "，")
        }
        .joined(separator: "；")
    }
}

private struct HeadlineFormView: View {
    let form: HeadlineForm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if form.isKanaOnly {
                MarkedKana(reading: form.readings[0], font: .title2.bold())
            } else {
                Text(form.written).font(.title2.bold())
                ForEach(Array(form.readings.enumerated()), id: \.offset) { _, reading in
                    MarkedKana(reading: reading, font: .body)
                }
            }
        }
        .fixedSize()
    }
}

/// Kana with the same pitch marks as the conjugation rows, without the curve.
struct MarkedKana: View {
    let reading: AccentedReading
    var font: Font = .body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(reading.morae.enumerated()), id: \.offset) { _, mora in
                MoraCell(mora: mora, font: font, fillsWidth: false)
            }
        }
        .padding(.trailing, 2)
    }
}
