import SwiftUI
import MoonlitCore

/// Directors / Creators / Writers / Producers / Cinematography / Music / Editors,
/// each rendered as a label + comma-joined names — Harbor-style crew grid shown
/// above the Cast row on the detail screen. Only non-empty categories render.
struct MacCrewInfoGrid: View {
    let detail: MetaDetail

    private var categories: [(title: String, people: [Person])] {
        [
            ("Directors", detail.director ?? []),
            ("Creators", detail.creators ?? []),
            ("Writers", detail.writer ?? []),
            ("Producers", detail.producers ?? []),
            ("Cinematography", detail.cinematographers ?? []),
            ("Music", detail.composers ?? []),
            ("Editors", detail.editors ?? []),
        ].filter { !$0.people.isEmpty }
    }

    var body: some View {
        let visible = categories
        if !visible.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 18) {
                ForEach(visible, id: \.title) { category in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(category.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MoonlitTheme.textTertiary)
                        Text(category.people.map(\.name).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
