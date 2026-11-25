//
//  DomainTests.swift
//  WlprzTests · Wlprz
//
//  Tests for the pure domain rules: playback policy, playlist rotation, persistence.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Wlprz

// MARK: - Playback policy

@Suite struct PlaybackPolicyTests {
    private func decide(
        scene: Bool = true, coverage: [Double] = [0], maxFPS: Int = 120,
        _ conditions: SystemConditions = .init(), _ prefs: Preferences = .init()
    ) -> PlaybackDecision {
        PlaybackPolicy.decide(isScene: scene, coverages: coverage, displayMaxFPS: maxFPS,
                              conditions: conditions, preferences: prefs)
    }

    private func decide(scene: Bool = true, p: Preferences) -> PlaybackDecision {
        decide(scene: scene, .init(), p)
    }

    @Test func automaticPlaysScenesAt30() {
        #expect(decide() == .play(maxFPS: 30, resolutionScale: 1))
    }

    @Test func automaticBurstsTo60WhileClickingOnAC() {
        var c = SystemConditions(); c.mouseDown = true
        #expect(decide(c) == .play(maxFPS: 60, resolutionScale: 1))
        c.onBattery = true
        #expect(decide(c) == .play(maxFPS: 30, resolutionScale: 1))
    }

    @Test func maximumUsesDisplayRefreshButNotInLowPower() {
        var p = Preferences(); p.performance = .maximum
        #expect(decide(maxFPS: 120, .init(), p) == .play(maxFPS: 120, resolutionScale: 1))
        var c = SystemConditions(); c.lowPowerMode = true
        #expect(decide(maxFPS: 120, c, p) == .play(maxFPS: 30, resolutionScale: 1))
    }

    @Test func efficientHalvesResolution() {
        var p = Preferences(); p.performance = .efficient
        #expect(decide(.init(), p) == .play(maxFPS: 30, resolutionScale: 0.5))
    }

    @Test func batteryAndLowPowerPauseOnlyWhenOptedIn() {
        var c = SystemConditions(); c.onBattery = true; c.lowPowerMode = true
        #expect(decide(c).isPlaying)
        var p = Preferences(); p.pauseOnBattery = true
        #expect(decide(c, p) == .pause(.battery))
        p = Preferences(); p.pauseInLowPowerMode = true
        #expect(decide(c, p) == .pause(.lowPower))
    }

    @Test func fullScreenAppPauses() {
        #expect(decide(coverage: [1.0]) == .pause(.fullScreen))
    }

    @Test func sharedSessionPlaysWhileAnyDisplayIsVisible() {
        #expect(decide(coverage: [1.0, 0.2]).isPlaying)
        #expect(decide(coverage: [1.0, 1.0]) == .pause(.fullScreen))
    }

    @Test func whenExposedPausesAboveHalfCoverage() {
        var p = Preferences(); p.desktopPlayback = .whenExposed
        #expect(decide(coverage: [0.4], .init(), p).isPlaying)
        #expect(decide(coverage: [0.6], .init(), p) == .pause(.covered))
        #expect(decide(coverage: [0.6]).isPlaying, "Always mode ignores partial coverage")
    }

    @Test func mostlyCoveredCapsMaximumTo30() {
        var p = Preferences(); p.performance = .maximum
        #expect(decide(coverage: [0.92], maxFPS: 120, .init(), p) == .play(maxFPS: 30, resolutionScale: 1))
    }

    @Test func criticalThermalPausesScenesNotVideos() {
        var c = SystemConditions(); c.thermal = .critical
        #expect(decide(scene: true, c) == .pause(.thermal))
        #expect(decide(scene: false, c).isPlaying)
    }

    @Test func memoryWarningCapsScenesAndCriticalPausesThem() {
        var c = SystemConditions(); c.memory = .warning
        var p = Preferences(); p.performance = .maximum
        #expect(decide(c, p) == .play(maxFPS: 30, resolutionScale: 1))
        c.memory = .critical
        #expect(decide(c, p) == .pause(.memory))
        #expect(decide(scene: false, c, p).isPlaying)
    }

    @Test func stillMotionHoldsEveryKindButUserPauseWins() {
        var p = Preferences(); p.desktopMotion = .still
        #expect(decide(p: p) == .pause(.motionOff))
        #expect(decide(scene: false, p: p) == .pause(.motionOff))
        var c = SystemConditions(); c.userPaused = true
        #expect(decide(c, p) == .pause(.user))
    }

    @Test func userPauseAndLockWinOverEverything() {
        var c = SystemConditions(); c.userPaused = true; c.sessionLocked = true
        #expect(decide(c) == .pause(.user))
        c.userPaused = false
        #expect(decide(c) == .pause(.locked))
    }
}

// MARK: - Playlist rotation

