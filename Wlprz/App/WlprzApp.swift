//
//  WlprzApp.swift
//  Wlprz · Wlprz
//
//  App entry point: menu bar extra, library and About windows, and settings.
//

import AppKit
import SwiftUI

/// The app's scenes: a menu bar extra that is always present, plus on-demand windows.
///
/// Wlprz is a menu bar app (`LSUIElement`): no Dock icon unless the user turns one on in
/// Settings, and it keeps running with every window closed. Launching it again while it
/// runs opens the library window.
@main
struct WlprzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("About Wlprz", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed) // never opens by itself at launch

        Window("Wlprz Library", id: WindowID.library) {
            LibraryView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 700)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Scene identifiers for `openWindow(id:)`.
enum WindowID {
    static let library = "library"
    static let about = "about"
}

/// The menu bar icon. It is created at launch and lives as long as the app, so it is where
/// the window-opening action is handed to the model for code outside SwiftUI (the app delegate).
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.engine.isUserPaused ? "pause.rectangle" : "photo.on.rectangle.angled")
            .accessibilityLabel(model.engine.isUserPaused ? "Wlprz, paused" : "Wlprz")
            .onAppear {
                let openWindow = openWindow
                model.windowOpener = { id in
                    openWindow(id: id)
                    NSApp.activate()
                }
            }
    }
}

/// Starts the engine at launch, persists at quit, and turns a relaunch into "open the library".
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    /// Launching the app again while it runs (Finder, Spotlight, Launchpad) or clicking its
    /// optional Dock icon opens the library: the menu bar item may be hidden by the notch.
    /// `hasVisibleWindows` is ignored: the desktop wallpaper windows always count as visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.open(WindowID.library)
        return true
    }

    /// A menu bar app keeps running when its library window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
