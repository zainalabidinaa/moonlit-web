import QuartzCore
import UIKit

/// Metal layer for mpv video rendering. Mirrors the reference MetalLayer config.
final class MetalLayer: CAMetalLayer {
    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        pixelFormat = .bgra8Unorm
        framebufferOnly = true
        contentsGravity = .resize
        backgroundColor = UIColor.black.cgColor
#if os(iOS) || os(macOS)
        wantsExtendedDynamicRangeContent = true
#endif
    }
}

/// Host view that keeps the mpv Metal layer sized to the view on every layout pass.
/// mpv renders into `metalLayer`'s drawables via `wid`; if the layer's frame and
/// `drawableSize` aren't kept in sync with the view bounds, the video renders tiny
/// in the top-left corner. Mirrors the reference `layoutMetalLayer()`.
final class MPVContainerView: UIView {
    let metalLayer = MetalLayer()
    private var lastDrawableSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(metalLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        layer.addSublayer(metalLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        let drawable = CGSize(
            width: (bounds.width * scale).rounded(.toNearestOrAwayFromZero),
            height: (bounds.height * scale).rounded(.toNearestOrAwayFromZero)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = scale
        metalLayer.frame = bounds
        if drawable != lastDrawableSize {
            metalLayer.drawableSize = drawable
            lastDrawableSize = drawable
        }
        CATransaction.commit()
    }
}
