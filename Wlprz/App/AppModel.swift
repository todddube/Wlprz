//
//  AppModel.swift
//  Wlprz · Wlprz
//
//  Composition root: owns the store and engine and exposes the commands the UI calls.
//

import Foundation
import Observation
import os

/// The app's shared state and command surface.
///
/// A singleton because App Intents are instantiated by the system and need a way back to
/// the running engine; everything else receives it through the SwiftUI environment.
@Observable
final class AppModel {
    static let shared = AppModel()

    let store: LibraryStore
    let engine: WallpaperEngine
    /// The most recent import failure, shown as an alert by the library window.
    var importError: String?
    /// Imports currently running, so the UI can show progress.
    private(set) var importsInFlight = 0

    @ObservationIgnored private var started = false
    @ObservationIgnored private let log = Logger(subsystem: "com.todddube.Wlprz", category: "App")

    /// `true` when launched as the unit-test host. Tests build their own engines; the host
    /// must neither draw on the desktop nor read or write the user's real library.
    static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private init() {
        let folders = Self.isTestHost
            ? LibraryFolders(root: FileManager.default.temporaryDirectory.appending(path: "WlprzTestHost-\(UUID().uuidString)"))
            : .standard
        store = LibraryStore(folders: folders)
        engine = WallpaperEngine(store: store)
    }

    /// Starts the engine once; safe to call from both launch and an intent that launched the app.
    func start() {
        guard !started, !Self.isTestHost else { return }
        started = true
        engine.start()
        Task { await measureUnmeasuredMedia() }
    }

    /// Fills in the aspect ratio of wallpapers imported before it was recorded, so the
    /// Standard / Ultrawide filter can place them.
    private func measureUnmeasuredMedia() async {
        for wallpaper in store.wallpapers where !wallpaper.isScene && wallpaper.aspectRatio == nil {
            guard let url = store.mediaURL(for: wallpaper),
                  let ratio = await MediaImporter.aspectRatio(of: url, isVideo: wallpaper.kind.isAnimated),
                  var current = store.wallpaper(id: wallpaper.id) // may have changed meanwhile
            else { continue }
            current.aspectRatio = ratio
            store.update(current)
        }
    }

    /// Flushes the pending save and takes the desktop windows down before the app exits.
    func shutdown() {
        guard !Self.isTestHost else { return }
        store.saveNow()
        engine.stop()
    }

    // MARK: - Preferences

    /// Applies a preference edit and lets the engine react.
    func updatePreferences(_ edit: (inout Preferences) -> Void) {
        var prefs = store.preferences
        edit(&prefs)
        store.preferences = prefs
        engine.preferencesDidChange()
    }

    // MARK: - Library commands

    /// Shows a wallpaper on one display, or on every display when `displayID` is `nil`.
    func setWallpaper(_ id: UUID, onDisplay displayID: String? = nil) {
        engine.show(.wallpaper(id), onDisplay: displayID)
    }

    /// Starts a playlist on one display, or on every display when `displayID` is `nil`.
    func playPlaylist(_ id: UUID, onDisplay displayID: String? = nil) {
        engine.show(.playlist(id), onDisplay: displayID)
    }

    /// Deletes a user wallpaper and its files, then re-resolves every display.
    func delete(_ id: UUID) {
        store.delete(id)
        engine.preferencesDidChange()
    }

    func deletePlaylist(_ id: UUID) {
        store.deletePlaylist(id)
        engine.preferencesDidChange()
    }

    /// Imports files with default options (drag and drop, quick import).
    func quickImport(_ urls: [URL]) async {
        for url in urls {
            await importMedia(from: url, options: ImportOptions(title: url.deletingPathExtension().lastPathComponent))
        }
    }

    /// Imports one file through the Creator pipeline.
    @discardableResult
    func importMedia(
        from url: URL, options: ImportOptions, progress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async -> Wallpaper? {
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let wallpaper = try await MediaImporter.importMedia(from: url, options: options, folders: store.folders,
                                                                  progress: progress)
            store.add(wallpaper)
            store.noteThumbnailWritten()
            return wallpaper
        } catch where Task.isCancelled {
            return nil // the user cancelled; not an error worth an alert
        } catch {
            log.error("Import failed: \(error.localizedDescription, privacy: .public)")
            importError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Status

    /// One line for the menu bar describing the display's state.
    func status(forDisplay displayID: String) -> String {
        guard let id = engine.nowPlaying[displayID], let wallpaper = store.wallpaper(id: id) else {
            return store.preferences.config(forDisplay: displayID).isEnabled ? "Nothing selected" : "Off — macOS wallpaper"
        }
        if let reason = engine.pauseReason(forDisplay: displayID) {
            return "\(wallpaper.title) · \(reason.label)"
        }
        return wallpaper.title
    }
}
