import SwiftUI
import MoonlitCore

///  "Awards & Recognition" section: one block per award body the
/// title has wins/nominations in — a fixed-width leading column (wreathed
/// glyph, body name, win/nomination summary) beside a two-column grid of
/// year + category entries (wins first, then an "ALSO NOMINATED" sub-list).
struct MacAwardsRecognitionSection: View {
    let summary: AwardSummary

    var body: some View {
        if !summary.bodiesRepresented.isEmpty {
            VStack(alignment: .leading, spacing: 36) {
                Text("Awards & Recognition")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                ForEach(summary.bodiesRepresented, id: \.self) { body in
                    awardBlock(for: body)
                }
            }
        }
    }

    private func awardBlock(for awardBody: AwardBody) -> some View {
        let wins = summary.wins(for: awardBody)
        let noms = summary.nominations(for: awardBody)
        let years = (wins + noms).compactMap(\.year)

        return HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 10) {
                wreathedGlyph(for: awardBody)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(awardBody.displayName)s")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(summaryLine(wins: wins.count, noms: noms.count))
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(awardBody.tintColor)
                    if let minYear = years.min(), let maxYear = years.max() {
                        Text(minYear == maxYear ? String(minYear) : "\(minYear)–\(maxYear)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }
                }
            }
            .frame(width: 220, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 4) {
                ForEach(wins, id: \.self) { entry in
                    entryRow(entry)
                }
                if !noms.isEmpty {
                    Text("ALSO NOMINATED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.top, wins.isEmpty ? 0 : 10)
                        .gridCellColumns(2)
                    ForEach(noms, id: \.self) { entry in
                        entryRow(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func wreathedGlyph(for awardBody: AwardBody) -> some View {
        HStack(spacing: -4) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 34))
                .foregroundColor(awardBody.tintColor)
            if let asset = awardBody.assetName {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 34))
                .foregroundColor(awardBody.tintColor)
        }
    }

    private func entryRow(_ entry: AwardEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let year = entry.year {
                Text(String(year))
                    .font(.subheadline)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .frame(width: 40, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                // Only set on person-scoped summaries — a title's own awards
                // don't need to repeat the title's name.
                if let workTitle = entry.workTitle {
                    Text(workTitle)
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    private func summaryLine(wins: Int, noms: Int) -> String {
        var parts: [String] = []
        if wins > 0 { parts.append("\(wins) WIN\(wins == 1 ? "" : "S")") }
        if noms > 0 { parts.append("\(noms) NOMINATION\(noms == 1 ? "" : "S")") }
        return parts.joined(separator: " · ")
    }
}
