//
//  LibraryDocument.swift
//  Wlprz · Wlprz
//
//  The on-disk shape of the whole library: user wallpapers, playlists and preferences.
//

import Foundation

/// Everything Wlprz persists, as one versioned JSON document.
///
/// Built-in scenes are not stored; they are merged in at load so that app updates can
/// change them. Only per-user state about them (favourites) is kept.
nonisolated struct LibraryDocument: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version = LibraryDocument.currentVersion
    var wallpapers: [Wallpaper] = []
    var playlists: [Playlist] = []
    var preferences = Preferences()
    var favoriteSceneIDs: Set<UUID> = []

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        wallpapers = try c.decodeIfPresent([Wallpaper].self, forKey: .wallpapers) ?? []
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        favoriteSceneIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .favoriteSceneIDs) ?? []
    }

    /// User wallpapers plus built-in scenes, with scene favourites applied.
    var allWallpapers: [Wallpaper] {
        let scenes = BuiltInScenes.all.map { scene in
            var scene = scene
            scene.isFavorite = favoriteSceneIDs.contains(scene.id)
            return scene
        }
        return wallpapers + scenes
    }
}
