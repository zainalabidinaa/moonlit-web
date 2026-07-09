import Foundation

public enum RowDisplayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case heroBanner
    case cardStack
    case carouselCinematic
    case topTen

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .heroBanner: return "Hero Banner"
        case .cardStack: return "Card Stack"
        case .carouselCinematic: return "Carousel Cinematic"
        case .topTen: return "Top 10"
        }
    }
}

@MainActor
public final class CollectionRowDisplayStyleStore: ObservableObject {
    public static let shared = CollectionRowDisplayStyleStore()

    @Published public private(set) var stylesByRowTitle: [String: RowDisplayStyle]
    @Published public private(set) var revision = 0

    private let defaults: UserDefaults
    private let key = "moonlit.collectionRowDisplayStyles"

    public convenience init() {
        self.init(defaults: .standard)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let raw = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        self.stylesByRowTitle = raw.reduce(into: [:]) { result, pair in
            result[pair.key] = RowDisplayStyle(rawValue: pair.value) ?? .standard
        }
    }

    public func style(forRowTitle title: String) -> RowDisplayStyle {
        stylesByRowTitle[title] ?? .standard
    }

    public func setStyle(_ style: RowDisplayStyle, forRowTitle title: String) {
        stylesByRowTitle[title] = style
        save()
    }

    private func save() {
        let raw = stylesByRowTitle.mapValues(\.rawValue)
        defaults.set(raw, forKey: key)
        revision += 1
    }
}
