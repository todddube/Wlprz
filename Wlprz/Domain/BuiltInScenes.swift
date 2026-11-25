//
//  BuiltInScenes.swift
//  Wlprz · Wlprz
//
//  Catalogue entries for the shader scenes that ship inside the app.
//

import Foundation

/// The library entries for the built-in scenes.
///
/// Their ids are fixed so that display assignments and playlists that reference a scene
/// survive relaunches and library rebuilds.
nonisolated enum BuiltInScenes {
    static let all: [Wallpaper] = SceneID.allCases.map(wallpaper(for:))

    static func wallpaper(for scene: SceneID) -> Wallpaper {
        switch scene {
        case .aurora:
            make(scene, "00000000-0000-0000-0000-00000000A001", "Aurora",
                 ["nature", "calm", "green", "night"], .slow, .efficient)
        case .nebula:
            make(scene, "00000000-0000-0000-0000-00000000A002", "Nebula Drift",
                 ["space", "purple", "calm"], .slow, .balanced)
        case .orbs:
            make(scene, "00000000-0000-0000-0000-00000000A003", "Liquid Orbs",
                 ["abstract", "colorful", "interactive"], .medium, .balanced)
        case .constellation:
            make(scene, "00000000-0000-0000-0000-00000000A004", "Constellation",
                 ["space", "dark", "interactive", "minimal"], .slow, .efficient)
        case .duskWaves:
            make(scene, "00000000-0000-0000-0000-00000000A005", "Dusk Waves",
                 ["ocean", "sunset", "orange", "calm"], .medium, .intensive)
        }
    }

    private static func make(
        _ scene: SceneID, _ id: String, _ title: String, _ tags: [String],
        _ motion: Wallpaper.Motion, _ energy: Wallpaper.Energy
    ) -> Wallpaper {
        // The literals above are well-formed; a typo would be caught by the persistence tests.
        Wallpaper(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            kind: .scene(scene),
            tags: tags,
            motion: motion,
            energy: energy,
            dateAdded: .distantPast
        )
    }
}
