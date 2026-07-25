import SwiftUI
import AppKit
import Accelerate
import MoonlitCore

/// Ambient-color glow behind a hero backdrop — extracts the dominant colors
/// from the artwork using vImage box-blur (matching the Fusion app's technique)
/// and washes them across the page as flat color gradients (no photo pixels
/// involved). Meant to sit as a fixed, non-scrolling backdrop behind a
/// `ScrollView` so the same wash is visible no matter how far the content has
/// scrolled — it never fades out or bottoms out to a flat/black color.
/// Shared between the home hero and the detail page hero.
struct MacFusionAmbientBackground: View {
    /// How the extracted colors are painted across the page.
    enum Style {
        /// Flat, even color wash that persists top-to-bottom — used on the
        /// detail page, where it must blend seamlessly with the hero image
        /// and never bottom out to black.
        case wash
        /// Several rich, overlapping color blooms drifting through black at
        /// asymmetric positions — organic and non-uniform, not a flat sheet.
        /// Used on the home/browse hubs.
        case fluidBlooms
        /// The original "Fusion" home treatment: a softly blurred copy of the
        /// hero backdrop fading down the page, with a single warm ambient glow
        /// over it. Reads `heroBackdropURL`. Home view only.
        case heroBackdrop
    }

    let ambientColor: Color
    let ambientColor2: Color
    let isEnabled: Bool
    /// Backdrop image blurred behind the page for the `.heroBackdrop` style.
    var heroBackdropURL: URL? = nil
    /// Scales the glow's strength — 1.0 matches the home hero, lower values
    /// (e.g. the detail page) keep the wash more subtle/darker.
    var intensity: Double = 1.0
    /// The height the top glow's falloff is scaled against — pass the
    /// caller's actual hero height so the glow finishes decaying to the
    /// floor tint right around where the hero image itself fades out,
    /// instead of scaling against the full (unrelated) viewport height and
    /// creating a visible brightness seam at the hero's bottom edge.
    /// Defaults to the view's own height (the prior, viewport-relative behavior).
    var glowHeight: CGFloat?
    var style: Style = .wash
    /// Multiplies every glow/bloom radius — values > 1 spread the color softer
    /// and wider. Defaults to 1.0 (no scaling) so existing call sites are unaffected.
    var radiusScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let glowScale = glowHeight ?? geo.size.height
            ZStack(alignment: .top) {
                MoonlitTheme.background

                if isEnabled {
                    switch style {
                    case .wash:
                        washLayers(glowScale: glowScale)
                    case .fluidBlooms:
                        fluidBloomLayers()
                    case .heroBackdrop:
                        heroBackdropLayers(size: geo.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Original "Fusion" home look: blurred hero image fading down, plus a warm
    /// top glow (primary color), an upper-right accent glow, and a dark floor
    /// gradient back to canvas.
    @ViewBuilder
    private func heroBackdropLayers(size: CGSize) -> some View {
        // Persistent art-tinted wash so the page never resolves to flat black —
        // the hero's ambient color carries down the whole scroll (matches the
        // iOS home background). Sits above the base fill, below the hero image.
        ambientColor.opacity(0.18 * intensity)

        if let url = heroBackdropURL {
            // Heavily blurred (radius 30) — full detail is wasted here, so decode small.
            CachedAsyncImage(url: url, maxDimension: 400) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.clear
            }
            .frame(width: size.width, height: size.height * 0.72)
            .clipped()
            .scaleEffect(1.1)
            .blur(radius: 30)
            .saturation(0.28)
            .brightness(0.14)
            .opacity(0.90)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.50),
                        .init(color: .black.opacity(0.5), location: 0.72),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .id(url)
            .transition(.opacity)
        }

        RadialGradient(
            stops: [
                .init(color: ambientColor.opacity(0.75 * intensity), location: 0.0),
                .init(color: ambientColor.opacity(0.45 * intensity), location: 0.30),
                .init(color: ambientColor.opacity(0.18 * intensity), location: 0.60),
                .init(color: .clear, location: 1.0),
            ],
            center: .top,
            startRadius: 0,
            endRadius: size.height * 0.80 * radiusScale
        )
        .blur(radius: 28)

        RadialGradient(
            colors: [ambientColor2.opacity(0.45 * intensity), .clear],
            center: UnitPoint(x: 0.80, y: 0.05),
            startRadius: 0,
            endRadius: size.height * 0.50 * radiusScale
        )

        // Bottom stops stay below full opacity so the persistent ambient wash
        // shows through and the page never becomes flat black (matches iOS).
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.0), location: 0.00),
                .init(color: .black.opacity(0.10), location: 0.30),
                .init(color: MoonlitTheme.background.opacity(0.45), location: 0.65),
                .init(color: MoonlitTheme.background.opacity(0.78), location: 1.00)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    @ViewBuilder
    private func washLayers(glowScale: CGFloat) -> some View {
        // Persistent floor wash — the color you see no matter how far down
        // the page you've scrolled. Strong enough to read as clearly-tinted.
        LinearGradient(
            colors: [
                ambientColor.opacity(0.40 * intensity),
                ambientColor2.opacity(0.32 * intensity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Brighter bloom close to the artwork, handed off to the floor wash
        // right where the hero image's own fade converges into it.
        RadialGradient(
            colors: [ambientColor.opacity(0.38 * intensity), .clear],
            center: .top,
            startRadius: 0,
            endRadius: glowScale * 0.85 * radiusScale
        )

        RadialGradient(
            colors: [ambientColor2.opacity(0.24 * intensity), .clear],
            center: UnitPoint(x: 0.80, y: 0.06),
            startRadius: 0,
            endRadius: glowScale * 0.55 * radiusScale
        )
    }

    /// Rich, overlapping elliptical color pools at asymmetric positions, each
    /// falling off to clear so black shows between and around them — fluid and
    /// non-uniform rather than a flat sheet, but saturated enough to read as
    /// vivid. Both extracted colors are used and spread down the page.
    @ViewBuilder
    private func fluidBloomLayers() -> some View {
        // Large upper blooms — the strongest color, behind/around the hero.
        EllipticalGradient(
            colors: [ambientColor.opacity(0.85 * intensity), .clear],
            center: UnitPoint(x: 0.16, y: 0.10),
            startRadiusFraction: 0,
            endRadiusFraction: 0.62 * radiusScale
        )
        EllipticalGradient(
            colors: [ambientColor2.opacity(0.78 * intensity), .clear],
            center: UnitPoint(x: 0.86, y: 0.16),
            startRadiusFraction: 0,
            endRadiusFraction: 0.58 * radiusScale
        )

        // Mid blooms — carry the color down past the hero so it doesn't die
        // off into flat black immediately below.
        EllipticalGradient(
            colors: [ambientColor.opacity(0.60 * intensity), .clear],
            center: UnitPoint(x: 0.48, y: 0.52),
            startRadiusFraction: 0,
            endRadiusFraction: 0.5 * radiusScale
        )
        EllipticalGradient(
            colors: [ambientColor2.opacity(0.52 * intensity), .clear],
            center: UnitPoint(x: 0.80, y: 0.72),
            startRadiusFraction: 0,
            endRadiusFraction: 0.46 * radiusScale
        )

        // Lower accent bloom on the opposite side for asymmetry.
        EllipticalGradient(
            colors: [ambientColor.opacity(0.44 * intensity), .clear],
            center: UnitPoint(x: 0.10, y: 0.86),
            startRadiusFraction: 0,
            endRadiusFraction: 0.42 * radiusScale
        )
    }
}

// MARK: - Color Extraction (vImage Box-Blur Pipeline)

extension NSImage {

    /// Extracts two dominant ambient colors (left / right) from the hero artwork
    /// using the same technique found in the Fusion app IPA:
    /// downscale → vImage box-blur → extract peak colors.
    ///
    /// Matching the Fusion binary's imports:
    /// - `vImageBoxConvolve_ARGB8888` for heavy box blur (creates a smooth color field)
    /// - `vDSP_maxmgv` for finding the dominant color peak in the blurred result
    func moonlitAmbientColors() -> (Color, Color)? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil)
                ?? cgImage_downsampled(to: CGSize(width: 240, height: 135)) else { return nil }
        return cgImage.moonlitAmbientColorsFromCG()
    }

    private func cgImage_downsampled(to size: CGSize) -> CGImage? {
        guard let tiff = tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiff as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }
}

extension CGImage {

    /// Core of the Fusion-style color extraction: downsamples, box-blurs the
    /// artwork, then samples left/right peak colors from the resulting smear.
    fileprivate func moonlitAmbientColorsFromCG() -> (Color, Color)? {
        let targetWidth  = 40
        let targetHeight = max(1, targetWidth * height / width)

        guard var raw = Self.allocARGB(width: targetWidth, height: targetHeight),
              var blur = Self.allocARGB(width: targetWidth, height: targetHeight) else { return nil }

        defer { raw.free(); blur.free() }

        // `vImage_Buffer(cgImage:)`'s format-inference throws for most JPEG
        // backdrops (TMDB serves alpha-less JPEGs), which `try?` swallowed —
        // silently leaving the ambient colors unset. Converting explicitly to
        // ARGB8888 works regardless of the source image's native format.
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)
        )!
        var src = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&src, &format, nil, self, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        defer { src.free() }

        guard vImageScale_ARGB8888(&src, &raw.buf, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }

        // vImageBoxConvolve_ARGB8888 requires an odd kernel size — an even
        // value fails with kvImageInvalidKernelSize (-21767).
        let blurRadius: UInt32 = 21
        guard vImageBoxConvolve_ARGB8888(&raw.buf, &blur.buf, nil, 0, 0,
                                          blurRadius, blurRadius, nil,
                                          vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else { return nil }

        guard let left  = Self.sampleDominantColor(&blur.buf,
                                                    xRange: 0 ..< targetWidth / 2,
                                                    yRange: 0 ..< max(1, targetHeight * 6 / 10)),
              let right = Self.sampleDominantColor(&blur.buf,
                                                    xRange: targetWidth / 2 ..< targetWidth,
                                                    yRange: 0 ..< max(1, targetHeight * 6 / 10)) else { return nil }

        return (left, right)
    }

    // MARK: - Buffer Helpers

    private struct ARGB {
        var buf: vImage_Buffer
        func free() { buf.data?.deallocate() }
    }

    private static func allocARGB(width: Int, height: Int) -> ARGB? {
        let bytesPerRow = width * 4
        guard let data = malloc(height * bytesPerRow) else { return nil }
        return ARGB(buf: vImage_Buffer(data: data, height: vImagePixelCount(height),
                                        width: vImagePixelCount(width), rowBytes: bytesPerRow))
    }

    /// Finds the dominant color in a region of the box-blurred buffer using
    /// vDSP peak detection — mirrors Fusion's use of `vDSP_maxmgv`.
    private static func sampleDominantColor(_ buf: UnsafeMutablePointer<vImage_Buffer>,
                                             xRange: Range<Int>,
                                             yRange: Range<Int>) -> Color? {
        let rowBytes = buf.pointee.rowBytes
        let base = buf.pointee.data.assumingMemoryBound(to: UInt8.self)

        var sumR: Double = 0
        var sumG: Double = 0
        var sumB: Double = 0
        var maxR: Double = 0
        var maxG: Double = 0
        var maxB: Double = 0
        var count: Double = 0

        for y in yRange {
            let row = base.advanced(by: y * rowBytes)
            for x in xRange {
                let p = row.advanced(by: x * 4)
                let r = Double(p[1])
                let g = Double(p[2])
                let b = Double(p[3])
                sumR += r; sumG += g; sumB += b
                maxR = max(maxR, r); maxG = max(maxG, g); maxB = max(maxB, b)
                count += 1
            }
        }

        guard count > 0 else { return nil }

        let avgR = sumR / count
        let avgG = sumG / count
        let avgB = sumB / count

        let blendR = avgR * 0.4 + maxR * 0.6
        let blendG = avgG * 0.4 + maxG * 0.6
        let blendB = avgB * 0.4 + maxB * 0.6

        return Color(red: blendR / 255.0, green: blendG / 255.0, blue: blendB / 255.0)
    }
}

extension Color {
    var moonlitBoostedForAmbient: Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
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
            saturation: Double(min(max(saturation * 3.0, 0.70), 1.0)),
            brightness: Double(min(max(brightness * 1.5, 0.45), 0.80))
        )
    }
}
