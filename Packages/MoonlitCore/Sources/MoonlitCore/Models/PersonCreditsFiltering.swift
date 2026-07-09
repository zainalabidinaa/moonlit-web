import Foundation

public enum CreditMediaFilter: String, CaseIterable, Sendable {
    case all = "All"
    case movies = "Movies"
    case series = "Series"

    fileprivate func matches(_ credit: PersonCredit) -> Bool {
        switch self {
        case .all: return true
        case .movies: return credit.mediaType == "movie"
        case .series: return credit.mediaType == "tv"
        }
    }
}

public extension PersonCredit {
    /// Cast credits have no TMDB `department` — treat them as "Acting".
    var departmentLabel: String { department ?? "Acting" }

    var mediaKindLabel: String { mediaType == "tv" ? "Series" : "Movie" }

    /// "Acting • Series • 80 eps" (episode count only shown for tv credits).
    func subtitle(department: String) -> String {
        var parts = [department, mediaKindLabel]
        if mediaType == "tv", let episodeCount, episodeCount > 0 {
            parts.append("\(episodeCount) eps")
        }
        return parts.joined(separator: " • ")
    }
}

public extension PersonCredits {
    /// "Acting" (when there are cast credits) followed by unique crew departments,
    /// alphabetically.
    var departments: [String] {
        var result: [String] = []
        if !cast.isEmpty { result.append("Acting") }
        let crewDepartments = Set(crew.map(\.departmentLabel)).subtracting(["Acting"])
        result.append(contentsOf: crewDepartments.sorted())
        return result
    }

    /// Credits matching the given media filter and department (`nil` = all
    /// departments). Crew rows for the same title/department are merged so a
    /// producer-writer-director only shows once per title, with jobs joined
    /// ("Producer, Director").
    func filtered(media: CreditMediaFilter, department: String?) -> [PersonCredit] {
        var pool: [PersonCredit]
        switch department {
        case nil:
            pool = cast + crew
        case "Acting":
            pool = cast
        case let department?:
            pool = crew.filter { $0.departmentLabel == department }
        }
        pool = pool.filter(media.matches)

        var merged: [String: PersonCredit] = [:]
        var order: [String] = []
        for credit in pool {
            let key = "\(credit.id)|\(credit.departmentLabel)"
            if let existing = merged[key] {
                let jobs = Set((existing.job ?? "").components(separatedBy: ", ") + [credit.job ?? ""])
                    .filter { !$0.isEmpty }
                var updated = existing
                updated.job = jobs.sorted().joined(separator: ", ")
                merged[key] = updated
            } else {
                merged[key] = credit
                order.append(key)
            }
        }
        return order.compactMap { merged[$0] }
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }
}
