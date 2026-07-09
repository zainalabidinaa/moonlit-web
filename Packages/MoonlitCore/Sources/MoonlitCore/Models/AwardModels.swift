import SwiftUI

/// The award bodies we recognize from Wikidata award labels, in the order
/// they should be preferred when a title has multiple.
public enum AwardBody: String, Codable, CaseIterable, Sendable {
    case oscar
    case emmy
    case bafta
    case goldenGlobe
    case sag
    case criticsChoice
    case cannes
    case venice
    case berlin

    public var displayName: String {
        switch self {
        case .oscar: return "Academy Award"
        case .emmy: return "Emmy"
        case .bafta: return "BAFTA"
        case .goldenGlobe: return "Golden Globe"
        case .sag: return "Screen Actors Guild Award"
        case .criticsChoice: return "Critics' Choice Award"
        case .cannes: return "Cannes"
        case .venice: return "Venice"
        case .berlin: return "Berlin"
        }
    }

    /// Bundled glyph asset name, matching `AwardIndex.assetName(forBody:)`.
    /// `sag` and `criticsChoice` have no bundled glyph.
    public var assetName: String? {
        switch self {
        case .oscar: return "award-oscars"
        case .emmy: return "award-emmy"
        case .bafta: return "award-bafta"
        case .goldenGlobe: return "award-globe"
        case .cannes: return "award-cannes"
        case .venice: return "award-venice"
        case .berlin: return "award-berlin"
        case .sag, .criticsChoice: return nil
        }
    }

    /// Per-body laurel tint, matching Harbor's award corner treatment.
    public var tintColor: Color {
        switch self {
        case .oscar, .emmy, .goldenGlobe: return Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37
        case .bafta: return Color(red: 0.792, green: 0.573, blue: 0.0) // #CA9200
        case .sag: return Color(red: 0.690, green: 0.553, blue: 0.341) // #B08D57
        case .criticsChoice: return Color(red: 0.808, green: 0.533, blue: 0.098) // #CE8819
        case .cannes, .venice: return Color(red: 0.855, green: 0.647, blue: 0.125) // #DAA520
        case .berlin: return Color(red: 0.749, green: 0.749, blue: 0.749) // #BFBFBF
        }
    }

    /// Lower is more prestigious — used to pick the "headline" award when a
    /// title has wins/nominations across several bodies.
    var precedence: Int {
        switch self {
        case .oscar: return 0
        case .emmy: return 1
        case .bafta: return 2
        case .goldenGlobe: return 3
        case .sag: return 4
        case .criticsChoice: return 5
        case .cannes: return 6
        case .venice: return 7
        case .berlin: return 8
        }
    }

    /// Classifies a Wikidata award label (e.g. "Academy Award for Best Picture")
    /// into a known body. Matches on award-ish phrases rather than bare city
    /// names for festival awards, to avoid false positives.
    static func classify(label: String) -> AwardBody? {
        let text = label.lowercased()
        if text.contains("academy award") || text.contains("oscar") { return .oscar }
        if text.contains("primetime emmy") || text.contains("emmy award") { return .emmy }
        if text.contains("bafta") || text.contains("british academy") { return .bafta }
        if text.contains("golden globe") { return .goldenGlobe }
        if text.contains("screen actors guild") { return .sag }
        if text.contains("critics") && text.contains("choice") { return .criticsChoice }
        if text.contains("palme d'or") || text.contains("cannes film festival") { return .cannes }
        if text.contains("golden lion") || text.contains("venice film festival") { return .venice }
        if text.contains("golden bear") || text.contains("berlin international film festival") { return .berlin }
        return nil
    }

    // MARK: - Awards hub metadata (Harbor-style cinematic hero)

    /// Uppercase eyebrow shown above the hub title, e.g. "THE OSCARS".
    public var shorthand: String {
        switch self {
        case .oscar: return "The Oscars"
        case .emmy: return "Television's Finest"
        case .bafta: return "The British Academy"
        case .goldenGlobe: return "Golden Globes"
        case .sag: return "Chosen by Actors"
        case .criticsChoice: return "Critics' Choice"
        case .cannes: return "Cannes Film Festival"
        case .venice: return "Venice Film Festival"
        case .berlin: return "Berlinale"
        }
    }

    /// Full hub title, e.g. "Academy Awards".
    public var hubTitle: String {
        switch self {
        case .oscar: return "Academy Awards"
        case .emmy: return "Emmy Awards"
        case .bafta: return "BAFTA Awards"
        case .goldenGlobe: return "Golden Globe Awards"
        case .sag: return "Screen Actors Guild Awards"
        case .criticsChoice: return "Critics' Choice Awards"
        case .cannes: return "Cannes"
        case .venice: return "Venice"
        case .berlin: return "Berlin"
        }
    }

    /// Year the body was founded (0 when not shown).
    public var founded: Int {
        switch self {
        case .oscar: return 1929
        case .emmy: return 1949
        case .bafta: return 1949
        case .goldenGlobe: return 1944
        case .sag: return 1995
        case .criticsChoice: return 1995
        case .cannes: return 1946
        case .venice: return 1932
        case .berlin: return 1951
        }
    }

