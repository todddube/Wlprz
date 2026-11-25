//
//  WallpaperEngine.swift
//  Wlprz · Wlprz
//
//  Resolves what each display shows, runs the playback policy, and drives the windows.
//

import AppKit
import Observation
import os

/// The runtime: one desktop window per enabled display, shared video sessions, playlist
/// rotation and the power/visibility policy loop.
@Observable
final class WallpaperEngine {
    /// Connected displays, in `NSScreen.screens` order (the first has the menu bar).
    private(set) var displays: [DisplayInfo] = []
    /// The wallpaper each display is showing, by display id.
    private(set) var nowPlaying: [String: UUID] = [:]
    /// The policy verdict per wallpaper session.
    private(set) var decisions: [UUID: PlaybackDecision] = [:]
    private(set) var conditions = SystemConditions()
    private(set) var coverage: [String: Double] = [:]

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private var controllers: [String: DesktopWindowController] = [:]
    @ObservationIgnored private var videoSessions: [UUID: VideoSession] = [:]
    /// When each video session became hidden for a reason that allows unloading it.
    @ObservationIgnored private var hiddenSince: [UUID: Date] = [:]
    /// The in-flight desktop-picture sync per display; a newer wallpaper cancels the older one.
    @ObservationIgnored private var syncTasks: [String: Task<Void, Never>] = [:]
    /// Playlist position per rotation context ("mirror" or a display id).
    @ObservationIgnored private var cursors: [String: Cursor] = [:]
    @ObservationIgnored private var memorySource: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var mouseMonitors: [Any] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.todddube.Wlprz", category: "Engine")

    /// How long a hidden video keeps its decoder before being unloaded.
    static let unloadDelay: TimeInterval = 30
    static let tickInterval: Duration = .seconds(2)
    private static let mirrorContext = "mirror"

    /// Where a rotation context is in a playlist.
    private struct Cursor {
        var playlist: UUID
        var wallpaper: UUID
        var changed: Date
        /// Scheduled playlists only: a manual "Next" holds until the next slot starts.
        var until: Date?
    }

    init(store: LibraryStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() {
        observeSystem()
        refreshConditions()
        reconcile()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval) // cancellation ends the loop below
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        memorySource?.cancel()
        memorySource = nil
        controllers.values.forEach { $0.close() }
        controllers.removeAll()
        videoSessions.values.forEach { $0.pause() }
        videoSessions.removeAll()
    }

    // MARK: - Commands (menu bar, library, intents)

    var isUserPaused: Bool { conditions.userPaused }

    func setUserPaused(_ paused: Bool) {
        conditions.userPaused = paused
        applyPolicy()
    }

    /// Shows a wallpaper on one display, or on all displays when `displayID` is `nil`.
    func show(_ source: WallpaperSource, onDisplay displayID: String? = nil) {
        var prefs = store.preferences
        if let displayID {
            if prefs.mirrorsDisplays {
                // Leaving mirror mode: keep the other displays on what they were showing,
                // including their position in a shared playlist.
                let mirrorCursor = cursors.removeValue(forKey: Self.mirrorContext)
                for display in displays where display.id != displayID {
                    prefs.displays[display.id, default: DisplayConfig()].source = prefs.mirrorSource
                    cursors[display.id] = mirrorCursor
                }
                prefs.mirrorsDisplays = false
            }
            prefs.displays[displayID, default: DisplayConfig()].source = source
            prefs.displays[displayID]?.isEnabled = true
            cursors[displayID] = nil
        } else {
            prefs.mirrorSource = source
            for key in prefs.displays.keys { prefs.displays[key]?.source = source }
            cursors.removeAll()
        }
        store.preferences = prefs
        reconcile()
    }

