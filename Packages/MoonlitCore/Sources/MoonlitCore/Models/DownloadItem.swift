import Foundation

public enum DownloadState: String, Codable, Sendable {
    case queued, downloading, paused, completed, failed
}

public struct DownloadItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let mediaId: String
    public let type: String
    public let name: String
    public let poster: String?
    public let quality: String?
    public let remoteURL: String
    public var localFileName: String
    public var totalBytes: Int64
    public var receivedBytes: Int64
    public var state: DownloadState
    public let createdAt: Date

    public init(id: String, mediaId: String, type: String, name: String, poster: String?,
                quality: String?, remoteURL: String, localFileName: String,
                totalBytes: Int64, receivedBytes: Int64, state: DownloadState, createdAt: Date) {
        self.id = id; self.mediaId = mediaId; self.type = type; self.name = name
        self.poster = poster; self.quality = quality; self.remoteURL = remoteURL
        self.localFileName = localFileName; self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes; self.state = state; self.createdAt = createdAt
    }

    public var progress: Double {
        totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
    }
}
