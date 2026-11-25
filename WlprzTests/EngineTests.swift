//
//  EngineTests.swift
//  WlprzTests · Wlprz
//
//  Tests for WallpaperEngine: display assignment, mirror transitions, "Next", playlist
//  cursors, scheduled overrides, shared sessions and hidden-video unloading.
//

import CoreGraphics
import Foundation
import Testing

@testable import Wlprz

/// A settable clock for the engine.
@MainActor
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now += seconds }
}

/// An engine over a throwaway library, with two fake displays placed far off screen so the
/// desktop windows it creates are never visible.
@MainActor
private struct Harness {
    let store: LibraryStore
    let engine: WallpaperEngine
    let clock: TestClock
    let left = DisplayInfo(id: "LEFT", name: "Left", frame: CGRect(x: -40_000, y: -40_000, width: 1600, height: 1000))
    let right = DisplayInfo(id: "RIGHT", name: "Right", frame: CGRect(x: -38_000, y: -40_000, width: 1600, height: 1000))
    /// Coverage per display id, read on every tick.
    let coverage: CoverageBox

    final class CoverageBox { var values: [String: Double] = [:] }

    init(start: Date = Self.date(hour: 9)) {
        let root = FileManager.default.temporaryDirectory.appending(path: "WlprzEngineTests-\(UUID().uuidString)")
        store = LibraryStore(folders: LibraryFolders(root: root))
        var prefs = store.preferences
        prefs.syncSystemWallpaper = false // never touch the real desktop picture
        store.preferences = prefs
        clock = TestClock(start)
        let coverage = CoverageBox()
        self.coverage = coverage
        let displays = [left, right]
        let clock = clock
        engine = WallpaperEngine(store: store, dependencies: EngineDependencies(
            displays: { displays },
            coverage: { _ in coverage.values },
            power: { (false, false, .nominal) },
            now: { clock.now }
        ))
    }

    /// 2026-01-10 at `hour`:`minute`, in the calendar the engine uses.
    static func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: hour, minute: minute))!
    }

    func addVideo(_ title: String) -> UUID {
        let wallpaper = Wallpaper(title: title, kind: .video(fileName: "\(title).mov"))
        store.add(wallpaper)
        return wallpaper.id
    }

    func addImage(_ title: String) -> UUID {
        let wallpaper = Wallpaper(title: title, kind: .image(fileName: "\(title).png"))
        store.add(wallpaper)
        return wallpaper.id
    }

    func showing(_ display: DisplayInfo) -> UUID? { engine.nowPlaying[display.id] }

    func tearDown() {
        engine.stop()
        try? FileManager.default.removeItem(at: store.folders.root) // temp folder
    }
}

@MainActor
@Suite struct EngineTests {
    @Test func mirrorShowsOneWallpaperOnEveryDisplay() {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addImage("a")
        h.engine.show(.wallpaper(a))
        #expect(h.showing(h.left) == a)
        #expect(h.showing(h.right) == a)
    }

    @Test func showingOnOneDisplayLeavesMirrorModeAndKeepsTheOthers() {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addImage("a"), b = h.addImage("b")
        h.engine.show(.wallpaper(a))
        h.engine.show(.wallpaper(b), onDisplay: h.right.id)
        #expect(!h.store.preferences.mirrorsDisplays)
        #expect(h.showing(h.left) == a)
        #expect(h.showing(h.right) == b)
    }

    @Test func disablingADisplayStopsDrawingOnlyThere() {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addImage("a")
        h.engine.show(.wallpaper(a))
        h.engine.setDisplay(h.left.id, enabled: false)
        #expect(h.showing(h.left) == nil)
        #expect(h.showing(h.right) == a)
    }

    @Test func nextStepsThroughTheLibraryForASingleWallpaper() {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addImage("a")
        let b = h.addImage("b") // added last, so first in library order
        h.engine.show(.wallpaper(b))
        h.engine.next()
        // Library order is newest first: b, a, then the built-in scenes.
        #expect(h.showing(h.left) == a)
        #expect(h.showing(h.right) == a) // mirror mode advances once, for everyone
    }

    @Test func playlistRotatesOnlyAfterItsInterval() {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addImage("a"), b = h.addImage("b")
        var playlist = h.store.createPlaylist(named: "P", with: [a, b])
        playlist.intervalMinutes = 5
        h.store.update(playlist)
        h.engine.show(.playlist(playlist.id))
        #expect(h.showing(h.left) == a)

        h.clock.advance(4 * 60)
        h.engine.tick()
        #expect(h.showing(h.left) == a)

        h.clock.advance(61)
        h.engine.tick()
        #expect(h.showing(h.left) == b)
        #expect(h.showing(h.right) == b)
    }

