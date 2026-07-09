import Foundation

/// Which shape of artwork a tile/hero wants first.
public enum ArtworkOrientation: Sendable {
    case portrait
    case landscape
}

public extension MetaPreview {
    /// Best-fit artwork URL for the given orientation. Falls back to the other
    /// orientation's art, then to `backdrop`, when the preferred art is missing.
    ///
    /// Centralizing this avoids each screen hand-rolling its own `poster ?? banner`
    /// chain with an inconsistent (and easy to get backwards) preference order.
    func artworkURL(preferring orientation: ArtworkOrientation) -> URL? {
        artworkString(preferring: orientation).flatMap(URL.init)
    }

    /// Same preference order as `artworkURL(preferring:)`, without resolving to a
    /// `URL` — for call sites that just need a raw path/URL string (e.g. building
    /// a `CatalogRow.coverImage`).
    func artworkString(preferring orientation: ArtworkOrientation) -> String? {
        switch orientation {
        case .portrait:
            return poster ?? banner ?? backdrop
        case .landscape:
            return banner ?? poster ?? backdrop
        }
    }
}
