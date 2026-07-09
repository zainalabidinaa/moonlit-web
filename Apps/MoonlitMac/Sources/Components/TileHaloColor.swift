import SwiftUI
import AppKit
import Accelerate

// Harbor-style focus halo: a soft, image-derived colored glow shown behind a tile
// on hover/focus. Uses the same vImage box-blur pipeline as the home hero ambient
// background but resolves a single vibrant color per tile, with caching so
// repeated hovers are instant.
@MainActor
final class TileHaloColorStore {
    static let shared = TileHaloColorStore()

    private var cache: [String: Color] = [:]
    private var inFlight: Set<String> = []

    /// Returns a cached halo color if one was already resolved for this URL.
    func cached(for url: URL) -> Color? { cache[url.absoluteString] }

    /// Resolves (and caches) the halo color for a tile's artwork. Safe to call
    /// repeatedly — in-flight requests are de-duplicated and results are memoized.
    func resolve(for url: URL) async -> Color? {
        let key = url.absoluteString
        if let color = cache[key] { return color }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let resolved: Color? = await Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return nil }
            return image.moonlitTileHaloColor()
        }.value

        if let resolved { cache[key] = resolved }
        return resolved
    }
}

private extension NSImage {
    /// Extracts the dominant color from tile artwork using the vImage box-blur
    /// pipeline: downscale → box-blur → peak-color extraction.
    func moonlitTileHaloColor() -> Color? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) ?? cgImage_downsampled(to: CGSize(width: 80, height: 45)) else {
            return nil
        }
        return cg.moonlitTileHaloColorFromCG()
    }

    private func cgImage_downsampled(to size: CGSize) -> CGImage? {
        guard let tiff = tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiff as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}

private extension CGImage {
    func moonlitTileHaloColorFromCG() -> Color? {
        let targetWidth  = 20
        let targetHeight = max(1, targetWidth * height / width)

        guard var raw = allocARGB(width: targetWidth, height: targetHeight),
              var blur = allocARGB(width: targetWidth, height: targetHeight) else { return nil }
        defer { raw.free(); blur.free() }

        // `vImage_Buffer(cgImage:)`'s format inference throws for most JPEG
        // posters (TMDB serves alpha-less JPEGs), which `try?` swallowed —
        // silently leaving every tile's halo color unset. Converting explicitly
        // to ARGB8888 works regardless of the source image's native format.
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)
        )!
        var src = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&src, &format, nil, self, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        defer { src.free() }

        guard vImageScale_ARGB8888(&src, &raw.buf, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return nil }

        let radius: UInt32 = 8
        guard vImageBoxConvolve_ARGB8888(&raw.buf, &blur.buf, nil, 0, 0,
                                          radius, radius, nil,
                                          vImage_Flags(kvImageEdgeExtend)) == kvImageNoError
        else { return nil }

        return sampleDominantColor(&blur.buf,
                                    xRange: 0 ..< targetWidth,
                                    yRange: 0 ..< targetHeight)?
            .moonlitBoostedForHalo
    }
}

private func allocARGB(width: Int, height: Int) -> ARGBBuffer? {
    let bytesPerRow = width * 4
    guard let data = malloc(height * bytesPerRow) else { return nil }
    return ARGBBuffer(buf: vImage_Buffer(data: data, height: vImagePixelCount(height),
                                          width: vImagePixelCount(width), rowBytes: bytesPerRow))
}

private struct ARGBBuffer {
    var buf: vImage_Buffer
    func free() { buf.data?.deallocate() }
}

private func sampleDominantColor(_ buf: UnsafeMutablePointer<vImage_Buffer>,
                                  xRange: Range<Int>,
                                  yRange: Range<Int>) -> Color? {
    let rowBytes = buf.pointee.rowBytes
    let base = buf.pointee.data.assumingMemoryBound(to: UInt8.self)

    var sumR: Double = 0, sumG: Double = 0, sumB: Double = 0
    var maxR: Double = 0, maxG: Double = 0, maxB: Double = 0
    var count: Double = 0

    for y in yRange {
        let row = base.advanced(by: y * rowBytes)
        for x in xRange {
            let p = row.advanced(by: x * 4)
            let r = Double(p[1]), g = Double(p[2]), b = Double(p[3])
            sumR += r; sumG += g; sumB += b
            maxR = max(maxR, r); maxG = max(maxG, g); maxB = max(maxB, b)
            count += 1
        }
    }

    guard count > 0 else { return nil }

    return Color(
        red:   (sumR / count * 0.4 + maxR * 0.6) / 255.0,
        green: (sumG / count * 0.4 + maxG * 0.6) / 255.0,
        blue:  (sumB / count * 0.4 + maxB * 0.6) / 255.0
    )
}

private extension Color {
    /// Pushes saturation up and clamps brightness so washed-out averages still read
    /// as a deliberate accent glow (matches the home hero's ambient boost).
    var moonlitBoostedForHalo: Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        let brightness = maxC

        if delta > 0.001 {
            saturation = delta / maxC
            if r == maxC {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if g == maxC {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation * 2.0, 0.55), 1.0)),
            brightness: Double(min(max(brightness * 1.25, 0.45), 0.80))
        )
    }
}
