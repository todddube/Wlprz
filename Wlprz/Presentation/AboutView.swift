//
//  AboutView.swift
//  Wlprz · Wlprz
//
//  The About panel: icon, version and build, a summary, and links to the GitHub repo.
//

import AppKit
import SwiftUI

/// About Wlprz. Used as its own window and as the Settings "About" tab.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(AppInfo.name).font(.title.bold())
                Text(AppInfo.versionLine)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }

            Text("Live wallpapers for your Mac: videos, images and interactive shader scenes, with playlists and battery-aware playback.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link(destination: AppInfo.repository) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: AppInfo.readme) { Label("Read Me", systemImage: "book") }
                Link(destination: AppInfo.issues) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
            }
            .font(.callout)

            VStack(spacing: 2) {
                Text("macOS 26 or later · Apple silicon · needs no permissions")
                if !AppInfo.copyright.isEmpty { Text(AppInfo.copyright) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 400)
    }
}
