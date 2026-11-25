//
//  WallpaperIntents.swift
//  Wlprz · Wlprz
//
//  Shortcuts and Siri actions: set, skip, pause/resume and play playlists.
//

import AppIntents
import Foundation

// MARK: - Entities

/// A library wallpaper as Shortcuts sees it: just enough to pick one by name.
struct WallpaperEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wallpaper"
    static let defaultQuery = WallpaperQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ wallpaper: Wallpaper) {
        id = wallpaper.id
        title = wallpaper.title
    }
}

/// Resolves wallpaper parameters against the live library, with title/tag search.
struct WallpaperQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [WallpaperEntity] {
        await MainActor.run { identifiers.compactMap { AppModel.shared.store.wallpaper(id: $0) }.map(WallpaperEntity.init) }
    }

    func entities(matching string: String) async throws -> [WallpaperEntity] {
        await MainActor.run { AppModel.shared.store.wallpapers.filter { $0.matches(query: string) }.map(WallpaperEntity.init) }
    }

    func suggestedEntities() async throws -> [WallpaperEntity] {
        await MainActor.run { AppModel.shared.store.wallpapers.map(WallpaperEntity.init) }
    }
}

/// A playlist as Shortcuts sees it.
struct PlaylistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static let defaultQuery = PlaylistQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Resolves playlist parameters against the live library.
struct PlaylistQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlaylistEntity] {
        await MainActor.run {
            identifiers.compactMap { AppModel.shared.store.playlist(id: $0) }.map { PlaylistEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [PlaylistEntity] {
        await MainActor.run { AppModel.shared.store.playlists.map { PlaylistEntity(id: $0.id, name: $0.name) } }
    }
}

// MARK: - Intents

/// Shows one wallpaper on every display.
struct SetWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Wallpaper"
    static let description = IntentDescription("Shows a Wlprz wallpaper on every display.")

    @Parameter(title: "Wallpaper") var wallpaper: WallpaperEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.setWallpaper(wallpaper.id)
        return .result()
    }
}

/// Advances the playlist, or steps through the library, like the menu bar's Next button.
struct NextWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Wallpaper"
    static let description = IntentDescription("Skips to the next wallpaper in the playlist or library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.engine.next()
        return .result()
    }
}

/// Sets the user pause, the same switch as the menu bar's Pause button.
struct SetPlaybackPausedIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Wallpaper"
    static let description = IntentDescription("Pauses, resumes or toggles live wallpaper playback.")

    enum Action: String, AppEnum {
        case toggle, pause, resume
        static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
        static let caseDisplayRepresentations: [Action: DisplayRepresentation] = [
            .toggle: "Toggle", .pause: "Pause", .resume: "Resume",
        ]
    }

    @Parameter(title: "Action", default: .toggle) var action: Action

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        let engine = AppModel.shared.engine
        switch action {
        case .toggle: engine.setUserPaused(!engine.isUserPaused)
        case .pause: engine.setUserPaused(true)
        case .resume: engine.setUserPaused(false)
        }
        return .result()
    }
}

/// Starts a playlist on every display.
struct PlayPlaylistIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Wallpaper Playlist"
    static let description = IntentDescription("Rotates a Wlprz playlist on every display.")

    @Parameter(title: "Playlist") var playlist: PlaylistEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.playPlaylist(playlist.id)
        return .result()
    }
}

/// The intents offered as zero-setup Siri and Spotlight shortcuts.
struct WlprzShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextWallpaperIntent(), phrases: ["Next wallpaper in \(.applicationName)"],
                    shortTitle: "Next Wallpaper", systemImageName: "forward.fill")
        AppShortcut(intent: SetPlaybackPausedIntent(), phrases: ["Pause \(.applicationName)", "Toggle \(.applicationName)"],
                    shortTitle: "Pause or Resume", systemImageName: "playpause.fill")
        AppShortcut(intent: SetWallpaperIntent(), phrases: ["Set wallpaper in \(.applicationName)"],
                    shortTitle: "Set Wallpaper", systemImageName: "photo.on.rectangle")
    }
}
