import OJADKit
import SwiftUI

/// Conjugation columns grouped so the detail screen opens short: the everyday forms
/// first, the rest folded away.
struct ConjugationGroup: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case common, more, derived

        var title: String {
            switch self {
            case .common: "常用形"
            case .more: "其他活用形"
            case .derived: "使役・受身・可能"
            }
        }
    }

    let kind: Kind
    let forms: [ConjugatedForm]

    var id: String { kind.rawValue }

    static let defaultExpanded: Set<Kind> = [.common]

    /// Keeps OJAD's column order inside each group; unknown columns go to `.more`.
    static func groups(for entry: WordEntry) -> [ConjugationGroup] {
        let common: Set<String> = ["jisho", "masu", "te", "ta", "nai"]
        let derived: Set<String> = entry.category == .verb ? ["shieki", "ukemi", "kano"] : []
        func kind(of form: ConjugatedForm) -> Kind {
            if entry.category == .noun || common.contains(form.kind) { return .common }
            return derived.contains(form.kind) ? .derived : .more
        }
        return Kind.allCases.compactMap { group in
            let forms = entry.forms.filter { kind(of: $0) == group }
            return forms.isEmpty ? nil : ConjugationGroup(kind: group, forms: forms)
        }
    }
}

/// Which groups are open, shared by every word and kept across launches.
private struct ExpandedGroups: DynamicProperty {
    @AppStorage("conjugationGroupsExpanded") private var raw = ConjugationGroup.defaultExpanded
        .map(\.rawValue).sorted().joined(separator: ",")

    var kinds: Set<ConjugationGroup.Kind> {
        get { Set(raw.split(separator: ",").compactMap { ConjugationGroup.Kind(rawValue: String($0)) }) }
        nonmutating set { raw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }
}

struct ConjugationGroupsView: View {
    let groups: [ConjugationGroup]
    private var expanded = ExpandedGroups()

    var body: some View {
        if groups.count == 1, let only = groups.first {
            ForEach(only.forms, id: \.kind) { ConjugatedFormRow(form: $0) }
        } else {
            ForEach(groups) { group in
                DisclosureGroup(isExpanded: binding(for: group.kind)) {
                    ForEach(group.forms, id: \.kind) { ConjugatedFormRow(form: $0) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.kind.title).font(.subheadline.weight(.semibold))
                        if !expanded.kinds.contains(group.kind) {
                            Text(group.forms.map(\.label).joined(separator: "・"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("conjugation-group-\(group.id)")
            }
        }
    }

    private func binding(for kind: ConjugationGroup.Kind) -> Binding<Bool> {
        Binding(
            get: { expanded.kinds.contains(kind) },
            set: { isOpen in
                withAnimation {
                    if isOpen { expanded.kinds.insert(kind) } else { expanded.kinds.remove(kind) }
                }
            }
        )
    }
}

/// The section header: title plus 全部展开 / 全部收起.
struct ConjugationHeader: View {
    let groups: [ConjugationGroup]
    private var expanded = ExpandedGroups()

    var body: some View {
        HStack {
            Text("活用形")
            Spacer()
            if groups.count > 1 {
                let allOpen = groups.allSatisfy { expanded.kinds.contains($0.kind) }
                Button(allOpen ? "全部收起" : "全部展开") {
                    withAnimation {
                        expanded.kinds = allOpen ? [] : Set(ConjugationGroup.Kind.allCases)
                    }
                }
                .font(.footnote)
                .textCase(nil)
            }
        }
    }
}

struct ConjugatedFormRow: View {
    let form: ConjugatedForm

    var body: some View {
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
