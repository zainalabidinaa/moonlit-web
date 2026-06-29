import MoonlitCore
import SwiftUI
import AppKit

struct AnimatedRemoteImage: NSViewRepresentable {
    let url: URL
    let contentMode: CALayerContentsGravity

    func makeNSView(context: Context) -> GIFImageView {
        let view = GIFImageView()
        view.imageScaling = {
            switch contentMode {
            case .resizeAspectFill: return .scaleAxesIndependently
            case .resizeAspect: return .scaleProportionallyUpOrDown
            default: return .scaleAxesIndependently
            }
        }()
        return view
    }

    func updateNSView(_ view: GIFImageView, context: Context) {
        Task {
            let frames = await Self.loadFrames(from: url)
            await MainActor.run { view.setFrames(frames) }
        }
    }

    static func loadFrames(from url: URL) async -> [AnimatedGIFFrame] {
        if let data = MoonlitImageCache.cachedData(for: url) {
            return decodeFrames(from: data)
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        MoonlitImageCache.store(data: data, for: url)
        return decodeFrames(from: data)
    }

    private static func decodeFrames(from data: Data) -> [AnimatedGIFFrame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        var frames: [AnimatedGIFFrame] = []
        let count = CGImageSourceGetCount(source)
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let duration = frameDuration(source: source, index: index)
            frames.append(AnimatedGIFFrame(image: cgImage, duration: duration))
        }
        return frames
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.08 }
        return gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
            ?? gif[kCGImagePropertyGIFDelayTime] as? TimeInterval
            ?? 0.08
    }
}

struct AnimatedGIFFrame {
    let image: CGImage
    let duration: TimeInterval
}

final class GIFImageView: NSImageView {
    private var frameTimer: Timer?
    private var frames: [AnimatedGIFFrame] = []
    private var currentFrameIndex: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        animates = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animates = false
    }

    func setFrames(_ frames: [AnimatedGIFFrame]) {
        frameTimer?.invalidate()
        self.frames = frames
        currentFrameIndex = 0

        guard !frames.isEmpty else { return }

        image = NSImage(cgImage: frames[0].image, size: .zero)
        if frames.count > 1 {
            startAnimating()
        }
    }

    private func startAnimating() {
        guard frames.count > 1 else { return }
        let interval = max(frames[0].duration, 0.02)
        frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, !self.frames.isEmpty else { return }
            self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frames.count
            DispatchQueue.main.async {
                self.image = NSImage(cgImage: self.frames[self.currentFrameIndex].image, size: .zero)
            }
        }
    }

    deinit {
        frameTimer?.invalidate()
    }
}
