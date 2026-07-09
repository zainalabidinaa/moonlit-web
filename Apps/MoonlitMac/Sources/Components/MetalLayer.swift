#if canImport(Libmpv)
import QuartzCore
import AppKit

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
        backgroundColor = NSColor.black.cgColor
        wantsExtendedDynamicRangeContent = true
    }
}

final class MPVContainerView: NSView {
    let metalLayer = MetalLayer()
    private var lastDrawableSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer?.addSublayer(metalLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer?.addSublayer(metalLayer)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Keep the Metal layer in lockstep with the view during live window
        // resizes; `layout()` alone can lag a drag, leaving the video smaller
        // than the window.
        updateMetalLayerGeometry()
    }

    override func layout() {
        super.layout()
        updateMetalLayerGeometry()
    }

    private func updateMetalLayerGeometry() {
        let bounds = self.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let scale = window?.screen?.backingScaleFactor ?? 2.0
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
#endif
