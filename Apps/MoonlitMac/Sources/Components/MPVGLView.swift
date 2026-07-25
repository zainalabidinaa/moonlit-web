#if canImport(Libmpv)
import AppKit
import OpenGL.GL
import OpenGL.GL3
import Libmpv

/// App-owned OpenGL view that renders mpv via the libmpv render API
/// (`vo=libmpv` + `MPV_RENDER_API_TYPE_OPENGL`).
///
/// Why not `wid` + CAMetalLayer? On the `wid`/MoltenVK embedding path mpv owns
/// its Vulkan swapchain and only recreates it on a `SUBOPTIMAL` present, which
/// never fires when we drive `drawableSize` ourselves — so resizing (especially
/// while paused) leaves the video anchored to a corner with black bars.
///
/// With the render API the app owns the render loop: every `draw(_:)` we hand
/// mpv an FBO sized from the current viewport, so the target can never be stale.
/// This is the same approach shipping mpv apps (IINA, Fusion, and similar players) use on
/// macOS, and it makes live window resize and PiP monitor moves "just work".
final class MPVGLView: NSOpenGLView {
    /// Set by the engine after it creates the render context on this view's
    /// GL context. `draw(_:)` renders through it; nil renders black.
    var mpvGL: OpaquePointer? {
        didSet { needsDisplay = true }
    }

    private var defaultFBO: GLint = 0
    /// True while AppKit is doing a live window drag. During this we render only
    /// from `reshape()` (one draw per resize step) and ignore mpv's playback
    /// update-callback redraws, so the two don't contend for the GL context and
    /// make the drag stutter while video is playing.
    private var isLiveResizing = false

    override class func defaultPixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion3_2Core),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), NSOpenGLPixelFormatAttribute(32),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAllowOfflineRenderers),
            NSOpenGLPixelFormatAttribute(0)
        ]
        // Fall back to a permissive format if the core profile isn't available.
        return NSOpenGLPixelFormat(attributes: attributes)
            ?? NSOpenGLPixelFormat(attributes: [
                NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
                NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), NSOpenGLPixelFormatAttribute(32),
                NSOpenGLPixelFormatAttribute(0)
            ])!
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        wantsBestResolutionOpenGLSurface = true
        autoresizingMask = [.width, .height]
        // Sync buffer swaps to the display refresh to avoid tearing.
        openGLContext?.setValues([1], for: .swapInterval)
    }

    /// Resolves GL function pointers for libmpv from the system OpenGL framework.
    static func getProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
        guard let name else { return nil }
        let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
        let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
        return CFBundleGetFunctionPointerForName(bundle, symbol)
    }

    /// Requests a redraw from any thread. mpv's render-update callback fires on
    /// its render thread; marshal onto main and let AppKit coalesce.
    func requestRedraw() {
        if Thread.isMainThread {
            // During a live drag `reshape()` owns rendering; skip callback-driven
            // redraws so playback frames don't contend with the resize renders.
            guard !isLiveResizing else { return }
            needsDisplay = true
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isLiveResizing else { return }
                self.needsDisplay = true
            }
        }
    }

    // MARK: - Resize tracking
    //
    // NSOpenGLView only repaints when we mark it dirty. During a live window drag
    // mpv delivers no new frames (especially while paused), so without forcing a
    // synchronous render here the video surface would lag the window edge (or
    // freeze) while the SwiftUI controls reflow — making the whole player look
    // "stuck". `reshape()` fires on every AppKit resize step; render immediately
    // so the video fills the new bounds on the same frame as the window.
    //
    // Crucially we drop vsync (swap-interval 0) for the duration of a live resize:
    // with swap-interval 1 every `flushBuffer()` blocks until the next vsync, and
    // resizing fires many renders per second — that vsync stall is what makes the
    // drag feel laggy. We restore vsync when the drag ends.

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        isLiveResizing = true
        openGLContext?.setValues([0], for: .swapInterval)
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        isLiveResizing = false
        openGLContext?.setValues([1], for: .swapInterval)
        renderNow()
    }

    override func reshape() {
        super.reshape()
        renderNow()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Backing scale can change when moving between displays (e.g. PiP across
        // monitors); re-render at the new pixel size.
        renderNow()
    }

    /// Draw the current mpv frame synchronously at the current size. Safe to call
    /// during live resize; no-op until the GL context/render context exist.
    private func renderNow() {
        guard mpvGL != nil, openGLContext != nil else { return }
        draw(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = openGLContext else { return }
        ctx.makeCurrentContext()
        CGLLockContext(ctx.cglContextObj!)
        defer {
            CGLUnlockContext(ctx.cglContextObj!)
        }

        guard let mpvGL else {
            glClearColor(0, 0, 0, 1)
            glClear(UInt32(GL_COLOR_BUFFER_BIT))
            ctx.flushBuffer()
            return
        }

        // The FBO size must match the actual backing pixels of the viewport so
        // mpv renders at full size after every resize / scale change.
        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO)
        let backing = convertToBacking(bounds)
        let width = Int32(max(1, backing.width.rounded()))
        let height = Int32(max(1, backing.height.rounded()))

        var fbo = mpv_opengl_fbo(fbo: Int32(defaultFBO), w: width, h: height, internal_format: 0)
        var flip: CInt = 1
        withUnsafeMutablePointer(to: &flip) { flipPtr in
            withUnsafeMutablePointer(to: &fbo) { fboPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param()
                ]
                mpv_render_context_render(mpvGL, &params)
            }
        }
        ctx.flushBuffer()
    }
}
#endif
