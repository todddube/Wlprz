//
//  LibraryStore.swift
//  Wlprz · Wlprz
//
//  Observable, persisted library: wallpapers, playlists, preferences and their files.
//

import Foundation
import Observation
import os

/// The single source of truth for library state, saved as JSON in Application Support.
///
/// Mutations go through this type so that every change is persisted (debounced) and
/// observed by the engine and the UI alike.
@Observable
final class LibraryStore {
    private(set) var document: LibraryDocument
    /// Bumped when a thumbnail file is (re)written so grid cells reload it.
    private(set) var thumbnailRevision = 0

    @ObservationIgnored let folders: LibraryFolders
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.todddube.Wlprz", category: "Library")

    init(folders: LibraryFolders = .standard) {
        self.folders = folders
        folders.createIfNeeded()
        self.document = Self.load(from: folders.document)
    }

    // MARK: - Reading

    var wallpapers: [Wallpaper] { document.allWallpapers }
    var playlists: [Playlist] { document.playlists }
    var availableIDs: Set<UUID> { Set(wallpapers.map(\.id)) }

    func wallpaper(id: UUID) -> Wallpaper? { wallpapers.first { $0.id == id } }
    func playlist(id: UUID) -> Playlist? { document.playlists.first { $0.id == id } }

    /// The library file behind a video or image wallpaper.
    func mediaURL(for wallpaper: Wallpaper) -> URL? {
        wallpaper.kind.fileName.map { folders.media.appending(path: $0) }
    }

    func thumbnailURL(for id: UUID) -> URL { folders.thumbnails.appending(path: "\(id.uuidString).jpg") }

    func noteThumbnailWritten() { thumbnailRevision += 1 }

    // MARK: - Preferences

    var preferences: Preferences {
        get { document.preferences }
        set {
            guard newValue != document.preferences else { return }
            document.preferences = newValue
            scheduleSave()
        }
    }

    // MARK: - Wallpapers

    /// Adds a newly imported wallpaper at the top of the library.
    func add(_ wallpaper: Wallpaper) {
        document.wallpapers.insert(wallpaper, at: 0)
        scheduleSave()
    }

    /// Replaces the stored copy of a wallpaper; built-in scenes only persist the favourite flag.
    func update(_ wallpaper: Wallpaper) {
        if wallpaper.isScene {
            if wallpaper.isFavorite {
                document.favoriteSceneIDs.insert(wallpaper.id)
            } else {
                document.favoriteSceneIDs.remove(wallpaper.id)
            }
        } else if let index = document.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            document.wallpapers[index] = wallpaper
        }
        scheduleSave()
    }

    func toggleFavorite(_ id: UUID) {
        guard var wallpaper = wallpaper(id: id) else { return }
        wallpaper.isFavorite.toggle()
        update(wallpaper)
    }

    /// Removes a user wallpaper, its files, and every reference to it. Scenes can't be deleted.
    func delete(_ id: UUID) {
        guard let index = document.wallpapers.firstIndex(where: { $0.id == id }) else { return }
        let removed = document.wallpapers.remove(at: index)
        for i in document.playlists.indices {
            document.playlists[i].wallpaperIDs.removeAll { $0 == id }
            document.playlists[i].schedule.removeAll { $0.wallpaperID == id }
        }
        var prefs = document.preferences
        if prefs.mirrorSource == .wallpaper(id) { prefs.mirrorSource = nil }
        for (key, config) in prefs.displays where config.source == .wallpaper(id) {
            prefs.displays[key]?.source = nil
        }
        document.preferences = prefs

        let fm = FileManager.default
        for url in [mediaURL(for: removed), thumbnailURL(for: id), folders.stillURL(for: id)].compactMap(\.self)
        where fm.fileExists(atPath: url.path) {
            do { try fm.removeItem(at: url) } catch {
                log.error("Couldn't delete \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        scheduleSave()
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(named name: String, with ids: [UUID] = []) -> Playlist {
        let playlist = Playlist(name: name, wallpaperIDs: ids)
        document.playlists.append(playlist)
        scheduleSave()
        return playlist
    }

    /// Replaces the stored copy of a playlist; unknown ids are ignored.
    func update(_ playlist: Playlist) {
        guard let index = document.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        document.playlists[index] = playlist
        scheduleSave()
    }

    /// Removes a playlist and clears any display source that pointed at it.
    func deletePlaylist(_ id: UUID) {
        document.playlists.removeAll { $0.id == id }
        var prefs = document.preferences
        if prefs.mirrorSource == .playlist(id) { prefs.mirrorSource = nil }
        for (key, config) in prefs.displays where config.source == .playlist(id) {
            prefs.displays[key]?.source = nil
        }
        document.preferences = prefs
        scheduleSave()
    }

    /// Appends a wallpaper to a playlist unless it is already in it.
    func add(_ wallpaperID: UUID, toPlaylist playlistID: UUID) {
        guard var playlist = playlist(id: playlistID), !playlist.wallpaperIDs.contains(wallpaperID) else { return }
        playlist.wallpaperIDs.append(wallpaperID)
        update(playlist)
    }

    // MARK: - Persistence

    /// Writes immediately, e.g. at quit, instead of waiting for the debounce.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        Self.write(document, to: folders.document, log: log)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400)) // cancellation just means a newer save superseded this one
            guard !Task.isCancelled, let self else { return }
            Self.write(self.document, to: self.folders.document, log: self.log)
        }
    }

    private static func load(from url: URL) -> LibraryDocument {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LibraryDocument.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return LibraryDocument() // first launch: no file yet
        } catch {
            // Unreadable or undecodable. Back it up now, before the first save can
            // overwrite the user's real library with an empty one.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup) // may not exist
            try? FileManager.default.copyItem(at: url, to: backup) // best effort; we still start clean
            Logger(subsystem: "com.todddube.Wlprz", category: "Library")
                .error("Library unreadable, backed up and reset: \(error.localizedDescription, privacy: .public)")
            return LibraryDocument()
        }
    }

    private static func write(_ document: LibraryDocument, to url: URL, log: Logger) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The folder layout inside Application Support.
nonisolated struct LibraryFolders: Sendable {
    let root: URL

    var document: URL { root.appending(path: "library.json") }
    var media: URL { root.appending(path: "Media", directoryHint: .isDirectory) }
    var thumbnails: URL { root.appending(path: "Thumbnails", directoryHint: .isDirectory) }
    var stills: URL { root.appending(path: "Stills", directoryHint: .isDirectory) }

    func stillURL(for id: UUID) -> URL { stills.appending(path: "\(id.uuidString).heic") }

    static var standard: LibraryFolders {
        LibraryFolders(root: URL.applicationSupportDirectory.appending(path: "Wlprz", directoryHint: .isDirectory))
    }

    func createIfNeeded() {
        for folder in [root, media, thumbnails, stills] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) // failure surfaces on first write
        }
    }
}
