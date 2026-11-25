//
//  SceneMetalView.swift
//  Wlprz · Wlprz
//
//  Draws a shader scene on the desktop with a dedicated Metal pipeline, at the policy's
//  frame rate and resolution.
//

import AppKit
import MetalKit
import Observation
import os

/// Must match `SceneUniforms` in Scenes.metal.
///
/// Three 8-byte-aligned `float2`s, then four 4-byte scalars: 40 bytes in both languages with
/// no implicit padding, so field order is the only thing that can drift.
private struct SceneUniforms {
    var size: SIMD2<Float>
    var pointer: SIMD2<Float>
    var drawable: SIMD2<Float>
    var time: Float
    var press: Float
    var scene: Int32
    var pad: Int32 = 0
}

/// The Metal device, queue and pipeline, created once and shared by every desktop window.
private final class SceneRenderer {
    static let shared = SceneRenderer()

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLRenderPipelineState
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    private init?() {
        let log = Logger(subsystem: "com.todddube.Wlprz", category: "SceneRenderer")
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            log.error("No Metal device or shader library")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "sceneVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "sceneFragment")
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            log.error("Scene pipeline failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        self.device = device
        self.queue = queue
    }
}

/// A desktop scene drawn straight into a `CAMetalLayer`.
///
/// Why not SwiftUI's `colorEffect` (still used for library thumbnails): on the desktop it
/// rendered every frame offscreen (`drawingGroup`) and then composited it again through
/// SwiftUI, which cost far more GPU time than the shader itself. Here one fragment pass
/// writes the drawable, `preferredFramesPerSecond` is the policy's cap, a paused scene
/// draws nothing, and the drawable is sized to the policy's resolution scale.
final class SceneMetalView: MTKView, MTKViewDelegate {
    private let scene: SceneID
    /// The `switch (u.scene)` case in `sceneFragment`, which follows `SceneID.allCases` order.
    private let sceneIndex: Int32
    private let state: SceneRenderState
    private let renderer: SceneRenderer
    private let pointer = PointerTracker()
    private let epoch = Date()
    #if DEBUG
    /// Debug builds log the real frame rate every 5 s, to check the policy's cap holds.
    private var framesDrawn = 0
    /// GPU milliseconds spent on frames, summed by command-buffer completion handlers.
    private let gpuMilliseconds = OSAllocatedUnfairLock(initialState: 0.0)
    private var countingSince = Date()
    private static let fpsLog = Logger(subsystem: "com.todddube.Wlprz", category: "SceneFPS")
    #endif

    /// `nil` when Metal is unavailable; the caller falls back to the SwiftUI view.
    init?(scene: SceneID, state: SceneRenderState) {
        guard let renderer = SceneRenderer.shared else { return nil }
        self.scene = scene
        self.sceneIndex = scene.metalIndex
        self.state = state
        self.renderer = renderer
        super.init(frame: .zero, device: renderer.device)
        delegate = self
        colorPixelFormat = SceneRenderer.pixelFormat
        framebufferOnly = true
        autoResizeDrawable = false // sized by resolution scale in `updateDrawableSize`
        enableSetNeedsDisplay = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        layer?.isOpaque = true
        // Colour-match like SwiftUI does for the thumbnails; without it, wide-gamut (P3)
        // displays show the scenes oversaturated.
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // The drawable is smaller than the view (see `SceneID.renderDetail`); upscale smoothly.
        layer?.magnificationFilter = .linear
        applyState()
        observeState()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        redrawIfPausedAfterResize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redrawIfPausedAfterResize()
    }

    /// A paused view never draws on its own, so a view created while paused (user pause,
    /// Still, pause on battery) would stay black. Draw once whenever its size settles.
    private func redrawIfPausedAfterResize() {
        if updateDrawableSize(), isPaused { draw() }
    }

    // MARK: - Policy

    /// Re-applies the render state whenever the engine changes it.
    private func observeState() {
        withObservationTracking {
            _ = (state.maxFPS, state.isPaused, state.resolutionScale)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyState()
                self?.observeState()
            }
        }
    }

    private func applyState() {
        preferredFramesPerSecond = max(1, state.maxFPS)
        isPaused = state.isPaused
        updateDrawableSize()
        if state.isPaused { draw() } // leave one current frame on screen, not a stale one
    }

    /// - Returns: whether the drawable size changed.
    @discardableResult
    private func updateDrawableSize() -> Bool {
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let scale = backing * scene.renderDetail * min(1, max(0.25, state.resolutionScale))
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size.width > 0, size.height > 0, drawableSize != size else { return false }
        drawableSize = size
        return true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard bounds.width > 0,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commands = renderer.queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let (point, press) = pointer.sample(screenFrame: state.screenFrame, viewSize: bounds.size)
        // Wrapping keeps float precision in the shader; the seam is once every ~2.7 h.
        let time = Date().timeIntervalSince(epoch).truncatingRemainder(dividingBy: 10_000)
        var uniforms = SceneUniforms(
            size: SIMD2(Float(bounds.width), Float(bounds.height)),
            pointer: SIMD2(Float(point.x), Float(point.y)),
            drawable: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(time),
            press: Float(press),
            scene: sceneIndex
        )
        encoder.setRenderPipelineState(renderer.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        #if DEBUG
        let gpu = gpuMilliseconds
        commands.addCompletedHandler { buffer in
            let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            gpu.withLock { $0 += ms }
        }
        #endif
        commands.commit()
        #if DEBUG
        framesDrawn += 1
        let elapsed = Date().timeIntervalSince(countingSince)
        if elapsed >= 5 {
            let fps = Double(framesDrawn) / elapsed
            let gpuPerFrame = gpuMilliseconds.withLock { total in
                defer { total = 0 }
                return total / Double(max(1, framesDrawn))
            }
            Self.fpsLog.debug("\(self.scene.rawValue, privacy: .public): \(fps, format: .fixed(precision: 1)) fps, cap \(self.preferredFramesPerSecond), drawable \(Int(self.drawableSize.width))×\(Int(self.drawableSize.height)), GPU \(gpuPerFrame, format: .fixed(precision: 2)) ms/frame")
            framesDrawn = 0
            countingSince = Date()
        }
        #endif
    }
}
