import SwiftUI
import AppKit
import MoonlitCore

/// One hover-depth treatment for every media/folder tile in MoonlitMac.
/// Cards remain flat at rest; hover adds a restrained artwork/theme tint plus
/// a neutral deeper black lift shadow. Keeping this shared prevents individual
/// pages from drifting into different glow strengths.
struct MacTileGlowModifier: ViewModifier {
    let isHovering: Bool
    let color: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            // Radial halo painted behind the card: brightest immediately around
            // the artwork, decaying in levels to clear on all four sides. A
            // blurred elliptical gradient avoids the hard shadow-silhouette edge
            // ("visible cap") that stacked `.shadow`s produced.
            .background {
                // The poster is opaque, so the halo's readable part is the ring
                // just outside the card. Two blurred slabs give it levels: a
                // tight bright core ring and a wide soft bloom. Blur radius
                // exceeds each slab's overhang so every edge feathers to clear
                // instead of ending in a visible line.
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius + 8, style: .continuous)
                        .fill(color)
                        .padding(-22)
                        .blur(radius: 30)
                        .opacity(0.66)
                    RoundedRectangle(cornerRadius: cornerRadius + 16, style: .continuous)
                        .fill(color)
                        .padding(-46)
                        .blur(radius: 60)
                        .opacity(0.30)
                }
                .opacity(isHovering ? 1 : 0)
            }
            // Retain a soft black lift so the card still separates from the page.
            .shadow(
                color: .black.opacity(isHovering ? 0.40 : 0),
                radius: isHovering ? 16 : 0,
                y: isHovering ? 10 : 0
            )
    }
}

private struct MacArtworkTileGlowModifier: ViewModifier {
    let isHovering: Bool
    let artworkURL: URL?
    let fallbackColor: Color
    let cornerRadius: CGFloat

    @State private var resolvedColor: Color?

    func body(content: Content) -> some View {
        content
            .modifier(MacTileGlowModifier(
                isHovering: isHovering,
                // Never flash the generic accent while an artwork sample is in
                // flight. It was the source of the identical pale/cyan glow on
                // otherwise unrelated posters.
                color: resolvedColor ?? (artworkURL == nil ? fallbackColor : .clear),
                cornerRadius: cornerRadius
            ))
            .task(id: isHovering ? artworkURL?.absoluteString : nil) {
                guard isHovering, let artworkURL else { return }
                if let cached = TileHaloColorStore.shared.cached(for: artworkURL) {
                    resolvedColor = cached
                    return
                }
                if let color = await TileHaloColorStore.shared.resolve(for: artworkURL) {
                    withAnimation(.easeOut(duration: 0.28)) { resolvedColor = color }
                }
            }
            .onChange(of: artworkURL) { _, _ in resolvedColor = nil }
    }
}

private struct MacAutomaticArtworkTileGlowModifier: ViewModifier {
    let artworkURL: URL?
    let fallbackColor: Color
    let cornerRadius: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .modifier(MacArtworkTileGlowModifier(
                isHovering: isHovering,
                artworkURL: artworkURL,
                fallbackColor: fallbackColor,
                cornerRadius: cornerRadius
            ))
            .onHover { isHovering = $0 }
    }
}

extension View {
    func macTileGlow(isHovering: Bool, color: Color, cornerRadius: CGFloat = 16) -> some View {
        modifier(MacTileGlowModifier(
            isHovering: isHovering,
            color: color,
            cornerRadius: cornerRadius
        ))
    }

    func macTileGlow(
        isHovering: Bool,
        artworkURL: URL?,
        fallbackColor: Color,
        cornerRadius: CGFloat = 16
    ) -> some View {
        modifier(MacArtworkTileGlowModifier(
            isHovering: isHovering,
            artworkURL: artworkURL,
            fallbackColor: fallbackColor,
            cornerRadius: cornerRadius
        ))
    }

    @MainActor
    func macTileGlow(isHovering: Bool, artworkURL: URL?, cornerRadius: CGFloat = 16) -> some View {
        macTileGlow(
            isHovering: isHovering,
            artworkURL: artworkURL,
            fallbackColor: MoonlitTheme.accent,
            cornerRadius: cornerRadius
        )
    }