    /// Advances the playlist, or steps through the library when a single wallpaper is set.
    func next(onDisplay displayID: String? = nil) {
        var prefs = store.preferences
        // In mirror mode every display shares one source (and one context), so advance it once,
        // without depending on any particular display being enabled.
        let targets = prefs.mirrorsDisplays
            ? [Self.mirrorContext]
            : displayID.map { [$0] } ?? displays.map(\.id)
        for id in targets {
            let source = prefs.mirrorsDisplays ? prefs.mirrorSource : prefs.source(forDisplay: id)
            switch source {
            case .playlist(let playlistID)?:
                advance(context: prefs.mirrorsDisplays ? Self.mirrorContext : id, playlistID: playlistID, force: true)
            case .wallpaper(let current)?:
                let all = store.wallpapers
                guard !all.isEmpty else { continue }
                let index = all.firstIndex { $0.id == current } ?? -1
                let nextSource = WallpaperSource.wallpaper(all[(index + 1) % all.count].id)
                if prefs.mirrorsDisplays {
                    prefs.mirrorSource = nextSource
                } else {
                    prefs.displays[id, default: DisplayConfig()].source = nextSource
                }
            case nil:
                continue
            }
        }
        store.preferences = prefs
        reconcile()
    }

    /// Stops drawing on a display so the macOS wallpaper shows.
    func setDisplay(_ displayID: String, enabled: Bool) {
        var prefs = store.preferences
        prefs.displays[displayID, default: DisplayConfig()].isEnabled = enabled
        store.preferences = prefs
        reconcile()
    }

    /// Call after preferences or the library change.
    func preferencesDidChange() {
        reconcile()
    }

    func pauseReason(forDisplay displayID: String) -> PauseReason? {
        guard let id = nowPlaying[displayID], case .pause(let reason)? = decisions[id] else { return nil }
        return reason
    }

    // MARK: - Reconcile

