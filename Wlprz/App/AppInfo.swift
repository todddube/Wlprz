//
//  AppInfo.swift
//  Wlprz · Wlprz
//
//  The app's identity (name, version, build, links) read from the bundle's Info.plist.
//

import Foundation

/// Name, version and links shown in the About panel, Settings and the menu bar.
///
/// Everything comes from Info.plist, which takes the version from `project.yml`
/// (`MARKETING_VERSION`) and the build number from the git commit count (see the Makefile),
/// so there's one place to change each.
enum AppInfo {
    static var name: String { string("CFBundleDisplayName") ?? "Wlprz" }
    /// The marketing version, e.g. "0.5.0".
    static var version: String { string("CFBundleShortVersionString") ?? "?" }
    /// The build number: the git commit count when built with `make`.
    static var build: String { string("CFBundleVersion") ?? "?" }
    static var versionLine: String { "Version \(version) (\(build))" }
    static var copyright: String { string("NSHumanReadableCopyright") ?? "" }

    /// The GitHub repository; its front page renders the README.
    static var repository: URL {
        string("WlprzRepositoryURL").flatMap(URL.init(string:)) ?? fallbackRepository
    }
    static var readme: URL { repository.appending(path: "blob/main/README.md") }
    static var issues: URL { repository.appending(path: "issues") }

    private static let fallbackRepository = URL(string: "https://github.com/todddube/Wlprz")!

    private static func string(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