    @MainActor
    func macAutomaticTileGlow(artworkURL: URL?, cornerRadius: CGFloat = 16) -> some View {
        modifier(MacAutomaticArtworkTileGlowModifier(
            artworkURL: artworkURL,
            fallbackColor: MoonlitTheme.accent,
            cornerRadius: cornerRadius
        ))
    }
}

//  focus halo: a soft, image-derived colored glow shown behind a tile
// on hover/focus. Resolves a single chromatic color per tile, with caching so
// repeated hovers are instant.
@MainActor
final class TileHaloColorStore {
    static let shared = TileHaloColorStore()

    private var cache: [String: Color] = [:]
    private var inFlight: [String: Task<Color?, Never>] = [:]

    /// Returns a cached halo color if one was already resolved for this URL.
    func cached(for url: URL) -> Color? { cache[url.absoluteString] }

    /// Resolves (and caches) the halo color for a tile's artwork. Safe to call
    /// repeatedly — in-flight requests are de-duplicated and results are memoized.
    func resolve(for url: URL) async -> Color? {
        let key = url.absoluteString
        if let color = cache[key] { return color }
        if let existing = inFlight[key] { return await existing.value }

        let task: Task<Color?, Never> = Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return nil }
            return image.moonlitTileHaloColor()
        }
        inFlight[key] = task
        let resolved = await task.value
        inFlight[key] = nil

        if let resolved { cache[key] = resolved }
        return resolved
    }
}

private extension NSImage {
    /// Extracts the dominant chromatic color from a small, explicitly RGBA
    /// rendering. Explicit byte order avoids interpreting JPEG channel memory as
    /// ARGB/BGRA differently on different source formats.
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
        let targetWidth = 36
        let targetHeight = max(1, targetWidth * height / width)
        let bytesPerRow = targetWidth * 4
        var pixels = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let didRender = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(self, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard didRender else { return nil }
        return sampleDominantColor(pixels)?.moonlitBoostedForHalo
    }
}

func sampleDominantColor(_ pixels: [UInt8]) -> Color? {
    struct Bucket {
        var weight: Double = 0
        var red: Double = 0
        var green: Double = 0
        var blue: Double = 0
    }

    var buckets: [Int: Bucket] = [:]
    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[offset]) / 255
        let g = Double(pixels[offset + 1]) / 255
        let b = Double(pixels[offset + 2]) / 255
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
        let brightness = maximum

        // Ignore letterboxing, deep shadow, white typography and pale paper.
        // Sampling the unblurred thumbnail preserves smaller chromatic regions
        // that the old box blur washed into grey/white.
        guard brightness > 0.10, brightness < 0.92, saturation > 0.12 else { continue }
        let redBin = Int(r * 15)
        let greenBin = Int(g * 15)
        let blueBin = Int(b * 15)
        let key = (redBin << 8) | (greenBin << 4) | blueBin
        // Chroma (saturation × brightness) squared: a large dark-navy field must
        // lose to a smaller vivid region (e.g. Silo's orange lettering over a
        // navy poster). Dark pixels have near-zero chroma even when "saturated".
        let chroma = saturation * brightness
        let pixelWeight = 0.02 + chroma * chroma * 4.0
        var bucket = buckets[key, default: Bucket()]
        bucket.weight += pixelWeight
        bucket.red += r * pixelWeight
        bucket.green += g * pixelWeight
        bucket.blue += b * pixelWeight
        buckets[key] = bucket
    }

    if let dominant = buckets.values.max(by: { $0.weight < $1.weight }), dominant.weight > 0 {
        return Color(
            red: dominant.red / dominant.weight,
            green: dominant.green / dominant.weight,
            blue: dominant.blue / dominant.weight
        )
    }

    // Monochrome artwork has no honest artwork-derived color. Returning nil is
    // preferable to manufacturing the white halo reported in the screenshots.
    return nil
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

        // Keep the artwork's hue honest; lift saturation/brightness enough to
        // read as a vivid glow, with the fade levels handled by the gradient.
        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation * 1.7, 0.70), 1.0)),
            brightness: Double(min(max(brightness * 1.25, 0.60), 0.95))
        )
    }
}