    /// Makes windows and sessions match preferences and the connected displays.
    func reconcile() {
        displays = DisplayInfo.current
        let prefs = store.preferences
        let library = Dictionary(store.wallpapers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var resolved: [String: UUID] = [:]

        for display in displays {
            guard let source = prefs.source(forDisplay: display.id),
                  let id = resolve(source, context: context(for: display.id, prefs: prefs), library: library)
            else { continue }
            resolved[display.id] = id
        }

        // Windows.
        for (id, controller) in controllers where resolved[id] == nil || !displays.contains(where: { $0.id == id }) {
            controller.close()
            controllers[id] = nil
        }
        for display in displays {
            guard let wallpaperID = resolved[display.id], let wallpaper = library[wallpaperID],
                  let content = content(for: wallpaper)
            else { continue }
            let controller = controllers[display.id] ?? DesktopWindowController(display: display)
            controllers[display.id] = controller
            controller.updateFrame(display.frame)
            let changed = controller.wallpaperID != wallpaperID
            controller.show(content, wallpaperID: wallpaperID)
            controller.setAllowsHDR(prefs.allowsHDR)
            if changed && prefs.syncSystemWallpaper {
                syncTasks[display.id]?.cancel()
                let store = store
                syncTasks[display.id] = Task { [weak self] in
                    await SystemWallpaperSync.apply(wallpaper, on: display, store: store) {
                        self?.nowPlaying[display.id] == wallpaper.id
                    }
                }
            }
        }

        // Video sessions no display uses any more.
        let used = Set(resolved.values)
        for id in videoSessions.keys where !used.contains(id) {
            videoSessions[id]?.pause()
            videoSessions[id] = nil
            hiddenSince[id] = nil
        }

        nowPlaying = resolved
        applyPolicy()
    }

    private func content(for wallpaper: Wallpaper) -> DesktopContent? {
        switch wallpaper.kind {
        case .scene(let scene):
            return .scene(scene)
        case .image:
            return store.mediaURL(for: wallpaper).map(DesktopContent.image)
        case .video:
            guard let url = store.mediaURL(for: wallpaper) else { return nil }
            let session = videoSessions[wallpaper.id] ?? VideoSession(wallpaperID: wallpaper.id, url: url)
            videoSessions[wallpaper.id] = session
            return .video(.init(session: session))
        }
    }

    private func context(for displayID: String, prefs: Preferences) -> String {
        prefs.mirrorsDisplays ? Self.mirrorContext : displayID
    }

    private func resolve(_ source: WallpaperSource, context: String, library: [UUID: Wallpaper]) -> UUID? {
        switch source {
        case .wallpaper(let id):
            return library[id] == nil ? nil : id
        case .playlist(let playlistID):
            guard let playlist = store.playlist(id: playlistID) else { return nil }
            let available = Set(library.keys)
            if playlist.usesSchedule {
                return scheduledWallpaper(playlist, context: context, available: available)
            }
            if let cursor = cursors[context], cursor.playlist == playlistID,
               playlist.wallpaperIDs.contains(cursor.wallpaper), available.contains(cursor.wallpaper) {
                return cursor.wallpaper
            }
            guard let first = PlaylistRotation.next(in: playlist, after: nil, available: available) else { return nil }
            cursors[context] = Cursor(playlist: playlistID, wallpaper: first, changed: .now)
            return first
        }
    }

    /// The schedule's wallpaper, unless a manual "Next" overrides it until the next slot.
    private func scheduledWallpaper(_ playlist: Playlist, context: String, available: Set<UUID>) -> UUID? {
        if let cursor = cursors[context], cursor.playlist == playlist.id,
           let until = cursor.until, until > .now, available.contains(cursor.wallpaper) {
            return cursor.wallpaper
        }
        return PlaylistRotation.scheduled(in: playlist, at: .now, available: available)
    }

    private func advance(context: String, playlistID: UUID, force: Bool) {
        guard let playlist = store.playlist(id: playlistID) else { return }
        if playlist.usesSchedule {
            // Timed changes come from the schedule itself; only a manual "Next" overrides it.
            guard force, let until = PlaylistRotation.nextSlotStart(in: playlist, after: .now) else { return }
            let available = store.availableIDs
            let current = scheduledWallpaper(playlist, context: context, available: available)
            var unscheduled = playlist
            unscheduled.schedule = []
            guard let next = PlaylistRotation.next(in: unscheduled, after: current, available: available) else { return }
            cursors[context] = Cursor(playlist: playlistID, wallpaper: next, changed: .now, until: until)
            return
        }
        let current = cursors[context]?.playlist == playlistID ? cursors[context]?.wallpaper : nil
        if !force, let changed = cursors[context]?.changed,
           playlist.intervalMinutes <= 0 || Date.now.timeIntervalSince(changed) < Double(playlist.intervalMinutes) * 60 {
            return
        }
        guard let next = PlaylistRotation.next(in: playlist, after: current, available: store.availableIDs) else { return }
        cursors[context] = Cursor(playlist: playlistID, wallpaper: next, changed: .now)
    }

    // MARK: - Policy

    private func tick() {
        refreshConditions()
        rotatePlaylists()
        applyPolicy()
    }

    private func rotatePlaylists() {
        let prefs = store.preferences
        var changed = false
        var seen = Set<String>()
        for display in displays {
            guard case .playlist(let playlistID)? = prefs.source(forDisplay: display.id) else { continue }
            let context = context(for: display.id, prefs: prefs)
            guard seen.insert(context).inserted, let playlist = store.playlist(id: playlistID) else { continue }
            if playlist.usesSchedule {
                let due = scheduledWallpaper(playlist, context: context, available: store.availableIDs)
                changed = changed || due != nowPlaying[display.id]
            } else {
                let before = cursors[context]?.wallpaper
                advance(context: context, playlistID: playlistID, force: false)
                changed = changed || before != cursors[context]?.wallpaper
            }
        }
        if changed { reconcile() }
    }

    private func refreshConditions() {
        conditions.onBattery = PowerState.isOnBattery
        conditions.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        conditions.thermal = PowerState.thermal
        coverage = CoverageSampler.sample(displays: displays, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// Runs the policy for every session and pushes the result to players and scene views.
    private func applyPolicy() {
        let prefs = store.preferences
        let library = Dictionary(store.wallpapers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byWallpaper: [UUID: [DisplayInfo]] = [:]
        for display in displays {
            if let id = nowPlaying[display.id] { byWallpaper[id, default: []].append(display) }
        }

        var newDecisions: [UUID: PlaybackDecision] = [:]
        for (id, shownOn) in byWallpaper {
            let decision = PlaybackPolicy.decide(
                isScene: library[id]?.isScene ?? false,
                coverages: shownOn.map { coverage[$0.id] ?? 0 },
                displayMaxFPS: shownOn.map(\.maxFPS).max() ?? 60,
                conditions: conditions,
                preferences: prefs
            )
            newDecisions[id] = decision
            apply(decision, to: id, on: shownOn, prefs: prefs)
        }
        if newDecisions != decisions { decisions = newDecisions }
    }

    private func apply(_ decision: PlaybackDecision, to id: UUID, on shownOn: [DisplayInfo], prefs: Preferences) {
        for display in shownOn {
            guard let state = controllers[display.id]?.sceneState else { continue }
            switch decision {
            case .play(let fps, let scale):
                state.isPaused = false
                if state.maxFPS != fps { state.maxFPS = fps }
                if state.resolutionScale != scale { state.resolutionScale = scale }
            case .pause:
                state.isPaused = true
            }
        }

        guard let session = videoSessions[id] else { return }
        // Only the session on the main display makes sound, so mirroring doesn't echo.
        let audible = shownOn.contains { $0.id == displays.first?.id }
        session.setAudio(muted: prefs.isMuted || !audible, volume: prefs.volume)

        switch decision {
        case .play:
            hiddenSince[id] = nil
            session.play()
        case .pause(let reason):
            session.pause()
            // Free decoder memory only for "nobody can see it" reasons; a user pause should
            // resume instantly, and time spent user-paused must not count towards the delay.
            guard [.fullScreen, .covered, .asleep, .locked].contains(reason) else {
                hiddenSince[id] = nil
                return
            }
            let hidden = hiddenSince[id] ?? .now
            hiddenSince[id] = hidden
            if Date.now.timeIntervalSince(hidden) >= Self.unloadDelay { session.unload() }
        }
    }

    // MARK: - System observation

    private static func memoryPressure(_ event: DispatchSource.MemoryPressureEvent) -> SystemConditions.MemoryPressure {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func on(_ nc: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (WallpaperEngine) -> Void) {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            }
            observers.append((nc, token))
        }

        on(center, NSApplication.didChangeScreenParametersNotification) { $0.reconcile() }
        on(center, .NSProcessInfoPowerStateDidChange) { $0.tick() }
        on(center, ProcessInfo.thermalStateDidChangeNotification) { $0.tick() }
        on(workspace, NSWorkspace.screensDidSleepNotification) { $0.conditions.displaysAsleep = true; $0.applyPolicy() }
        on(workspace, NSWorkspace.screensDidWakeNotification) { $0.conditions.displaysAsleep = false; $0.tick() }
        on(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.tick() }
        on(workspace, NSWorkspace.didActivateApplicationNotification) { $0.tick() }
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.conditions.sessionLocked = true; $0.applyPolicy() }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.conditions.sessionLocked = false; $0.tick() }

        // Memory pressure: throttle scenes on a warning, pause them when critical.
        let memory = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        memory.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.memorySource?.data else { return }
                let level = Self.memoryPressure(event)
                if self.conditions.memory != level {
                    self.conditions.memory = level
                    self.applyPolicy()
                }
            }
        }
        memory.resume()
        memorySource = memory

        // Mouse buttons drive the Automatic mode's 60 fps burst. Global mouse monitors need
        // no Accessibility permission (only key events do).
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let down = event.type == .leftMouseDown
                if self.conditions.mouseDown != down {
                    self.conditions.mouseDown = down
                    self.applyPolicy()
                }
            }
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) { mouseMonitors.append(local) }
    }
}
