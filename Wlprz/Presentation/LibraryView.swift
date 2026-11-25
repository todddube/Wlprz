//
//  LibraryView.swift
//  Wlprz · Wlprz
//
//  The library window: sidebar of categories and playlists, wallpaper grid, inspector.
//

import SwiftUI
import UniformTypeIdentifiers

/// Sidebar destinations.
enum LibrarySection: Hashable {
    case all, videos, images, scenes, favorites
    case playlist(UUID)

    var title: String {
        switch self {
        case .all: "All Wallpapers"
        case .videos: "Videos"
        case .images: "Images"
        case .scenes: "Scenes"
        case .favorites: "Favorites"
        case .playlist: "Playlist"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .videos: "film"
        case .images: "photo"
        case .scenes: "sparkles"
        case .favorites: "heart"
        case .playlist: "music.note.list"
        }
    }

    static let categories: [LibrarySection] = [.all, .videos, .images, .scenes, .favorites]
}

/// Grid sort orders; the raw value is the menu label.
enum LibrarySort: String, CaseIterable {
    case recent = "Recently Added", title = "Title"
}

/// The library window: categories and playlists, the filtered grid, and the inspector.
///
/// Also the import entry point (toolbar, `fileImporter`, drag and drop).
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection? = .all
    @State private var selection: UUID?
    @State private var query = ""
    @State private var motion: Wallpaper.Motion?
    @State private var format: Wallpaper.Format?
    @State private var sort = LibrarySort.recent
    @State private var showingImporter = false
    @State private var pickedFile: PickedFile?
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } content: {
            Group {
                if case .playlist(let id)? = section, let playlist = model.store.playlist(id: id) {
                    PlaylistEditor(playlist: playlist, selection: $selection)
                } else {
                    grid
                }
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        } detail: {
            if let selection, let wallpaper = model.store.wallpaper(id: selection) {
                // A fresh identity per wallpaper makes onDisappear save unsaved edits on reselect.
                InspectorView(wallpaper: wallpaper)
                    .id(wallpaper.id)
            } else {
                ContentUnavailableView("No Selection", systemImage: "photo.on.rectangle",
                                       description: Text("Choose a wallpaper to preview and set it."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbar }
        .searchable(text: $query, placement: .toolbar, prompt: "Search titles and tags")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: MediaImporter.acceptedTypes) { result in
            if case .success(let url) = result { pickedFile = PickedFile(url: url) }
        }
        .sheet(item: $pickedFile) { file in
            CreatorView(source: file.url)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { model.importError != nil },
            set: { if !$0 { model.importError = nil } }
        )) {
            Button("OK") { model.importError = nil }
        } message: {
            Text(model.importError ?? "")
        }
        .dropDestination(for: URL.self) { urls, _ in
            let media = urls.filter { MediaImporter.isVideo($0) || MediaImporter.isImage($0) }
            guard !media.isEmpty else { return false }
            Task { await model.quickImport(media) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section("Library") {
                ForEach(LibrarySection.categories, id: \.self) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            Section("Playlists") {
                ForEach(model.store.playlists) { playlist in
                    Label(playlist.name, systemImage: LibrarySection.playlist(playlist.id).symbol)
                        .tag(LibrarySection.playlist(playlist.id))
                        .contextMenu {
                            Button("Play on All Displays") { model.playPlaylist(playlist.id) }
                            Button("Delete Playlist", role: .destructive) {
                                if section == .playlist(playlist.id) { section = .all }
                                model.deletePlaylist(playlist.id)
                            }
                        }
                }
                Button {
                    let playlist = model.store.createPlaylist(named: "New Playlist")
                    section = .playlist(playlist.id)
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    // MARK: - Grid

    private var filtered: [Wallpaper] {
        let items = model.store.wallpapers.filter { wallpaper in
            let inSection = switch section ?? .all {
            case .all: true
            case .videos: if case .video = wallpaper.kind { true } else { false }
            case .images: if case .image = wallpaper.kind { true } else { false }
            case .scenes: wallpaper.isScene
            case .favorites: wallpaper.isFavorite
            case .playlist: true
            }
            return inSection && wallpaper.matches(query: query) && (motion == nil || wallpaper.motion == motion)
                && (format.map(wallpaper.fits) ?? true)
        }
        switch sort {
        case .recent: return items.sorted { $0.dateAdded > $1.dateAdded }
        case .title: return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private var grid: some View {
        let items = filtered
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)], spacing: 14) {
                ForEach(items) { wallpaper in
                    WallpaperCell(wallpaper: wallpaper, isSelected: selection == wallpaper.id)
                        .onTapGesture { selection = wallpaper.id }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { model.setWallpaper(wallpaper.id) })
                        .contextMenu { WallpaperMenu(wallpaper: wallpaper) }
                }
            }
            .padding(16)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Wallpapers", systemImage: "photo.stack")
                } description: {
                    Text("Drop videos or images here, or click Import.")
                }
            }
        }
        .navigationTitle((section ?? .all).title)
        .navigationSubtitle("\(items.count) wallpapers")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.importsInFlight > 0 {
                ProgressView().controlSize(.small)
            }
            Picker("Motion", selection: $motion) {
                Text("Any Motion").tag(Wallpaper.Motion?.none)
                ForEach(Wallpaper.Motion.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Picker("Format", selection: $format) {
                Text("Any Format").tag(Wallpaper.Format?.none)
                ForEach(Wallpaper.Format.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            .help("Standard (16:9, 16:10) or Ultrawide (21:9 and wider); scenes fit both")
            Picker("Sort", selection: $sort) {
                ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Button {
                showingImporter = true
            } label: {
                Label("Import", systemImage: "plus")
            }
            .help("Create a wallpaper from a video or image")
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Wlprz Settings")
        }
    }
}

/// A file picked for the Creator sheet; wraps the URL for `.sheet(item:)`.
struct PickedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The right-click / "…" actions shared by the grid and the playlist editor.
struct WallpaperMenu: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper

    var body: some View {
        Button("Set on All Displays") { model.setWallpaper(wallpaper.id) }
        if model.engine.displays.count > 1 {
            Menu("Set on Display") {
                ForEach(model.engine.displays) { display in
                    Button(display.name) { model.setWallpaper(wallpaper.id, onDisplay: display.id) }
                }
            }
        }
        if !model.store.playlists.isEmpty {
            Menu("Add to Playlist") {
                ForEach(model.store.playlists) { playlist in
                    Button(playlist.name) { model.store.add(wallpaper.id, toPlaylist: playlist.id) }
                }
            }
        }
        Button(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            model.store.toggleFavorite(wallpaper.id)
        }
        if !wallpaper.isScene {
            Divider()
            Button("Delete", role: .destructive) { model.delete(wallpaper.id) }
        }
    }
}

/// A grid cell: thumbnail, title, and badges.
struct WallpaperCell: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WallpaperThumbnail(wallpaper: wallpaper, animate: hovering)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if model.engine.nowPlaying.values.contains(wallpaper.id) {
                        Image(systemName: "play.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.title3)
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
            HStack(spacing: 4) {
                Text(wallpaper.title).lineLimit(1)
                if wallpaper.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
                Spacer()
                KindBadge(kind: wallpaper.kind)
            }
            .font(.callout)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}

/// An icon for the wallpaper's kind, with the name as its tooltip.
struct KindBadge: View {
    let kind: Wallpaper.Kind

    var body: some View {
        let (text, symbol) = switch kind {
        case .video: ("Video", "film")
        case .image: ("Image", "photo")
        case .scene: ("Scene", "sparkles")
        }
        Label(text, systemImage: symbol)
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .help(text)
    }
}

/// A wallpaper's preview: a cached JPEG for media, a live (or frozen) render for scenes.
struct WallpaperThumbnail: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    var animate: Bool
    @State private var sceneState = SceneRenderState()

    var body: some View {
        switch wallpaper.kind {
        case .scene(let scene):
            SceneView(scene: scene, state: sceneState)
                .onAppear { configureScene() }
                .onChange(of: animate) { configureScene() }
        case .video, .image:
            let url = model.store.thumbnailURL(for: wallpaper.id)
            // The revision forces a reload after an import writes the file.
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                }
            }
            .id("\(wallpaper.id)-\(model.store.thumbnailRevision)")
        }
    }

    private func configureScene() {
        sceneState.maxFPS = 24
        sceneState.resolutionScale = 0.5
        sceneState.isPaused = !animate
    }
}
