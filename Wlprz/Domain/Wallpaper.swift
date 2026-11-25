//
//  Wallpaper.swift
//  Wlprz · Wlprz
//
//  The wallpaper value type: what can be shown on a desktop and how it is described.
//

import Foundation

/// A single item in the library: a video, an image, or a built-in shader scene.
nonisolated struct Wallpaper: Codable, Hashable, Identifiable, Sendable {
    /// Where the pixels come from.
    enum Kind: Codable, Hashable, Sendable {
        /// A video file stored in the library folder, by file name.
        case video(fileName: String)
        /// An image file stored in the library folder, by file name.
        case image(fileName: String)
        /// A built-in Metal shader scene.
        case scene(SceneID)

        var isAnimated: Bool {
            if case .image = self { return false }
            return true
        }

        /// The library file backing this wallpaper, if it has one.
        var fileName: String? {
            switch self {
            case .video(let name), .image(let name): name
            case .scene: nil
            }
        }
    }

    /// How much visible movement the wallpaper has; used as a library filter.
    enum Motion: String, Codable, CaseIterable, Sendable {
        case still, slow, medium, dynamic

        var label: String { rawValue.capitalized }
    }

    /// The rough GPU/CPU cost of showing the wallpaper.
    enum Energy: String, Codable, CaseIterable, Sendable {
        case efficient, balanced, intensive

        var label: String { rawValue.capitalized }
    }

    /// Screen shape a wallpaper is made for, from its aspect ratio.
    enum Format: String, Codable, CaseIterable, Sendable {
        case standard, ultrawide

        var label: String { rawValue.capitalized }

        /// 21:9 is 2.33 and 32:9 is 3.56; 16:9 (1.78) and 16:10 (1.6) are standard.
        static let ultrawideMinimumRatio = 2.0
    }

    var id: UUID
    var title: String
    var kind: Kind
    var tags: [String]
    var isFavorite: Bool
    var motion: Motion
    var energy: Energy
    var dateAdded: Date
    /// Width ÷ height of the media, as displayed. `nil` for scenes (they fit any shape) and
    /// for media not measured yet.
    var aspectRatio: Double?

    init(
        id: UUID = UUID(),
        title: String,
        kind: Kind,
        tags: [String] = [],
        isFavorite: Bool = false,
        motion: Motion = .slow,
        energy: Energy = .balanced,
        dateAdded: Date = .now,
        aspectRatio: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.tags = tags
        self.isFavorite = isFavorite
        self.motion = motion
        self.energy = energy
        self.dateAdded = dateAdded
        self.aspectRatio = aspectRatio
    }

    /// The format of measured media; `nil` for scenes and for media not measured yet.
    var format: Format? {
        aspectRatio.map { $0 >= Format.ultrawideMinimumRatio ? .ultrawide : .standard }
    }

    /// Whether the wallpaper belongs under a format filter. Scenes match every format, and so
    /// does unmeasured media, so it stays findable until the launch backfill measures it.
    func fits(_ format: Format) -> Bool {
        self.format.map { $0 == format } ?? true
    }

    var isScene: Bool {
        if case .scene = kind { return true }
        return false
    }

    /// Case-insensitive match against the title and tags; an empty query matches everything.
    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(needle)
            || tags.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// Identifies one of the shader scenes compiled into the app.
nonisolated enum SceneID: String, Codable, CaseIterable, Sendable {
    case aurora, nebula, orbs, constellation, duskWaves

    /// The `switch (u.scene)` case in `sceneFragment` (Scenes.metal). Explicit, so
    /// reordering the cases can't silently draw the wrong scene.
    var metalIndex: Int32 {
        switch self {
        case .aurora: 0
        case .nebula: 1
        case .orbs: 2
        case .constellation: 3
        case .duskWaves: 4
        }
    }

    /// The fraction of the display's native pixels the desktop renders this scene at,
    /// before the policy's resolution scale (Efficient halves it). The layer upscales with
    /// smooth filtering.
    ///
    /// The scenes are soft gradients and noise, so native Retina resolution only multiplies
    /// GPU work: at 6016×3384 the noise scenes took ~50 ms of GPU per frame per display,
    /// over the whole 33 ms budget of a 30 fps frame. Scenes with fine, crisp detail (star
    /// points, wave edges) keep more pixels.
    var renderDetail: Double {
        switch self {
        case .aurora: 0.35
        case .nebula: 0.3
        case .orbs: 0.5
        case .constellation: 0.42
        case .duskWaves: 0.5
        }
    }
}