/// Deterministic generator so shuffle tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct PlaylistRotationTests {
    let a = UUID(), b = UUID(), c = UUID()
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: hour, minute: minute))!
    }

    @Test func sequentialWrapsAround() {
        let list = Playlist(name: "x", wallpaperIDs: [a, b, c])
        let all: Set = [a, b, c]
        #expect(PlaylistRotation.next(in: list, after: nil, available: all) == a)
        #expect(PlaylistRotation.next(in: list, after: a, available: all) == b)
        #expect(PlaylistRotation.next(in: list, after: c, available: all) == a)
    }

    @Test func skipsDeletedWallpapers() {
        let list = Playlist(name: "x", wallpaperIDs: [a, b, c])
        #expect(PlaylistRotation.next(in: list, after: a, available: [a, c]) == c)
        #expect(PlaylistRotation.next(in: list, after: a, available: []) == nil)
    }

    @Test func shuffleNeverRepeatsCurrent() {
        let list = Playlist(name: "x", wallpaperIDs: [a, b, c], shuffle: true)
        var rng = SeededGenerator(state: 42)
        for _ in 0..<200 {
            let next = PlaylistRotation.next(in: list, after: b, available: [a, b, c], at: .now, using: &rng)
            #expect(next != b)
            #expect(next != nil)
        }
    }

    @Test func singleItemAlwaysReturnsIt() {
        let list = Playlist(name: "x", wallpaperIDs: [a], shuffle: true)
        #expect(PlaylistRotation.next(in: list, after: a, available: [a]) == a)
    }

    @Test func nextSlotStartIsLaterTodayOrFirstSlotTomorrow() {
        let plain = Playlist(name: "x", wallpaperIDs: [a, b])
        var p = plain
        p.schedule = [.init(startMinute: 8 * 60, wallpaperID: a), .init(startMinute: 20 * 60, wallpaperID: b)]
        let all: Set = [a, b, c]
        #expect(PlaylistRotation.nextSlotStart(in: p, after: at(9), calendar: calendar, available: all) == at(20))
        let tomorrow8 = calendar.date(byAdding: .day, value: 1, to: at(8))
        #expect(PlaylistRotation.nextSlotStart(in: p, after: at(21), calendar: calendar, available: all) == tomorrow8)
        #expect(PlaylistRotation.nextSlotStart(in: plain, after: at(9), calendar: calendar, available: all) == nil)
        // At exactly a slot's start that slot is active, so the boundary is the following one.
        #expect(PlaylistRotation.scheduled(in: p, at: at(20), calendar: calendar, available: all) == b)
        #expect(PlaylistRotation.nextSlotStart(in: p, after: at(20), calendar: calendar, available: all) == tomorrow8)
    }

    @Test func nextSlotStartSkipsDeletedAndRepeatedSlots() {
        var p = Playlist(name: "x", wallpaperIDs: [a, b, c])
        p.schedule = [.init(startMinute: 8 * 60, wallpaperID: a), .init(startMinute: 12 * 60, wallpaperID: c),
                      .init(startMinute: 16 * 60, wallpaperID: a), .init(startMinute: 20 * 60, wallpaperID: b)]
        // c deleted: 12:00 is gone and 16:00 repeats a, so from 9:00 the next change is 20:00.
        #expect(PlaylistRotation.nextSlotStart(in: p, after: at(9), calendar: calendar, available: [a, b]) == at(20))
    }

    @Test func scheduleWrapsPastMidnight() {
        var list = Playlist(name: "x", wallpaperIDs: [a, b])
        list.schedule = [.init(startMinute: 7 * 60, wallpaperID: a), .init(startMinute: 19 * 60, wallpaperID: b)]
        #expect(PlaylistRotation.scheduled(in: list, at: at(12), calendar: calendar, available: [a, b]) == a)
        #expect(PlaylistRotation.scheduled(in: list, at: at(20), calendar: calendar, available: [a, b]) == b)
        #expect(PlaylistRotation.scheduled(in: list, at: at(3), calendar: calendar, available: [a, b]) == b,
                "Before the first slot, yesterday's last slot is still active")
        #expect(PlaylistRotation.scheduled(in: list, at: at(7), calendar: calendar, available: [a, b]) == a)
    }
}

// MARK: - Model and persistence

@Suite struct LibraryDocumentTests {
    @Test func builtInScenesHaveStableUniqueIDs() {
        let ids = BuiltInScenes.all.map(\.id)
        #expect(Set(ids).count == SceneID.allCases.count)
        #expect(ids.allSatisfy { $0.uuidString.hasPrefix("00000000-0000-0000-0000-00000000A") })
    }

