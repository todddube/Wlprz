//
//  SystemWallpaperSync.swift
//  Wlprz · Wlprz
//
//  Keeps the macOS desktop picture (and so the Lock Screen) matched to the live wallpaper.
//

import AppKit
import ServiceManagement
import os

/// Sets a still of the current wallpaper as the system desktop picture for a display.
///
/// There's no public API for an animated Lock Screen, so this is how Wlprz makes the
/// Lock Screen, Mission Control and the desktop after quitting match what plays.
enum SystemWallpaperSync {
    private static let log = Logger(subsystem: "com.todddube.Wlprz", category: "SystemWallpaper")
    /// The wallpaper whose still each display's desktop picture currently shows.
    private static var applied: [String: UUID] = [:]
    /// One in-flight still extraction per wallpaper, shared by every display that needs it.
    private static var extractions: [UUID: Task<Void, any Error>] = [:]

    /// Makes a still of `wallpaper` the desktop picture of `display`; scenes are skipped.
    ///
    /// macOS is pointed at a private, uniquely named copy of the still, so deleting the
    /// wallpaper from the library never leaves the desktop or Lock Screen on a missing file,
    /// and the unique name defeats the system's per-URL picture cache.
    ///
    /// - Parameter isCurrent: re-checked after the (slow) still extraction; if the display
    ///   moved on to another wallpaper meanwhile, nothing is applied.
    static func apply(
        _ wallpaper: Wallpaper, on display: DisplayInfo, store: LibraryStore,
        isCurrent: () -> Bool
    ) async {
        guard applied[display.id] != wallpaper.id,
              let media = store.mediaURL(for: wallpaper)
        else { return } // scenes have no still
        let source: URL
        switch wallpaper.kind {
        case .image:
            source = media
        case .video:
            source = store.folders.stillURL(for: wallpaper.id)
            if !FileManager.default.fileExists(atPath: source.path) {
                do {
                    try await extractStill(for: wallpaper.id, media: media, to: source, store: store)
                } catch {
                    log.error("Still extraction failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
        case .scene:
            return
        }
        guard !Task.isCancelled, isCurrent(), let screen = display.screen else { return }

        let folder = store.folders.stills.appending(path: "Desktop", directoryHint: .isDirectory)
        let fm = FileManager.default
        let copy = folder.appending(path: "\(display.id)-\(UUID().uuidString).\(source.pathExtension)")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try await MediaImporter.copyFile(source, to: copy)
            // The copy suspends; a newer wallpaper may have taken over the display meanwhile.
            guard !Task.isCancelled, isCurrent() else {
                try? fm.removeItem(at: copy) // our own unused copy
                return
            }
            try NSWorkspace.shared.setDesktopImageURL(copy, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
            applied[display.id] = wallpaper.id
        } catch {
            log.error("Desktop picture sync failed: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: copy) // may not exist if the copy itself failed
            return
        }
        // Remove this display's previous copies now that macOS points at the new one.
        let previous = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] // empty folder is fine
        for url in previous where url != copy && url.lastPathComponent.hasPrefix(display.id + "-") {
            try? fm.removeItem(at: url) // stale copy; leaving it only costs disk space
        }
    }

    /// Extracts a video's still once, however many displays ask for it at the same time.
    private static func extractStill(for id: UUID, media: URL, to destination: URL, store: LibraryStore) async throws {
        if let running = extractions[id] { return try await running.value }
        let task = Task {
            // Write beside the destination, then move, so a reader never sees a half-written file.
            let temp = destination.deletingLastPathComponent().appending(path: "\(UUID().uuidString).tmp.heic")
            do {
                try await Thumbnailer.writeStill(for: media, isVideo: true, to: temp)
                try FileManager.default.moveItem(at: temp, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: temp) // may not exist
                throw error
            }
        }
        extractions[id] = task
        defer { extractions[id] = nil }
        try await task.value
        // Deleted from the library while extracting: don't leave an orphaned still behind.
        if store.wallpaper(id: id) == nil {
            try? FileManager.default.removeItem(at: destination) // best effort cleanup
        }
    }
}

/// Registers the app as a login item.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// - Throws: the ServiceManagement error so the UI can explain it (e.g. approval needed).
    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
