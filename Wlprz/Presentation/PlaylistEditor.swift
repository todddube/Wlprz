//
//  PlaylistEditor.swift
//  Wlprz · Wlprz
//
//  Edits a playlist: items, shuffle, rotation interval and time-of-day schedule.
//

import SwiftUI

/// Edits one playlist in place; every change is saved and re-applied to the displays immediately.
struct PlaylistEditor: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    @Binding var selection: UUID?

    private static let intervals = [0, 5, 15, 30, 60, 180, 720, 1440]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: binding(\.name))
                HStack {
                    Button("Play on All Displays") { model.playPlaylist(playlist.id) }
                        .buttonStyle(.borderedProminent)
                    if model.engine.displays.count > 1 {
                        Menu("Play on Display") {
                            ForEach(model.engine.displays) { display in
                                Button(display.name) { model.playPlaylist(playlist.id, onDisplay: display.id) }
                            }
                        }
                        .fixedSize()
                    }
                }
            }

            Section("Rotation") {
                Toggle("Shuffle", isOn: binding(\.shuffle))
                    .disabled(playlist.usesSchedule)
                Picker("Change every", selection: binding(\.intervalMinutes)) {
                    ForEach(Self.intervals, id: \.self) { Text(intervalLabel($0)).tag($0) }
                }
                .disabled(playlist.usesSchedule)
                if playlist.usesSchedule {
                    Text("A schedule is set, so it decides what plays.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Wallpapers") {
                if playlist.wallpaperIDs.isEmpty {
                    Text("Add wallpapers from the library with right-click → Add to Playlist.")
                        .foregroundStyle(.secondary)
                }
                ForEach(playlist.wallpaperIDs, id: \.self) { id in
                    if let wallpaper = model.store.wallpaper(id: id) {
                        HStack {
                            WallpaperThumbnail(wallpaper: wallpaper, animate: false)
                                .frame(width: 56, height: 35)
                                .clipShape(.rect(cornerRadius: 4))
                            Text(wallpaper.title)
                            Spacer()
                        }
                        .contentShape(.rect)
                        .onTapGesture { selection = id }
                    }
                }
                .onMove { from, to in edit { $0.wallpaperIDs.move(fromOffsets: from, toOffset: to) } }
                .onDelete { offsets in edit { $0.wallpaperIDs.remove(atOffsets: offsets) } }
            }

            Section {
                ForEach(playlist.schedule.sorted { $0.startMinute < $1.startMinute }) { slot in
                    ScheduleRow(slot: slot, choices: playlist.wallpaperIDs) { updated in
                        edit { list in
                            if let index = list.schedule.firstIndex(where: { $0.id == slot.id }) {
                                if let updated { list.schedule[index] = updated } else { list.schedule.remove(at: index) }
                            }
                        }
                    }
                }
                Button("Add Time Slot") {
                    guard let first = playlist.wallpaperIDs.first else { return }
                    edit { $0.schedule.append(.init(startMinute: 8 * 60, wallpaperID: first)) }
                }
                .disabled(playlist.wallpaperIDs.isEmpty)
            } header: {
                Text("Schedule")
            } footer: {
                Text("Each slot plays from its start time until the next slot begins.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(playlist.name)
    }

    private func edit(_ change: (inout Playlist) -> Void) {
        var updated = playlist
        change(&updated)
        model.store.update(updated)
        model.engine.preferencesDidChange()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Playlist, T>) -> Binding<T> {
        Binding(get: { playlist[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func intervalLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Manually"
        case ..<60: "\(minutes) minutes"
        case 60: "Hour"
        case 1440: "Day"
        default: "\(minutes / 60) hours"
        }
    }
}

/// One schedule slot; reports an edit, or `nil` to delete the slot.
private struct ScheduleRow: View {
    @Environment(AppModel.self) private var model
    let slot: Playlist.ScheduleSlot
    let choices: [UUID]
    let onChange: (Playlist.ScheduleSlot?) -> Void

    var body: some View {
        HStack {
            DatePicker("Starts", selection: Binding(
                get: {
                    // Setting hour/minute (not adding seconds) stays correct on DST-change days.
                    Calendar.current.date(bySettingHour: slot.startMinute / 60, minute: slot.startMinute % 60,
                                          second: 0, of: .now) ?? .now
                },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    var updated = slot
                    updated.startMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    onChange(updated)
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            Picker("Wallpaper", selection: Binding(
                get: { slot.wallpaperID },
                set: { var updated = slot; updated.wallpaperID = $0; onChange(updated) }
            )) {
                ForEach(choices, id: \.self) { id in
                    Text(model.store.wallpaper(id: id)?.title ?? "Missing").tag(id)
                }
            }
            .labelsHidden()
            Button(role: .destructive) { onChange(nil) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }
}
