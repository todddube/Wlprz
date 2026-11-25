//
//  SceneView.swift
//  Wlprz · Wlprz
//
//  Renders a built-in shader scene at a policy-controlled frame rate and resolution.
//

import AppKit
import Observation
import SwiftUI

/// Live render parameters for one scene window, changed by the engine without rebuilding views.
@Observable
final class SceneRenderState {
    var maxFPS = PlaybackPolicy.baseFPS
    var resolutionScale = 1.0
    var isPaused = false
    /// The display frame in AppKit coordinates, used to map the global pointer into the view.
    var screenFrame: CGRect?
}

/// A shader scene that follows the pointer.
///
/// The pointer is read from `NSEvent.mouseLocation` each frame instead of from events:
/// desktop windows ignore the mouse, and polling needs no Input Monitoring permission.
struct SceneView: View {
    let scene: SceneID
    let state: SceneRenderState

    @State private var pointer = PointerTracker()
    private let epoch = Date()

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, max(0.25, state.resolutionScale))
            let renderSize = CGSize(width: proxy.size.width * scale, height: proxy.size.height * scale)
            TimelineView(.animation(minimumInterval: 1 / Double(max(1, state.maxFPS)), paused: state.isPaused)) { context in
                let (point, press) = pointer.sample(screenFrame: state.screenFrame, viewSize: proxy.size)
                // Wrapping keeps float precision in the shader; the seam is once every ~2.7 h.
                let time = context.date.timeIntervalSince(epoch).truncatingRemainder(dividingBy: 10_000)
                Rectangle()
                    .fill(.black)
                    .frame(width: renderSize.width, height: renderSize.height)
                    .colorEffect(Shader(
                        function: ShaderFunction(library: .default, name: scene.rawValue),
                        arguments: [
                            .float2(renderSize),
                            .float(time),
                            .float2(point.x * scale, point.y * scale),
                            .float(press),
                        ]
                    ))
                    // Rasterise at the reduced size, then upscale: that is where Efficient saves GPU time.
                    .drawingGroup()
                    .scaleEffect(1 / scale, anchor: .topLeading)
            }
        }
        .ignoresSafeArea()
    }
}

/// Smooths mouse-button state into a 0…1 "press" value and maps the pointer into view space.
final class PointerTracker {
    private var press = 0.0
    private var lastSample = Date()

    func sample(screenFrame: CGRect?, viewSize: CGSize) -> (CGPoint, Double) {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastSample))
        lastSample = now
        let target = NSEvent.pressedMouseButtons & 1 == 1 ? 1.0 : 0.0
        press += (target - press) * min(1, dt * (target > press ? 12 : 3))

        guard let frame = screenFrame else {
            return (CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), press)
        }
        let mouse = NSEvent.mouseLocation
        // AppKit's origin is bottom-left; the shader expects top-left like SwiftUI.
        return (CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y), press)
    }
}
