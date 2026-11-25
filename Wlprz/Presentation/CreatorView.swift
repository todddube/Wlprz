//
//  CreatorView.swift
//  Wlprz · Wlprz
//
//  The Creator sheet: turn a picked video or image into a library wallpaper.
//

import AVKit
import SwiftUI

/// The import sheet for one picked file: metadata, trim and HEVC options, then import.
///
/// Holds security-scoped access to `source` for as long as the sheet previews it.
struct CreatorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let source: URL

    @State private var title = ""
    @State private var tags = ""
    @State private var motion = Wallpaper.Motion.slow
    @State private var duration = 0.0
    @State private var trimStart = 0.0
    @State private var trimEnd = 0.0
    @State private var optimize = true
    @State private var keepAudio = false
    @State private var setAfterImport = true
    @State private var working = false
    @State private var player: AVPlayer?
    /// HEVC export progress, 0…1, once the encoder reports any.
    @State private var exportProgress: Double?

    private var isVideo: Bool { MediaImporter.isVideo(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .background(.black)

            Form {
                TextField("Title", text: $title)
                TextField("Tags", text: $tags, prompt: Text("calm, night, ocean"))
                if isVideo {
                    Picker("Motion", selection: $motion) {
                        ForEach(Wallpaper.Motion.allCases.filter { $0 != .still }, id: \.self) { Text($0.label) }
                    }
                    if duration > 1 {
                        LabeledContent("Loop") {
                            VStack(alignment: .leading) {
                                Slider(value: $trimStart, in: 0...duration) { Text("Start") }
                                Slider(value: $trimEnd, in: 0...duration) { Text("End") }
                                Text("\(format(trimStart)) – \(format(trimEnd)) of \(format(duration))")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .onChange(of: trimStart) { if trimEnd < trimStart + 1 { trimEnd = min(duration, trimStart + 1) } }
                        .onChange(of: trimEnd) { if trimStart > trimEnd - 1 { trimStart = max(0, trimEnd - 1) } }
                    }
                    Toggle("Optimize for wallpaper (HEVC)", isOn: $optimize)
                        .help("Re-encodes to HEVC for lower power use. Trimming always re-encodes.")
                    Toggle("Keep audio", isOn: $keepAudio)
                }
                Toggle("Set as wallpaper after import", isOn: $setAfterImport)
            }
            .formStyle(.grouped)

            HStack {
                if working {
                    if let exportProgress {
                        ProgressView(value: exportProgress).frame(width: 140)
                        Text("Converting… \(exportProgress.formatted(.percent.precision(.fractionLength(0))))")
                            .foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small)
                        Text(isVideo && needsExport ? "Converting…" : "Importing…").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    createTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") { createTask = Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
            .padding(16)
        }
        .frame(width: 520)
        .task { await prepare() }
        .onDisappear {
            createTask?.cancel()
            player?.pause()
            if didAccess { source.stopAccessingSecurityScopedResource() }
        }
    }

    @State private var didAccess = false
    @State private var previewImage: NSImage?
    /// The running import, kept so Cancel stops the HEVC export instead of orphaning it.
    @State private var createTask: Task<Void, Never>?

    @ViewBuilder
    private var preview: some View {
        if isVideo, let player {
            VideoPlayer(player: player).disabled(true)
        } else if let image = previewImage {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
        } else {
            ProgressView()
        }
    }

    private var needsExport: Bool {
        optimize || trimStart > 0.05 || (duration > 0 && trimEnd < duration - 0.05)
    }

    private func prepare() async {
        // The importer's URL is security-scoped; hold access while the sheet previews it.
        didAccess = source.startAccessingSecurityScopedResource()
        title = source.deletingPathExtension().lastPathComponent
        guard isVideo else {
            // Decoded once here, not in `body`, so typing in the form doesn't re-read the file.
            previewImage = NSImage(contentsOf: source)
            return
        }
        duration = await MediaImporter.duration(of: source)
        trimEnd = duration
        let player = AVPlayer(url: source)
        player.isMuted = true
        player.play()
        self.player = player
    }

    private func create() async {
        working = true
        exportProgress = nil
        defer { working = false; exportProgress = nil }
        let trimmed = duration > 0 && (trimStart > 0.05 || trimEnd < duration - 0.05)
        let options = ImportOptions(
            title: title,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            motion: motion,
            trimStart: trimmed ? trimStart : nil,
            trimEnd: trimmed ? trimEnd : nil,
            optimize: optimize,
            dropAudio: !keepAudio
        )
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in exportProgress = value }
        }
        if let wallpaper = await model.importMedia(from: source, options: options, progress: report) {
            // A copy can't be interrupted mid-file; if the user cancelled meanwhile, undo it.
            if Task.isCancelled {
                model.delete(wallpaper.id)
                return
            }
            if setAfterImport { model.setWallpaper(wallpaper.id) }
            dismiss()
        }
    }

    private func format(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
