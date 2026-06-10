import Foundation

public struct PersonDetails: Sendable {
    public let id: Int
    public let name: String
    public let biography: String
    public let birthday: String?
    public let placeOfBirth: String?
    public let alsoKnownAs: [String]
    public let profilePath: String?
    public let profileImages: [String]
    public let knownForDepartment: String?
    public let imdbId: String?
    public let credits: PersonCredits
}

public struct PersonCredits: Sendable {
    public let cast: [PersonCredit]
    public let crew: [PersonCredit]

    public var allCombined: [PersonCredit] {
        (cast + crew).sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    public var knownFor: [PersonCredit] {
        cast.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }.prefix(5).map { $0 }
    }
}

public struct PersonCredit: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let mediaType: String
    public let character: String?
    public let job: String?
    public let releaseDate: String?
    public let posterPath: String?
    public var backdropPath: String?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let episodeCount: Int?
    public let popularity: Double?

    public var year: String? {
        releaseDate.flatMap { $0.components(separatedBy: "-").first }
    }

    public var creditType: String {
        if let job, !job.isEmpty { return job }
        return character != nil ? "Acting" : "Unknown"
    }
}
