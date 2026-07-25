import Foundation

public final class StreamService: @unchecked Sendable {
    public static let shared = StreamService()
    private let client = StremioHTTPClient.shared

    private init() {}

    public func fetchStreams(type: String, id: String, baseURL: String) async throws -> [StreamItem] {
        guard !id.hasPrefix("folder_") else { return [] }
        let url = "\(baseURL)/stream/\(type)/\(id).json"

        struct RawStream: Codable {
            let name: String?
            let title: String?
            let description: String?
            let url: String?
            let infoHash: String?
            let fileIdx: Int?
            let externalUrl: String?
            let ytId: String?
            let playerFrameUrl: String?
            let sources: [String]?
            let behaviorHints: RawBehaviorHints?
            let subtitles: [RawSubtitle]?
        }
        struct RawSubtitle: Codable {
            let id: String?
            let url: String?
            let lang: String?
            let name: String?
        }
        struct RawBehaviorHints: Codable {
            let notWebReady: Bool?
            let bingeGroup: String?
            let countryWhitelist: [String]?
            let proxyHeaders: RawProxyHeaders?
            let filename: String?
            let videoHash: String?
            let videoSize: Int64?
        }
        struct RawProxyHeaders: Codable {
            let request: [String: String]?
            let response: [String: String]?
        }
        struct StreamResponse: Codable {
            let streams: [RawStream]?
        }

        do {
            let response: StreamResponse = try await getJSONWithNetworkRetry(url: url, type: StreamResponse.self)
            return (response.streams ?? []).map { raw in
                StreamItem(
                    name: raw.name,
                    title: raw.title,
                    description: raw.description,
                    url: raw.url,
                    infoHash: raw.infoHash,
                    fileIdx: raw.fileIdx,
                    externalUrl: raw.externalUrl,
                    ytId: raw.ytId,
                    playerFrameUrl: raw.playerFrameUrl,
                    sources: raw.sources,
                    sourceName: nil,
                    addonName: nil,
                    addonId: nil,
                    behaviorHints: raw.behaviorHints.map {
                        StreamBehaviorHints(
                            notWebReady: $0.notWebReady,
                            bingeGroup: $0.bingeGroup,
                            countryWhitelist: $0.countryWhitelist,
                            proxyHeaders: $0.proxyHeaders.map {
                                StreamProxyHeaders(
                                    request: $0.request,
                                    response: $0.response
                                )
                            },
                            filename: $0.filename,
                            videoHash: $0.videoHash,
                            videoSize: $0.videoSize
                        )
                    },
                    subtitles: raw.subtitles?.map {
                        SubtitleItem(
                            id: $0.id ?? UUID().uuidString,
                            url: $0.url ?? "",
                            lang: $0.lang ?? "unknown",
                            name: $0.name
                        )
                    }
                )
            }
        } catch {
            throw error
        }
    }

    private func getJSONWithNetworkRetry<T: Decodable>(url: String, type: T.Type) async throws -> T {
        do {
            return try await client.getJSON(url: url, type: type)
        } catch StremioError.networkError(let underlying) {
            guard Self.isWorthRetrying(underlying) else { throw StremioError.networkError(underlying) }
            try await Task.sleep(for: .seconds(1))
            return try await client.getJSON(url: url, type: type)
        }
    }

    /// A retry only pays off for errors that a second attempt can plausibly fix.
    /// Timeouts and unresolvable hosts are not those: the client already waited
    /// out `timeoutIntervalForRequest` (12s), and retrying doubles that cost for
    /// a host that is simply down — which gates playback behind the slowest
    /// dead addon. Fail fast instead and let the caller rank what did arrive.
    private static func isWorthRetrying(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return true }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .unsupportedURL, .badURL, .cancelled:
            return false
        default:
            return true
        }
    }

    public func fetchStreamsFromAddons(
        type: String,
        id: String,
        addons: [AddonManifest]
    ) async throws -> [StreamItem] {
        var allStreams: [StreamItem] = []

        await withTaskGroup(of: (String, [StreamItem])?.self) { group in
            for addon in addons {
                guard addon.hasResource("stream"),
                      let types = addon.types,
                      types.contains(type),
                      let baseURL = addon.transportUrl else { continue }

                group.addTask {
                    do {
                        let streams = try await self.fetchStreams(type: type, id: id, baseURL: baseURL)
                        let enriched = streams.map { stream in
                            StreamItem(
                                name: stream.name,
                                title: stream.title,
                                description: stream.description,
                                url: stream.url,
                                infoHash: stream.infoHash,
                                fileIdx: stream.fileIdx,
                                externalUrl: stream.externalUrl,
                                ytId: stream.ytId,
                                playerFrameUrl: stream.playerFrameUrl,
                                sources: stream.sources,
                                sourceName: stream.sourceName,
                                addonName: addon.name,
                                addonId: addon.id,
                                behaviorHints: stream.behaviorHints,
                                subtitles: stream.subtitles
                            )
                        }
                        return (addon.name, enriched)
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let (_, streams) = result {
                    allStreams.append(contentsOf: streams)
                }
            }
        }

        return allStreams
    }
}
