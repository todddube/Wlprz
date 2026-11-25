//
//  WlprzApp.swift
//  Wlprz · Wlprz
//
//  App entry point: menu bar extra, library window and settings.
//

import AppKit
import SwiftUI

/// The app's scenes: a menu bar extra that is always present, plus on-demand windows.
@main
struct WlprzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Wlprz", systemImage: "photo.on.rectangle.angled") {
            MenuBarView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

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
}

/// Starts the engine at launch and persists at quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    /// A menu bar app keeps running when its library window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
