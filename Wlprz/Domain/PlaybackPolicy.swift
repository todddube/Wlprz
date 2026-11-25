//
//  PlaybackPolicy.swift
//  Wlprz · Wlprz
//
//  Decides whether each wallpaper may play, and how fast, from power, memory and visibility.
//

import Foundation

/// The machine conditions the policy reacts to. Sampled by the engine, judged here.
nonisolated struct SystemConditions: Hashable, Sendable {
    enum Thermal: Int, Comparable, Sendable {
        case nominal, fair, serious, critical
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    enum MemoryPressure: Int, Comparable, Sendable {
        case normal, warning, critical
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    var userPaused = false
    var displaysAsleep = false
    var sessionLocked = false
    var onBattery = false
    var lowPowerMode = false
    var thermal: Thermal = .nominal
    var memory: MemoryPressure = .normal
    var mouseDown = false
}

/// Why a wallpaper is not playing. Shown to the user, so every case has a label.
nonisolated enum PauseReason: Hashable, Sendable {
    case user, motionOff, asleep, locked, battery, lowPower, thermal, memory, fullScreen, covered

    var label: String {
        switch self {
        case .user: "Paused"
        case .motionOff: "Still (motion off)"
        case .asleep: "Display asleep"
        case .locked: "Screen locked"
        case .battery: "Paused on battery"
        case .lowPower: "Paused in Low Power Mode"
        case .thermal: "Paused to cool down"
        case .memory: "Paused to free memory"
        case .fullScreen: "Hidden by a full-screen app"
        case .covered: "Hidden by windows"
        }
    }
}

/// The verdict for one wallpaper session.
nonisolated enum PlaybackDecision: Hashable, Sendable {
    /// Play, rendering scenes at no more than `maxFPS` and at `resolutionScale` of native size.
    case play(maxFPS: Int, resolutionScale: Double)
    case pause(PauseReason)

    var isPlaying: Bool {
        if case .play = self { return true }
        return false
    }
}

/// The playback rules from SPEC §2.6, as a pure function.
nonisolated enum PlaybackPolicy {
    /// Coverage at or above this is treated as a full-screen app.
    static let fullScreenCoverage = 0.98
    /// "When exposed" pauses above this coverage.
    static let exposedThreshold = 0.5
    /// Scenes drop to 30 fps when at least this much of the display is covered.
    static let mostlyCoveredThreshold = 0.9
    static let baseFPS = 30
    static let interactiveFPS = 60

    /// Decides one session's playback.
    ///
    /// - Parameters:
    ///   - isScene: scenes are throttled and paused for heat or memory; videos and images are not.
    ///   - coverages: the window coverage (0…1) of every display showing this session.
    ///     The session plays if *any* of them may play.
    ///   - displayMaxFPS: the highest refresh rate among those displays.
    static func decide(
        isScene: Bool,
        coverages: [Double],
        displayMaxFPS: Int,
        conditions: SystemConditions,
        preferences: Preferences
    ) -> PlaybackDecision {
        if conditions.userPaused { return .pause(.user) }
        if preferences.desktopMotion == .still { return .pause(.motionOff) }
        if conditions.sessionLocked { return .pause(.locked) }
        if conditions.displaysAsleep { return .pause(.asleep) }
        if conditions.onBattery && preferences.pauseOnBattery { return .pause(.battery) }
        if conditions.lowPowerMode && preferences.pauseInLowPowerMode { return .pause(.lowPower) }
        if isScene && conditions.thermal == .critical { return .pause(.thermal) }
        if isScene && conditions.memory == .critical { return .pause(.memory) }

        // Visibility: the least-covered display decides, because one visible display is
        // enough reason to keep a shared session running.
        let coverage = coverages.min() ?? 0
        if coverage >= fullScreenCoverage { return .pause(.fullScreen) }
        if preferences.desktopPlayback == .whenExposed && coverage > exposedThreshold {
            return .pause(.covered)
        }

        let fps = sceneFPS(coverage: coverage, displayMaxFPS: displayMaxFPS,
                           conditions: conditions, mode: preferences.performance)
        let scale = preferences.performance == .efficient ? 0.5 : 1.0
        return .play(maxFPS: fps, resolutionScale: scale)
    }

    private static func sceneFPS(
        coverage: Double, displayMaxFPS: Int,
        conditions: SystemConditions, mode: Preferences.PerformanceMode
    ) -> Int {
        let ceiling = max(baseFPS, displayMaxFPS)
        let mustThrottle = coverage >= mostlyCoveredThreshold
            || conditions.thermal >= .serious
            || conditions.memory >= .warning
            || conditions.lowPowerMode
        if mustThrottle { return baseFPS }

        switch mode {
        case .efficient:
            return baseFPS
        case .maximum:
            return ceiling
        case .automatic:
            // A burst of smoothness while the user is interacting, only when it's cheap to.
            let canBurst = conditions.mouseDown && !conditions.onBattery
            return canBurst ? min(interactiveFPS, ceiling) : baseFPS
        }
    }
}
