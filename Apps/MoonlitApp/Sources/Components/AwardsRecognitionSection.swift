import SwiftUI
import MoonlitCore

///  "Awards & Recognition" section: one block per award body the
/// title has wins/nominations in, glyph + "N WIN(S) · N NOMINATION(S)" header,
/// wins listed first (year desc), then an "ALSO NOMINATED" sub-list.
struct AwardsRecognitionSection: View {
    let summary: AwardSummary

    var body: some View {
        if !summary.bodiesRepresented.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                Text("Awards & Recognition")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)

                ForEach(summary.bodiesRepresented, id: \.self) { body in
                    awardBlock(for: body)
                }
            }
        }
    }

    private func awardBlock(for awardBody: AwardBody) -> some View {
        let wins = summary.wins(for: awardBody)
        let noms = summary.nominations(for: awardBody)

        return HStack(alignment: .top, spacing: 16) {
            if let asset = awardBody.assetName {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(awardBody.displayName)s")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                    Text(summaryLine(wins: wins.count, noms: noms.count))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(awardBody.tintColor)
                }

                ForEach(wins, id: \.self) { entry in
                    entryRow(entry)
                }

                if !noms.isEmpty {
                    Text("ALSO NOMINATED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.top, wins.isEmpty ? 0 : 4)
                    ForEach(noms, id: \.self) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func entryRow(_ entry: AwardEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let year = entry.year {
                Text(String(year))
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .frame(width: 36, alignment: .leading)
            }
            Text(entry.category)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryLine(wins: Int, noms: Int) -> String {
        var parts: [String] = []
        if wins > 0 { parts.append("\(wins) WIN\(wins == 1 ? "" : "S")") }
        if noms > 0 { parts.append("\(noms) NOMINATION\(noms == 1 ? "" : "S")") }
        return parts.joined(separator: " · ")
    }
}
