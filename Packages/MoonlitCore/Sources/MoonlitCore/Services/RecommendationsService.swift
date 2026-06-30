import Foundation

public struct RecommendationRow: Codable, Identifiable, Sendable {
    public let rowType: String
    public let rowTitle: String
    public let coverImage: String?
    public let sortOrder: Int
    public let items: [MetaPreview]

    public var id: String { "\(rowType)_\(rowTitle)" }

    enum CodingKeys: String, CodingKey {
        case rowType = "row_type"
        case rowTitle = "row_title"
        case coverImage = "cover_image"
        case sortOrder = "sort_order"
        case items
    }
}

public struct RecommendationsResponse: Codable, Sendable {
    public let generatedAt: String
    public let rows: [RecommendationRow]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case rows
    }
}

@MainActor
public final class RecommendationsService: ObservableObject {
    public static let shared = RecommendationsService()

    @Published public var rows: [RecommendationRow] = []
    @Published public var isLoading = false
    @Published public var generatedAt: String?

    private let apiBase = "https://moonlit-web-zainalabidinaas-projects.vercel.app/api/recommendations"

    private init() {}

    public func load(profileId: String) async {
        isLoading = true
        defer { isLoading = false }

        guard var components = URLComponents(string: apiBase) else { return }
        components.queryItems = [URLQueryItem(name: "profile_id", value: profileId)]

        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(RecommendationsResponse.self, from: data)
            rows = response.rows
            generatedAt = response.generatedAt
        } catch {
            print("[RecommendationsService] load failed: \(error)")
        }
    }

    public func triggerRegeneration(profileId: String) async -> Bool {
        guard let components = URLComponents(string: "\(apiBase)/generate") else { return false }
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["profile_id": profileId])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["success"] as? Bool ?? false
        } catch {
            print("[RecommendationsService] generate failed: \(error)")
            return false
        }
    }

    public func clear() {
        rows = []
        generatedAt = nil
    }
}
