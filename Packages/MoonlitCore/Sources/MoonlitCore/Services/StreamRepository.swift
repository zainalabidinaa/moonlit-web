import Foundation

@MainActor
public class StreamRepository: ObservableObject {
    public static let shared = StreamRepository()

    @Published public var streams: [StreamItem] = []
    @Published public var isLoading = false

    private let streamService = StreamService.shared

    private init() {}

    public func clearStreams() {
        streams = []
        isLoading = false
    }

    public func fetchStreams(type: String, id: String, addons: [AddonManifest], title: String? = nil) async {
        streams = []
        isLoading = true
        guard !id.hasPrefix("folder_") else {
            isLoading = false
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            isLoading = false
            return
        }

        let eligible = addons.filter {
            $0.hasResource("stream") &&
            $0.canHandleStream(type: type) &&
            $0.transportUrl != nil
        }

        guard !eligible.isEmpty else {
            isLoading = false
            return
        }

        // Fire all addon requests in parallel and publish each result immediately
        // as it arrives instead of waiting for the slowest addon.
        await withTaskGroup(of: [StreamItem].self) { group in
            for addon in eligible {
                guard let baseURL = addon.transportUrl else { continue }
                group.addTask {
                    guard let raw = try? await self.streamService.fetchStreams(
                        type: type, id: id, baseURL: baseURL
                    ) else { return [] }
                    let mapped = raw.map { stream in
                        StreamItem(
                            name: stream.name, title: stream.title,
                            description: stream.description, url: stream.url,
                            infoHash: stream.infoHash, fileIdx: stream.fileIdx,
                            externalUrl: stream.externalUrl, ytId: stream.ytId,
                            playerFrameUrl: stream.playerFrameUrl, sources: stream.sources,
                            sourceName: stream.sourceName,
                            addonName: addon.name, addonId: addon.id,
                            behaviorHints: stream.behaviorHints, subtitles: stream.subtitles
                        )
                    }
                    return mapped.filter { StreamMatchGuard.shouldKeep($0, type: type, id: id, title: title) }
                }
            }

            // Each addon result publishes immediately — UI updates as addons respond.
            for await addonStreams in group {
                if !addonStreams.isEmpty {
                    self.streams.append(contentsOf: addonStreams)
                }
            }
        }

        isLoading = false
    }

    public func fetchStreamsFromSingleAddon(type: String, id: String, addon: AddonManifest, title: String? = nil) async throws -> [StreamItem] {
        guard !id.hasPrefix("folder_") else { return [] }
        guard let baseURL = addon.transportUrl else { return [] }
        let raw = try await streamService.fetchStreams(type: type, id: id, baseURL: baseURL)
        return raw.map { stream in
            StreamItem(
                name: stream.name, title: stream.title, description: stream.description,
                url: stream.url, infoHash: stream.infoHash, fileIdx: stream.fileIdx,
                externalUrl: stream.externalUrl, ytId: stream.ytId,
                playerFrameUrl: stream.playerFrameUrl, sources: stream.sources,
                sourceName: stream.sourceName, addonName: addon.name, addonId: addon.id,
                behaviorHints: stream.behaviorHints, subtitles: stream.subtitles
            )
        }
        .filter { StreamMatchGuard.shouldKeep($0, type: type, id: id, title: title) }
    }

    public func bestStream(for type: String, id: String, from addons: [AddonManifest], title: String? = nil, prefer4K: Bool = false) async -> StreamItem? {
        await fetchStreams(type: type, id: id, addons: addons, title: title)
        // Use the same ranked selector as PlayerScreen:
        // bolt ⚡ (10 000 pts) → cached (5 000 pts) → highest mbps (≤ 1 000 pts)
        // then resolution/codec tie-breakers.
        return StreamSourceSelector.initialStream(from: streams, prefer4K: prefer4K)
    }
}
