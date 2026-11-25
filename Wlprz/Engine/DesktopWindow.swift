//
//  DesktopWindow.swift
//  Wlprz · Wlprz
//
//  The borderless window that sits behind the desktop icons on one display.
//

@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// What a desktop window is currently drawing.
enum DesktopContent: Equatable {
    case video(VideoSessionRef)
    case image(URL)
    case scene(SceneID)

    /// Identity wrapper so content can be compared without comparing players.
    struct VideoSessionRef: Equatable {
        let session: VideoSession
        static func == (a: Self, b: Self) -> Bool { a.session === b.session }
    }
}

/// A window at the desktop level: under icons, on every Space, invisible to the mouse.
final class DesktopWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one display's desktop window and swaps its content.
final class DesktopWindowController {
    let displayID: String
    private let window: DesktopWindow
    private(set) var content: DesktopContent?
    private(set) var wallpaperID: UUID?
    let sceneState = SceneRenderState()
    private var playerLayer: AVPlayerLayer?

    init(display: DisplayInfo) {
        displayID = display.id
        window = DesktopWindow(frame: display.frame)
        sceneState.screenFrame = display.frame
    }

    func updateFrame(_ frame: CGRect) {
        sceneState.screenFrame = frame
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    /// Swaps in new content and brings the window up; identical content is left alone so
    /// players and scenes don't restart on every reconcile.
    func show(_ content: DesktopContent, wallpaperID: UUID) {
        self.wallpaperID = wallpaperID
        guard content != self.content else { return }
        self.content = content
        playerLayer = nil

        switch content {
        case .video(let ref):
            let view = NSView()
            view.wantsLayer = true
            let layer = AVPlayerLayer(player: ref.session.player)
            layer.videoGravity = .resizeAspectFill
            layer.backgroundColor = NSColor.black.cgColor
            view.layer = layer
            playerLayer = layer
            window.contentView = view
        case .image(let url):
            let view = NSView()
            view.wantsLayer = true
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.layer?.contents = NSImage(contentsOf: url)
            window.contentView = view
        case .scene(let scene):
            window.contentView = NSHostingView(rootView: SceneView(scene: scene, state: sceneState))
        }
        window.orderFront(nil)
    }

    /// Applies the HDR preference to video layers.
    func setAllowsHDR(_ allowed: Bool) {
        playerLayer?.preferredDynamicRange = allowed ? .high : .standard
    }

    /// Hides the window and drops its content so the macOS wallpaper shows through.
    func close() {
        window.contentView = nil
        window.orderOut(nil)
        content = nil
        wallpaperID = nil
    }
}
