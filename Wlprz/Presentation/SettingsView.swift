//
//  SettingsView.swift
//  Wlprz · Wlprz
//
//  Settings window: General, Playback and Displays tabs.
//

import SwiftUI

/// The Settings window, grouped by intent rather than by subsystem.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Playback", systemImage: "play.rectangle") { PlaybackSettings() }
            Tab("Displays", systemImage: "display.2") { DisplaySettings() }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

/// A binding into one preference that applies changes through the model.
@MainActor
private func preferenceBinding<T>(_ model: AppModel, _ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
    Binding(
        get: { model.store.preferences[keyPath: keyPath] },
        set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
    )
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        try LaunchAtLogin.set(enabled)
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Toggle("Match the macOS wallpaper and Lock Screen", isOn: preferenceBinding(model, \.syncSystemWallpaper))
            Text("Sets a still frame of each video or image as the system wallpaper, so the Lock Screen and the desktop after quitting match. Scenes leave the system wallpaper unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct PlaybackSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.store.preferences
        Form {
            Section("Performance") {
                Picker("Mode", selection: preferenceBinding(model, \.performance)) {
                    ForEach(Preferences.PerformanceMode.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                Text(prefs.performance.summary).font(.caption).foregroundStyle(.secondary)
            }
            Section("Motion") {
                Picker("Desktop motion", selection: preferenceBinding(model, \.desktopMotion)) {
                    ForEach(Preferences.DesktopMotion.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                Text(prefs.desktopMotion == .still
                     ? "Every wallpaper holds its current frame and uses no power to animate."
                     : "Videos loop and scenes animate, following the rules below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Pausing") {
                Picker("Desktop playback", selection: preferenceBinding(model, \.desktopPlayback)) {
                    ForEach(Preferences.DesktopPlayback.allCases, id: \.self) { Text($0.label) }
                }
                Toggle("Pause on battery", isOn: preferenceBinding(model, \.pauseOnBattery))
                Toggle("Pause in Low Power Mode", isOn: preferenceBinding(model, \.pauseInLowPowerMode))
                Text("Wallpapers always pause behind full-screen apps, while displays sleep and while the screen is locked. Hidden videos release their memory after 30 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio & Color") {
                Toggle("Mute video audio", isOn: preferenceBinding(model, \.isMuted))
                Slider(value: preferenceBinding(model, \.volume), in: 0...1) { Text("Volume") }
                    .disabled(prefs.isMuted)
                Toggle("Allow HDR video", isOn: preferenceBinding(model, \.allowsHDR))
            }
            Section("Status") {
                LabeledContent("Power", value: model.engine.conditions.onBattery ? "Battery" : "Power adapter")
                LabeledContent("Low Power Mode", value: model.engine.conditions.lowPowerMode ? "On" : "Off")
                LabeledContent("Thermal", value: String(describing: model.engine.conditions.thermal).capitalized)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.store.preferences
        Form {
            Picker("Arrangement", selection: preferenceBinding(model, \.mirrorsDisplays)) {
                Text("Same wallpaper on every display").tag(true)
                Text("Different wallpaper per display").tag(false)
            }
            .pickerStyle(.radioGroup)

            if prefs.mirrorsDisplays {
                SourcePicker(title: "Wallpaper", selection: prefs.mirrorSource) { model.engine.show($0) }
            }

            ForEach(model.engine.displays) { display in
                Section(display.name) {
                    Toggle("Use Wlprz on this display", isOn: Binding(
                        get: { prefs.config(forDisplay: display.id).isEnabled },
                        set: { model.engine.setDisplay(display.id, enabled: $0) }
                    ))
                    if !prefs.mirrorsDisplays {
                        SourcePicker(title: "Wallpaper",
                                     selection: prefs.config(forDisplay: display.id).source ?? prefs.mirrorSource) {
                            model.engine.show($0, onDisplay: display.id)
                        }
                    }
                    LabeledContent("Showing", value: model.status(forDisplay: display.id))
                    LabeledContent("Window coverage",
                                   value: (model.engine.coverage[display.id] ?? 0).formatted(.percent.precision(.fractionLength(0))))
                    LabeledContent("Refresh rate", value: "\(display.maxFPS) Hz")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Chooses a display's source: any library wallpaper or playlist.
private struct SourcePicker: View {
    @Environment(AppModel.self) private var model
    let title: String
    let selection: WallpaperSource?
    let onChange: (WallpaperSource) -> Void

    var body: some View {
        Picker(title, selection: Binding(
            get: { selection },
            set: { if let source = $0 { onChange(source) } }
        )) {
            if selection == nil { Text("None").tag(WallpaperSource?.none) }
            Section("Wallpapers") {
                ForEach(model.store.wallpapers) { wallpaper in
                    Text(wallpaper.title).tag(Optional(WallpaperSource.wallpaper(wallpaper.id)))
                }
            }
            if !model.store.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(model.store.playlists) { playlist in
                        Text(playlist.name).tag(Optional(WallpaperSource.playlist(playlist.id)))
                    }
                }
            }
        }
    }
}
