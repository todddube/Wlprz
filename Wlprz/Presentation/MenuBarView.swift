//
//  MenuBarView.swift
//  Wlprz · Wlprz
//
//  The menu bar panel: what's playing per display, and quick playback controls.
//

import AppKit
import SwiftUI

/// The menu bar extra's panel: pause/next, per-display status and toggles, and app commands.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let engine = model.engine
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wlprz").font(.headline)
                Spacer()
                Button {
                    engine.setUserPaused(!engine.isUserPaused)
                } label: {
                    Image(systemName: engine.isUserPaused ? "play.fill" : "pause.fill")
                }
                .help(engine.isUserPaused ? "Resume" : "Pause")
                Button { engine.next() } label: { Image(systemName: "forward.fill") }
                    .help("Next wallpaper")
            }
            .buttonStyle(.borderless)

            ForEach(engine.displays) { display in
                DisplayRow(display: display)
            }

            if !model.store.playlists.isEmpty {
                Divider()
                Menu("Play Playlist") {
                    ForEach(model.store.playlists) { playlist in
                        Button(playlist.name) { model.playPlaylist(playlist.id) }
                    }
                }
            }

            Divider()
            HStack {
                Button("Library…") {
                    openWindow(id: WindowID.library)
                    NSApp.activate()
                }
                Button("Settings…") {
                    openSettings()
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// One display's thumbnail, status line and enable switch.
private struct DisplayRow: View {
    @Environment(AppModel.self) private var model
    let display: DisplayInfo

    var body: some View {
        let id = model.engine.nowPlaying[display.id]
        HStack(spacing: 10) {
            Group {
                if let id, let wallpaper = model.store.wallpaper(id: id) {
                    WallpaperThumbnail(wallpaper: wallpaper, animate: false)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(.rect(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).font(.caption).foregroundStyle(.secondary)
                Text(model.status(forDisplay: display.id)).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.store.preferences.config(forDisplay: display.id).isEnabled },
                set: { model.engine.setDisplay(display.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Show Wlprz on this display")
        }
    }
}
