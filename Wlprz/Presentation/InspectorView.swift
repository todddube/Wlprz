//
//  InspectorView.swift
//  Wlprz · Wlprz
//
//  Detail pane for one wallpaper: live preview, metadata editing and "set" actions.
//

import AppKit
import SwiftUI

/// The detail column for the selected wallpaper.
///
/// Title and tag edits are saved on Return or when the inspector disappears.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    @State private var title = ""
    @State private var tags = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WallpaperThumbnail(wallpaper: wallpaper, animate: true)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))

                HStack {
                    Button {
                        model.setWallpaper(wallpaper.id)
                    } label: {
                        Label("Set Wallpaper", systemImage: "desktopcomputer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Menu {
                        WallpaperMenu(wallpaper: wallpaper)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Form {
                    if wallpaper.isScene {
                        LabeledContent("Title", value: wallpaper.title)
                        LabeledContent("Tags", value: wallpaper.tags.joined(separator: ", "))
                    } else {
                        TextField("Title", text: $title)
                            .onSubmit(save)
                        TextField("Tags", text: $tags, prompt: Text("calm, night, ocean"))
                            .onSubmit(save)
                    }
                    Toggle("Favorite", isOn: Binding(
                        get: { wallpaper.isFavorite },
                        set: { _ in model.store.toggleFavorite(wallpaper.id) }
                    ))
                    LabeledContent("Type") { KindBadge(kind: wallpaper.kind).labelStyle(.titleAndIcon) }
                    LabeledContent("Motion", value: wallpaper.motion.label)
                    LabeledContent("Energy", value: wallpaper.energy.label)
                    if wallpaper.isScene {
                        LabeledContent("Interactive", value: "Follows the pointer; reacts to clicks")
                    }
                    if let url = model.store.mediaURL(for: wallpaper) {
                        LabeledContent("File") {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(.link)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(16)
        }
        .onAppear(perform: load)
        .onChange(of: wallpaper.id) { load() }
        .onDisappear(perform: save)
    }

    private func load() {
        title = wallpaper.title
        tags = wallpaper.tags.joined(separator: ", ")
    }

    private func save() {
        guard !wallpaper.isScene else { return }
        var updated = wallpaper
        updated.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? wallpaper.title : title
        updated.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if updated != wallpaper { model.store.update(updated) }
    }
}
