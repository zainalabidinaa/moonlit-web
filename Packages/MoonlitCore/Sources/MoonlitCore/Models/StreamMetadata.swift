import Foundation

public struct StreamMetadata: Codable, Sendable {
    public let resolution: String?
    public let videoCodec: String?
    public let audioCodec: String?
    public let hdr: String?
    public let fileSize: String?
    public let releaseGroup: String?

    public init(
        resolution: String? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        hdr: String? = nil,
        fileSize: String? = nil,
        releaseGroup: String? = nil
    ) {
        self.resolution = resolution
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.hdr = hdr
        self.fileSize = fileSize
        self.releaseGroup = releaseGroup
    }
}

public extension StreamItem {
    func parseMetadata() -> StreamMetadata {
        let desc = (description ?? "").lowercased()
        var meta = StreamMetadata()

        // Resolution
        let resPatterns = ["4k", "2160p", "1080p", "720p", "480p"]
        for r in resPatterns {
            if desc.contains(r) {
                meta = StreamMetadata(resolution: r.uppercased(), videoCodec: meta.videoCodec,
                    audioCodec: meta.audioCodec, hdr: meta.hdr,
                    fileSize: meta.fileSize, releaseGroup: meta.releaseGroup)
                break
            }
        }

        // HDR
        let hdrPatterns = ["hdr10+", "dolby vision", "hdr10", "hdr"]
        for h in hdrPatterns {
            if desc.contains(h) {
                let label = h == "dolby vision" ? "Dolby Vision" : h.uppercased()
                meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                    audioCodec: meta.audioCodec, hdr: label,
                    fileSize: meta.fileSize, releaseGroup: meta.releaseGroup)
                break
            }
        }

        // Video codec
        let vCodecs = [("hevc", "HEVC"), ("x265", "H.265"), ("h265", "H.265"),
                        ("avc", "AVC"), ("x264", "H.264"), ("h264", "H.264"),
                        ("av1", "AV1"), ("vp9", "VP9")]
        for (key, label) in vCodecs {
            if desc.contains(key) {
                meta = StreamMetadata(resolution: meta.resolution, videoCodec: label,
                    audioCodec: meta.audioCodec, hdr: meta.hdr,
                    fileSize: meta.fileSize, releaseGroup: meta.releaseGroup)
                break
            }
        }

        // Audio codec
        let aCodecs = ["dolby atmos", "truehd", "dts-hd", "dts", "eac3", "ac3", "aac", "flac", "opus", "mp3"]
        for a in aCodecs {
            if desc.contains(a) {
                let label = a == "dolby atmos" ? "Dolby Atmos" : a.uppercased()
                meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                    audioCodec: label, hdr: meta.hdr,
                    fileSize: meta.fileSize, releaseGroup: meta.releaseGroup)
                break
            }
        }

        // File size
        if let range = desc.range(of: "\\d+(\\.\\d+)?\\s*(gb|mb|gib|mib)", options: .regularExpression) {
            meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                audioCodec: meta.audioCodec, hdr: meta.hdr,
                fileSize: String(desc[range]).uppercased(),
                releaseGroup: meta.releaseGroup)
        }

        return meta
    }
}