    @Test func roundTripsThroughJSON() throws {
        var doc = LibraryDocument()
        doc.wallpapers = [Wallpaper(title: "Beach", kind: .video(fileName: "x.mov"), tags: ["sea"])]
        doc.playlists = [Playlist(name: "Mix", wallpaperIDs: [doc.wallpapers[0].id])]
        doc.preferences.performance = .efficient
        doc.preferences.displays["DISPLAY"] = DisplayConfig(isEnabled: false, source: .playlist(doc.playlists[0].id))
        doc.favoriteSceneIDs = [BuiltInScenes.all[0].id]

        let decoded = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(doc))
        #expect(decoded == doc)
        #expect(decoded.allWallpapers.first { $0.id == BuiltInScenes.all[0].id }?.isFavorite == true)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(LibraryDocument.self, from: Data(#"{"preferences":{"pauseOnBattery":true}}"#.utf8))
        #expect(decoded.preferences.pauseOnBattery)
        #expect(decoded.preferences.performance == .automatic)
        #expect(decoded.preferences.desktopMotion == .animated)
        #expect(decoded.allWallpapers.count == SceneID.allCases.count)
    }

    @Test func mirrorModeIgnoresPerDisplaySource() {
        var p = Preferences()
        let mirror = WallpaperSource.wallpaper(UUID())
        let own = WallpaperSource.wallpaper(UUID())
        p.mirrorSource = mirror
        p.displays["D"] = DisplayConfig(isEnabled: true, source: own)
        #expect(p.source(forDisplay: "D") == mirror)
        p.mirrorsDisplays = false
        #expect(p.source(forDisplay: "D") == own)
        p.displays["D"]?.isEnabled = false
        #expect(p.source(forDisplay: "D") == nil)
    }

    @Test func searchMatchesTitleAndTags() {
        let w = Wallpaper(title: "Northern Lights", kind: .scene(.aurora), tags: ["Calm"])
        #expect(w.matches(query: "north"))
        #expect(w.matches(query: "calm"))
        #expect(w.matches(query: "  "))
        #expect(!w.matches(query: "ocean"))
    }
}

// MARK: - Format

@Suite struct FormatTests {
    @Test func ratioDecidesFormatAndScenesFitBoth() {
        let wide = Wallpaper(title: "w", kind: .image(fileName: "w.png"), aspectRatio: 21.0 / 9)
        let normal = Wallpaper(title: "n", kind: .video(fileName: "n.mov"), aspectRatio: 16.0 / 9)
        let scene = Wallpaper(title: "s", kind: .scene(.aurora))
        #expect(wide.format == .ultrawide && wide.fits(.ultrawide) && !wide.fits(.standard))
        #expect(normal.format == .standard && normal.fits(.standard) && !normal.fits(.ultrawide))
        #expect(scene.fits(.standard) && scene.fits(.ultrawide))
    }

    @Test func oldLibrariesWithoutRatiosStillDecode() throws {
        let json = #"{"id":"11111111-0000-0000-0000-000000000001","title":"x","kind":{"image":{"fileName":"x.png"}},"tags":[],"isFavorite":false,"motion":"still","energy":"efficient","dateAdded":0}"#
        let decoded = try JSONDecoder().decode(Wallpaper.self, from: Data(json.utf8))
        #expect(decoded.aspectRatio == nil)
    }

    @Test func measuresImageAspectRatio() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "wlprz-ratio-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) } // temp file
        let context = try #require(CGContext(data: nil, width: 210, height: 90, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let ratio = try #require(await MediaImporter.aspectRatio(of: url, isVideo: false))
        #expect(abs(ratio - 210.0 / 90) < 0.001)
    }
}

// MARK: - Coverage

@Suite struct CoverageTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func noWindowsIsUncovered() {
        #expect(CoverageSampler.coverage(of: screen, by: []) == 0)
    }

    @Test func fullScreenWindowIsFullyCovered() {
        #expect(CoverageSampler.coverage(of: screen, by: [screen]) == 1)
    }

    @Test func overlappingWindowsAreNotDoubleCounted() {
        let left = CGRect(x: 0, y: 0, width: 500, height: 600)
        let coverage = CoverageSampler.coverage(of: screen, by: [left, left, left])
        #expect(abs(coverage - 0.5) < 0.03)
    }

    @Test func appKitFramesFlipIntoCGWindowSpace() {
        // Primary 1000×600 at the origin; a second display stacked above it in AppKit space.
        let above = CGRect(x: 0, y: 600, width: 800, height: 500)
        #expect(CoverageSampler.cgFrame(forAppKit: screen, primaryHeight: 600) == screen)
        #expect(CoverageSampler.cgFrame(forAppKit: above, primaryHeight: 600) == CGRect(x: 0, y: -500, width: 800, height: 500))
    }

    @Test func windowsOnOtherDisplaysAreIgnored() {
        let elsewhere = CGRect(x: 1000, y: 0, width: 1000, height: 600)
        #expect(CoverageSampler.coverage(of: screen, by: [elsewhere]) == 0)
    }
}