    /// One–two sentence description shown under the hero.
    public var about: String {
        switch self {
        case .oscar: return "The most-watched film awards in the world. Voted on by working members of the film industry across every branch, from cinematographers to actors to costume designers."
        case .emmy: return "The highest honor in American television, recognizing excellence across drama, comedy, limited series and beyond."
        case .bafta: return "Britain's premier film honors, awarded by the British Academy of Film and Television Arts."
        case .goldenGlobe: return "A sprawling celebration of both film and television — often the season's first major signal."
        case .sag: return "Awarded by actors, to actors. The only major film awards decided entirely by performers."
        case .criticsChoice: return "Selected by critics across film and television, a broad barometer of the awards season."
        case .cannes: return "The world's most prestigious film festival, awarding the Palme d'Or on the French Riviera."
        case .venice: return "The oldest film festival in the world, awarding the Golden Lion each autumn."
        case .berlin: return "A major European festival awarding the Golden Bear, known for bold, political cinema."
        }
    }

    /// Small uppercase tagline shown beneath the description.
    public var tagline: String {
        switch self {
        case .oscar: return "The Academy of Motion Picture Arts and Sciences"
        case .emmy: return "The Television Academy"
        case .bafta: return "British Academy of Film and Television Arts"
        case .goldenGlobe: return "Golden Globe Foundation"
        case .sag: return "Screen Actors Guild"
        case .criticsChoice: return "Critics' Choice Association"
        case .cannes: return "Festival de Cannes"
        case .venice: return "La Biennale di Venezia"
        case .berlin: return "Internationale Filmfestspiele Berlin"
        }
    }

    /// Maps a home-organizer award folder/collection title (e.g. "Academy
    /// Awards", "Golden Globes", "BAFTA") to a known body.
    public static func fromTitle(_ title: String) -> AwardBody? {
        let t = title.lowercased()
        if t.contains("academy") || t.contains("oscar") { return .oscar }
        if t.contains("emmy") { return .emmy }
        if t.contains("bafta") { return .bafta }
        if t.contains("golden globe") { return .goldenGlobe }
        if t.contains("screen actors") || t == "sag" || t.contains("sag award") { return .sag }
        if t.contains("critics") { return .criticsChoice }
        if t.contains("cannes") || t.contains("palme") { return .cannes }
        if t.contains("venice") { return .venice }
        if t.contains("berlin") || t.contains("berlinale") { return .berlin }
        return nil
    }

    /// Strips the body's own name off a Wikidata award label to get just the
    /// category, e.g. "Academy Award for Best Picture" → "Best Picture".
    static func category(from label: String, body: AwardBody) -> String {
        var text = label
        for prefix in ["\(body.displayName) for ", "\(body.displayName) Award for ", "\(body.displayName) - "] {
            if let range = text.range(of: prefix, options: .caseInsensitive) {
                text.removeSubrange(text.startIndex..<range.upperBound)
                break
            }
        }
        return text.isEmpty ? label : text
    }
}

/// A single award entry — one line in the Awards & Recognition section, e.g.
/// "2024 · Best Picture" under Academy Awards.
public struct AwardEntry: Codable, Sendable, Hashable {
    public let body: AwardBody
    public let category: String
    public let year: Int?

    public init(body: AwardBody, category: String, year: Int?) {
        self.body = body
        self.category = category
        self.year = year
    }
}

/// Wins and nominations for a single title, aggregated from Wikidata.
public struct AwardSummary: Codable, Sendable {
    public let titleId: String
    public var wins: [AwardEntry]
    public var nominations: [AwardEntry]
    public var fetchedAt: Date
    public var lastAccessedAt: Date

    public init(
        titleId: String,
        wins: [AwardEntry] = [],
        nominations: [AwardEntry] = [],
        fetchedAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.titleId = titleId
        self.wins = wins
        self.nominations = nominations
        self.fetchedAt = fetchedAt
        self.lastAccessedAt = lastAccessedAt
    }

    public var isWinner: Bool { !wins.isEmpty }
    public var totalWins: Int { wins.count }
    public var totalNominations: Int { nominations.count }

    /// The most prestigious body the title has a win or nomination in.
    public var primaryBody: AwardBody? {
        if let winner = wins.map(\.body).min(by: { $0.precedence < $1.precedence }) { return winner }
        return nominations.map(\.body).min(by: { $0.precedence < $1.precedence })
    }

    /// `primaryBody` if it has a bundled glyph, else the next-best body that does.
    public var primaryBodyWithAsset: AwardBody? {
        guard let primaryBody else { return nil }
        if primaryBody.assetName != nil { return primaryBody }
        let allBodies = (wins.map(\.body) + nominations.map(\.body))
            .sorted { $0.precedence < $1.precedence }
        return allBodies.first { $0.assetName != nil }
    }

    /// "Academy Award Winner · 3 wins · 5 nominations" or "5 Nominations".
    public var badgeText: String? {
        guard let primaryBody else { return nil }
        if isWinner {
            var text = "\(primaryBody.displayName) Winner"
            if totalWins > 0 || totalNominations > 0 {
                var parts: [String] = []
                if totalWins > 0 { parts.append("\(totalWins) win\(totalWins == 1 ? "" : "s")") }
                if totalNominations > 0 { parts.append("\(totalNominations) nomination\(totalNominations == 1 ? "" : "s")") }
                text += " · " + parts.joined(separator: " · ")
            }
            return text
        }
        guard totalNominations > 0 else { return nil }
        return "\(totalNominations) Nomination\(totalNominations == 1 ? "" : "s")"
    }

    /// Every body with at least one win or nomination, in precedence order —
    /// drives the Awards & Recognition section (one block per body).
    public var bodiesRepresented: [AwardBody] {
        Set(wins.map(\.body) + nominations.map(\.body))
            .sorted { $0.precedence < $1.precedence }
    }

    public func wins(for body: AwardBody) -> [AwardEntry] {
        wins.filter { $0.body == body }.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }

    public func nominations(for body: AwardBody) -> [AwardEntry] {
        nominations.filter { $0.body == body }.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }
}
