//
//  Preferences.swift
//  Wlprz · Wlprz
//
//  User settings and per-display assignments, persisted with the library.
//

import Foundation

/// What a display shows: one wallpaper, or a rotating playlist.
nonisolated enum WallpaperSource: Codable, Hashable, Sendable {
    case wallpaper(UUID)
    case playlist(UUID)
}

/// The configuration of one physical display, keyed by its stable UUID.
nonisolated struct DisplayConfig: Codable, Hashable, Sendable {
    /// When `false` Wlprz draws nothing and the macOS wallpaper shows through.
    var isEnabled: Bool = true
    /// Used in per-display mode only; mirror mode uses ``Preferences/mirrorSource``.
    var source: WallpaperSource?
}

/// All user-facing settings.
nonisolated struct Preferences: Codable, Hashable, Sendable {
    enum PerformanceMode: String, Codable, CaseIterable, Sendable {
        case automatic, maximum, efficient

        var label: String { rawValue.capitalized }

        var summary: String {
            switch self {
            case .automatic: "Scenes at 30 fps, 60 fps while you click. Best balance."
            case .maximum: "Scenes at the display's full refresh rate."
            case .efficient: "Scenes at 30 fps and half resolution. Videos are unaffected."
            }
        }
    }

    enum DesktopPlayback: String, Codable, CaseIterable, Sendable {
        /// Play whenever any part of the wallpaper is visible.
        case always
        /// Pause while windows cover more than half of the display.
        case whenExposed

        var label: String {
            switch self {
            case .always: "Always"
            case .whenExposed: "When exposed"
            }
        }
    }

    enum DesktopMotion: String, Codable, CaseIterable, Sendable {
        /// Videos and scenes play.
        case animated
        /// Everything holds its current frame: a static wallpaper at zero cost.
        case still

        var label: String { rawValue.capitalized }
    }

    // General
    var syncSystemWallpaper = true

    // Playback
    var performance: PerformanceMode = .automatic
    var pauseOnBattery = false
    var pauseInLowPowerMode = false
    var desktopPlayback: DesktopPlayback = .always
    var desktopMotion: DesktopMotion = .animated
    var isMuted = true
    var volume: Double = 0.5
    var allowsHDR = true

    // Displays
    var mirrorsDisplays = true
    var mirrorSource: WallpaperSource? = .wallpaper(BuiltInScenes.wallpaper(for: .aurora).id)
    var displays: [String: DisplayConfig] = [:]

    func config(forDisplay uuid: String) -> DisplayConfig {
        displays[uuid] ?? DisplayConfig()
    }

    /// The source a display should show, honouring mirror mode and the enabled flag.
    func source(forDisplay uuid: String) -> WallpaperSource? {
        let config = config(forDisplay: uuid)
        guard config.isEnabled else { return nil }
        return mirrorsDisplays ? mirrorSource : (config.source ?? mirrorSource)
    }

    // Decoding is tolerant so that adding a setting never wipes a user's existing ones.
    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        syncSystemWallpaper = try c.decodeIfPresent(Bool.self, forKey: .syncSystemWallpaper) ?? d.syncSystemWallpaper
        performance = try c.decodeIfPresent(PerformanceMode.self, forKey: .performance) ?? d.performance
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? d.pauseOnBattery
        pauseInLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .pauseInLowPowerMode) ?? d.pauseInLowPowerMode
        desktopPlayback = try c.decodeIfPresent(DesktopPlayback.self, forKey: .desktopPlayback) ?? d.desktopPlayback
        desktopMotion = try c.decodeIfPresent(DesktopMotion.self, forKey: .desktopMotion) ?? d.desktopMotion
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? d.isMuted
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
        allowsHDR = try c.decodeIfPresent(Bool.self, forKey: .allowsHDR) ?? d.allowsHDR
        mirrorsDisplays = try c.decodeIfPresent(Bool.self, forKey: .mirrorsDisplays) ?? d.mirrorsDisplays
        mirrorSource = try c.decodeIfPresent(WallpaperSource.self, forKey: .mirrorSource) ?? d.mirrorSource
        displays = try c.decodeIfPresent([String: DisplayConfig].self, forKey: .displays) ?? d.displays
    }
}
