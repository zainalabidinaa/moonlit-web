import SwiftUI
import MoonlitCore

/// Shared cache-aware image fetch used by `CachedAsyncImage` and
/// `LadderedCachedImage`.
enum CachedImageLoader {
    /// Loads a single URL, returning a resolved phase. Retries transient network
    /// failures with backoff; a real HTTP error (404 etc) fails fast so callers
    /// can move on. Successful bytes are written back to `MoonlitImageCache`.
    @MainActor static func load(_ url: URL) async -> AsyncImagePhase {
        if let cachedData = MoonlitImageCache.cachedData(for: url),
           let image = UIImage(data: cachedData) {
            return .success(Image(uiImage: image))
        }

        // A chunk of artwork is hosted on flaky free hosts (e.g. i.postimg.cc) that
        // intermittently drop connections; a single attempt leaves ~20% of tiles
        // blank. Backoffs: ~0.4s, 1.0s, 2.0s.
        let backoffs: [Double] = [0.4, 1.0, 2.0]
        var lastError: Error = URLError(.unknown)
        for attempt in 0...backoffs.count {
            if Task.isCancelled { return .empty }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard (200..<400).contains(code) else {
                    return .failure(URLError(.badServerResponse))
                }
                guard let image = UIImage(data: data) else {
                    return .failure(URLError(.cannotDecodeContentData))
                }
                MoonlitImageCache.store(data: data, for: url)
                return .success(Image(uiImage: image))
            } catch {
                lastError = error
                if attempt < backoffs.count {
                    try? await Task.sleep(for: .seconds(backoffs[attempt]))
                }
            }
        }
        return .failure(lastError)
    }
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url) { phase = await CachedImageLoader.load(url) }
    }
}

/// Tries an ordered list of candidate URLs, stepping to the next only if the
/// current one fails to load. Used for the hero poster resolution ladder
/// (`w780 → w500 → w342`, then addon fallback) so a missing size never leaves
/// the hero blank.
struct LadderedCachedImage<Content: View>: View {
    let urls: [URL]
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: urls) { await load() }
    }

    @MainActor private func load() async {
        for url in urls {
            if Task.isCancelled { return }
            let result = await CachedImageLoader.load(url)
            if case .success = result {
                // Animate the assignment so a `.transition` in the content (e.g.
                // the hero poster fading in over its placeholder) crossfades
                // instead of hard-cutting.
                withAnimation(.easeInOut(duration: 0.35)) { phase = result }
                return
            }
        }
        phase = .failure(URLError(.fileDoesNotExist))
    }
}
