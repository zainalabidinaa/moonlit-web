import Foundation
import ImageIO
import CoreGraphics

#if os(macOS)
import AppKit
public typealias MoonlitImage = NSImage
#elseif os(iOS) || os(tvOS)
import UIKit
public typealias MoonlitImage = UIImage
#endif

public enum MoonlitImageCache {
    private static let queue = DispatchQueue(label: "moonlit.imgcache", qos: .utility, attributes: .concurrent)

    /// Bounded in-memory cache of already-decoded, downsampled images.
    /// `NSCache` is thread-safe and evicts automatically under memory pressure,
    /// so scrolling never accumulates unbounded decoded bitmaps.
    // `NSCache` is internally thread-safe, so it's safe to share across threads
    // even though it isn't `Sendable`; `nonisolated(unsafe)` tells Swift 6's
    // strict concurrency checker that synchronization is handled by the class.
    nonisolated(unsafe) private static let memory: NSCache<NSString, MoonlitImage> = {
        let cache = NSCache<NSString, MoonlitImage>()
        cache.totalCostLimit = 96 * 1024 * 1024 // ~96 MB of decoded pixels
        return cache
    }()

    /// Longest-edge pixel cap used when a caller doesn't pass its own.
    ///
    /// ── TUNABLE (your call) ────────────────────────────────────────────
    /// Trade-off: larger = crisper artwork on big/Retina tiles but more memory
    /// and slower decode; smaller = leaner + smoother scrolling but soft on
    /// large surfaces. Posters render at roughly 150–260 pt, so ~2× that in
    /// pixels is plenty. Hero/detail surfaces that need full resolution can
    /// pass a large value at the call site to effectively opt out.
    public static let defaultMaxDimension: CGFloat = 640

    private static let root: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitImages")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func fileURL(for url: URL) -> URL {
        let key = url.absoluteString.data(using: .utf8)?.base64EncodedString() ?? url.lastPathComponent
        return root.appendingPathComponent(key)
    }

    private static func memoryKey(for url: URL, maxDimension: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(maxDimension.rounded()))" as NSString
    }

    /// Wrapper so a decoded image can cross the background-queue → caller boundary
    /// under Swift concurrency checking. Decoded images are immutable in practice.
    private struct SendableImage: @unchecked Sendable {
        let image: MoonlitImage
    }

    // MARK: - Public: raw bytes (unchanged API, still used by iOS loader)

    public static func cachedData(for url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url))
    }

    public static func store(data: Data, for url: URL) {
        let file = fileURL(for: url)
        queue.async { try? data.write(to: file, options: .atomic) }
    }

    public static func syncImage(for url: URL, maxDimension: CGFloat = defaultMaxDimension) -> MoonlitImage? {
        memory.object(forKey: memoryKey(for: url, maxDimension: maxDimension))
    }

    // MARK: - Public: decoded images (memory → disk, off-main, downsampled)

    /// Returns a decoded, downsampled image from the memory cache or disk cache.
    /// Disk read + decode run off the main thread. Returns `nil` if not cached.
    public static func image(for url: URL, maxDimension: CGFloat = defaultMaxDimension) async -> MoonlitImage? {
        if let cached = memory.object(forKey: memoryKey(for: url, maxDimension: maxDimension)) {
            return cached
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<SendableImage?, Never>) in
            queue.async {
                guard let data = try? Data(contentsOf: fileURL(for: url)),
                      let decoded = decodeDownsampled(data, maxDimension: maxDimension) else {
                    cont.resume(returning: nil)
                    return
                }
                store(decoded, for: url, maxDimension: maxDimension)
                cont.resume(returning: SendableImage(image: decoded.image))
            }
        }?.image
    }

    /// Persists freshly-fetched bytes to disk, then decodes a downsampled image
    /// off the main thread and populates the memory cache. Returns the image.
    public static func ingest(data: Data, url: URL, maxDimension: CGFloat = defaultMaxDimension) async -> MoonlitImage? {
        store(data: data, for: url)
        return await withCheckedContinuation { (cont: CheckedContinuation<SendableImage?, Never>) in
            queue.async {
                guard let decoded = decodeDownsampled(data, maxDimension: maxDimension) else {
                    cont.resume(returning: nil)
                    return
                }
                store(decoded, for: url, maxDimension: maxDimension)
                cont.resume(returning: SendableImage(image: decoded.image))
            }
        }?.image
    }

    // MARK: - Decode + downsample (ImageIO)

    private static func store(_ decoded: (image: MoonlitImage, cost: Int), for url: URL, maxDimension: CGFloat) {
        memory.setObject(decoded.image, forKey: memoryKey(for: url, maxDimension: maxDimension), cost: decoded.cost)
    }

    /// Decodes `data` to an image whose longest edge is at most `maxDimension` px,
    /// using ImageIO's thumbnail path so the full-resolution bitmap is never
    /// allocated. `cost` is the decoded byte size, used for NSCache eviction.
    private static func decodeDownsampled(_ data: Data, maxDimension: CGFloat) -> (image: MoonlitImage, cost: Int)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxDimension),
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let cost = cg.height * cg.bytesPerRow
        #if os(macOS)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #elseif os(iOS) || os(tvOS)
        let image = UIImage(cgImage: cg)
        #endif
        return (image, cost)
    }
}