    @Test func leavingMirrorModeKeepsThePlaylistPosition() {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addImage("a"), b = h.addImage("b"), other = h.addImage("other")
        let playlist = h.store.createPlaylist(named: "P", with: [a, b])
        h.engine.show(.playlist(playlist.id))
        h.engine.next() // mirror cursor → b
        #expect(h.showing(h.left) == b)

        h.engine.show(.wallpaper(other), onDisplay: h.right.id)
        #expect(h.showing(h.left) == b) // not restarted at a
        #expect(h.showing(h.right) == other)
    }

    @Test func nextOnAScheduleHoldsUntilTheNextSlot() {
        let h = Harness(start: Harness.date(hour: 9)); defer { h.tearDown() }
        let a = h.addImage("a"), b = h.addImage("b"), c = h.addImage("c")
        var playlist = h.store.createPlaylist(named: "Day", with: [a, c, b])
        playlist.schedule = [.init(startMinute: 8 * 60, wallpaperID: a), .init(startMinute: 20 * 60, wallpaperID: b)]
        h.store.update(playlist)
        h.engine.show(.playlist(playlist.id))
        #expect(h.showing(h.left) == a)

        h.engine.next()
        #expect(h.showing(h.left) == c)

        h.clock.now = Harness.date(hour: 19, minute: 59)
        h.engine.tick()
        #expect(h.showing(h.left) == c) // override still holds

        h.clock.now = Harness.date(hour: 20, minute: 1)
        h.engine.tick()
        #expect(h.showing(h.left) == b) // the schedule takes back over
    }

    @Test func mirroredVideoIsOneSessionThatPausesOnlyWhenEveryDisplayIsHidden() {
        let h = Harness(); defer { h.tearDown() }
        let v = h.addVideo("v")
        h.engine.show(.wallpaper(v))
        #expect(h.engine.videoSessions.count == 1)

        // Either display being visible keeps the shared session playing.
        h.coverage.values = [h.left.id: 1, h.right.id: 0]
        h.engine.tick()
        #expect(h.engine.decisions[v]?.isPlaying == true)
        h.coverage.values = [h.left.id: 0, h.right.id: 1]
        h.engine.tick()
        #expect(h.engine.decisions[v]?.isPlaying == true)

        h.coverage.values = [h.left.id: 1, h.right.id: 1]
        h.engine.tick()
        #expect(h.engine.decisions[v] == .pause(.fullScreen))
    }

    @Test func hiddenVideoUnloadsAfter30SecondsAndReloadsWhenSeen() throws {
        let h = Harness(); defer { h.tearDown() }
        let v = h.addVideo("v")
        h.engine.show(.wallpaper(v))
        let session = try #require(h.engine.videoSessions[v])

        h.coverage.values = [h.left.id: 1, h.right.id: 1]
        h.engine.tick()
        h.clock.advance(29)
        h.engine.tick()
        #expect(!session.isUnloaded)

        h.clock.advance(2)
        h.engine.tick()
        #expect(session.isUnloaded)

        h.coverage.values = [:]
        h.engine.tick()
        #expect(!session.isUnloaded)
    }

    @Test func userPauseNeverUnloadsAndStillReloadsAnUnloadedVideo() throws {
        let h = Harness(); defer { h.tearDown() }
        let v = h.addVideo("v")
        h.engine.show(.wallpaper(v))
        let session = try #require(h.engine.videoSessions[v])

        h.engine.setUserPaused(true)
        h.clock.advance(120)
        h.engine.tick()
        #expect(!session.isUnloaded)
        h.engine.setUserPaused(false)

        // Unload behind a full-screen app, then switch to Still and reveal the desktop.
        h.coverage.values = [h.left.id: 1, h.right.id: 1]
        h.engine.tick()
        h.clock.advance(31)
        h.engine.tick()
        #expect(session.isUnloaded)
        var prefs = h.store.preferences
        prefs.desktopMotion = .still
        h.store.preferences = prefs
        h.coverage.values = [:]
        h.engine.tick()
        #expect(h.engine.decisions[v] == .pause(.motionOff))
        #expect(!session.isUnloaded) // a frame to show, not black
    }

    @Test func deletingTheShownWallpaperClearsTheDisplaysAndItsSession() throws {
        let h = Harness(); defer { h.tearDown() }
        let a = h.addVideo("a")
        h.engine.show(.wallpaper(a))
        _ = try #require(h.engine.videoSessions[a])
        h.store.delete(a)
        h.engine.preferencesDidChange()
        #expect(h.showing(h.left) == nil)
        #expect(h.engine.videoSessions.isEmpty)
    }
}
