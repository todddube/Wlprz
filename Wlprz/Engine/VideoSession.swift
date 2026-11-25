//
//  VideoSession.swift
//  Wlprz · Wlprz
//
//  One looping video decode, shared by every display that shows the same wallpaper.
//

@preconcurrency import AVFoundation
import os

/// Owns the player for a video wallpaper.
///
/// A single `AVQueuePlayer` can feed several `AVPlayerLayer`s, so mirroring a video to
/// three displays costs one decode, not three.
final class VideoSession {
    let wallpaperID: UUID
    let player = AVQueuePlayer()
    private let url: URL
    private var looper: AVPlayerLooper?
    private(set) var isUnloaded = false

    init(wallpaperID: UUID, url: URL) {
        self.wallpaperID = wallpaperID
        self.url = url
        // A wallpaper must never keep the display awake.
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.isMuted = true
        player.actionAtItemEnd = .advance
        load()
    }

    deinit {
        looper?.disableLooping()
    }

    /// Resumes playback, reloading the looper first if the session was unloaded.
    func play() {
        if isUnloaded { load() }
        if player.rate == 0 { player.play() }
    }

    func pause() { player.pause() }

    /// Drops decoded frames and buffers after the wallpaper has been hidden for a while.
    func unload() {
        guard !isUnloaded else { return }
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        isUnloaded = true
    }

    func setAudio(muted: Bool, volume: Double) {
        player.isMuted = muted
        player.volume = Float(volume)
    }

    private func load() {
        let template = AVPlayerItem(asset: AVURLAsset(url: url))
        looper = AVPlayerLooper(player: player, templateItem: template)
        isUnloaded = false
    }
}
