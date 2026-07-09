import Foundation

@MainActor
public final class DownloadManager: NSObject, ObservableObject {

    public static let shared = DownloadManager()

    @Published public private(set) var downloads: [DownloadItem] = []

    private let persistenceName: String

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.moonlit.mac.downloads")
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var taskMap: [Int: String] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]

    public init(persistenceName: String = "downloads.json") {
        self.persistenceName = persistenceName
        super.init()
        load()
    }

    // MARK: - Public API

    @discardableResult
    public func startDownload(mediaId: String, type: String, name: String,
                              poster: String?, quality: String?,
                              url: String, headers: [String: String]? = nil) -> Bool {
        guard DownloadSupport.isDownloadable(url) else { return false }

        if downloads.contains(where: {
            $0.mediaId == mediaId && ($0.state == .queued || $0.state == .downloading || $0.state == .completed)
        }) {
            return false
        }

        let id = UUID().uuidString
        let ext: String = {
            let pathExt = (URL(string: url)?.path as NSString?)?.pathExtension.lowercased() ?? ""
            let allowed: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "wmv", "ts"]
            return allowed.contains(pathExt) ? pathExt : "mp4"
        }()
        let localFileName = "\(id).\(ext)"

        let item = DownloadItem(
            id: id, mediaId: mediaId, type: type, name: name,
            poster: poster, quality: quality,
            remoteURL: url, localFileName: localFileName,
            totalBytes: 0, receivedBytes: 0,
            state: .downloading, createdAt: Date()
        )

        guard let requestURL = URL(string: url) else { return false }
        var request = URLRequest(url: requestURL)
        if let headers {
            for (key, value) in headers where key.caseInsensitiveCompare("Range") != .orderedSame {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let task = session.downloadTask(with: request)
        taskMap[task.taskIdentifier] = item.id
        tasks[item.id] = task
        downloads.append(item)
        persist()
        task.resume()
        return true
    }

    public func delete(_ item: DownloadItem) {
        if let task = tasks[item.id] {
            task.cancel()
            tasks.removeValue(forKey: item.id)
            if let key = taskMap.first(where: { $0.value == item.id })?.key {
                taskMap.removeValue(forKey: key)
            }
        }
        try? FileManager.default.removeItem(at: localURL(for: item))
        downloads.removeAll { $0.id == item.id }
        persist()
    }

    public func localURL(for item: DownloadItem) -> URL {
        downloadsDirectory().appendingPathComponent(item.localFileName)
    }

    // MARK: - Private helpers

    private func downloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Moonlit").appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persistenceURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Moonlit")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(persistenceName)
    }

    private func load() {
        let url = persistenceURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            downloads = []
            return
        }
        downloads = decoded.filter { item in
            if item.state == .completed {
                return FileManager.default.fileExists(atPath: localURL(for: item).path)
            }
            return true
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        try? data.write(to: persistenceURL(), options: .atomic)
    }

    private func updateProgress(taskId: Int, received: Int64, total: Int64) {
        guard let itemId = taskMap[taskId],
              let idx = downloads.firstIndex(where: { $0.id == itemId }) else { return }
        downloads[idx].receivedBytes = received
        downloads[idx].totalBytes = total
        downloads[idx].state = .downloading
        persist()
    }

    private func markCompleted(taskId: Int) {
        guard let itemId = taskMap[taskId],
              let idx = downloads.firstIndex(where: { $0.id == itemId }) else { return }
        downloads[idx].state = .completed
        if downloads[idx].totalBytes > 0 {
            downloads[idx].receivedBytes = downloads[idx].totalBytes
        }
        persist()
    }

    private func markFailed(taskId: Int, error: Error) {
        guard let itemId = taskMap[taskId],
              let idx = downloads.firstIndex(where: { $0.id == itemId }) else { return }
        downloads[idx].state = .failed
        persist()
        _ = error
    }

    private func finishMove(taskId: Int, from tmp: URL) {
        guard let itemId = taskMap[taskId],
              let item = downloads.first(where: { $0.id == itemId }) else {
            try? FileManager.default.removeItem(at: tmp)
            return
        }
        let dest = localURL(for: item)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: tmp, to: dest)
        markCompleted(taskId: taskId)
    }

    // MARK: - Test helpers

    public var persistenceNameForTest: String { persistenceName }

    public func upsertForTest(_ item: DownloadItem) {
        if let idx = downloads.firstIndex(where: { $0.id == item.id }) {
            downloads[idx] = item
        } else {
            downloads.append(item)
        }
        persist()
    }

    public func loadForTest() {
        load()
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated public func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                                        didWriteData _: Int64, totalBytesWritten w: Int64,
                                        totalBytesExpectedToWrite e: Int64) {
        Task { @MainActor in self.updateProgress(taskId: t.taskIdentifier, received: w, total: e) }
    }

    nonisolated public func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                                        didFinishDownloadingTo location: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonlit-dl-\(t.taskIdentifier)-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: tmp)
        Task { @MainActor in self.finishMove(taskId: t.taskIdentifier, from: tmp) }
    }

    nonisolated public func urlSession(_ s: URLSession, task t: URLSessionTask,
                                        didCompleteWithError err: Error?) {
        if let err {
            Task { @MainActor in self.markFailed(taskId: t.taskIdentifier, error: err) }
        }
    }
}
