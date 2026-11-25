//
//  MediaImporter.swift
//  Wlprz · Wlprz
//
//  The Creator pipeline: copy or re-encode user media into the library and thumbnail it.
//

@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Options chosen in the Creator sheet.
nonisolated struct ImportOptions: Sendable {
    var title: String
    var tags: [String] = []
    var motion: Wallpaper.Motion = .slow
    /// Seconds into the video where the loop starts; `nil` keeps the original start.
    var trimStart: Double?
    /// Seconds into the video where the loop ends; `nil` keeps the original end.
    var trimEnd: Double?
    /// Re-encode to HEVC. Trimming always implies a re-encode.
    var optimize = false
    var dropAudio = true
}

/// Why an import failed, phrased for the alert the library window shows.
nonisolated enum ImportError: LocalizedError {
    case unsupportedType(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): "“\(ext)” files can't be used as wallpapers."
        case .exportFailed(let reason): "The video couldn't be converted: \(reason)"
        }
    }
}

/// Imports files into the library folder.
///
/// The async entry points are `@concurrent`: under Approachable Concurrency a plain
/// `nonisolated async` function would run on the caller's (main) actor, and copying or
/// transcoding a multi-gigabyte video there freezes the UI and the desktop scenes.
nonisolated enum MediaImporter {
    static let acceptedTypes: [UTType] = [.movie, .image]

    static func isVideo(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie)) ?? false
    }

    static func isImage(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image)) ?? false
    }

    /// The video's duration in seconds, for the trim sliders.
    @concurrent
    static func duration(of url: URL) async -> Double {
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0 // unreadable → no trim UI
        return seconds.isFinite ? seconds : 0
    }

    /// Imports `source` and returns the wallpaper to add. The caller owns security scope.
    ///
    /// - Parameter progress: called with 0…1 while a video is re-encoded (not for copies).
    @concurrent
    static func importMedia(
        from source: URL, options: ImportOptions, folders: LibraryFolders,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Wallpaper {
        let id = UUID()
        let ext = source.pathExtension.lowercased()
        let kind: Wallpaper.Kind

        if isVideo(source) {
            let needsExport = options.optimize || options.trimStart != nil || options.trimEnd != nil
            if needsExport {
                let name = "\(id.uuidString).mov"
                try await exportHEVC(from: source, to: folders.media.appending(path: name), options: options, progress: progress)
                kind = .video(fileName: name)
            } else {
                let name = "\(id.uuidString).\(ext)"
                try FileManager.default.copyItem(at: source, to: folders.media.appending(path: name))
                kind = .video(fileName: name)
            }
        } else if isImage(source) {
            let name = "\(id.uuidString).\(ext)"
            try FileManager.default.copyItem(at: source, to: folders.media.appending(path: name))
            kind = .image(fileName: name)
        } else {
            throw ImportError.unsupportedType(ext)
        }

        let wallpaper = Wallpaper(
            id: id,
            title: options.title.isEmpty ? source.deletingPathExtension().lastPathComponent : options.title,
            kind: kind,
            tags: options.tags,
            motion: kind.isAnimated ? options.motion : .still,
            energy: kind.isAnimated ? .balanced : .efficient
        )
        if let media = kind.fileName.map({ folders.media.appending(path: $0) }) {
            // A missing thumbnail only degrades the grid; the import itself succeeded.
            try? await Thumbnailer.writeThumbnail(for: media, isVideo: kind.isAnimated,
                                                  to: folders.thumbnails.appending(path: "\(id.uuidString).jpg"))
        }
        return wallpaper
    }

    /// Copies a file off the main actor (images can be tens of megabytes).
    @concurrent
    static func copyFile(_ source: URL, to destination: URL) async throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    @concurrent
    private static func exportHEVC(
        from source: URL, to destination: URL, options: ImportOptions,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        let start = CMTime(seconds: max(0, options.trimStart ?? 0), preferredTimescale: 600)
        let end = options.trimEnd.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? duration
        let range = CMTimeRange(start: start, end: CMTimeMinimum(end, duration))

        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try target.insertTimeRange(range, of: track, at: .zero)
            target.preferredTransform = try await track.load(.preferredTransform)
        }
        if !options.dropAudio {
            for track in try await asset.loadTracks(withMediaType: .audio) {
                guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try target.insertTimeRange(range, of: track, at: .zero)
            }
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw ImportError.exportFailed("HEVC export isn't available on this Mac.")
        }
        // Report progress alongside the export; the monitor ends when the export does.
        // `export(to:as:)` and `states(updateInterval:)` are designed to be used concurrently
        // on one session, but the SDK doesn't mark the class Sendable.
        nonisolated(unsafe) let observed = session
        let monitor = Task {
            for await state in observed.states(updateInterval: 0.25) {
                if case .exporting(let p) = state { progress?(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        do {
            try await session.export(to: destination, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: destination) // remove a partial file if one was written
            throw ImportError.exportFailed(error.localizedDescription)
        }
    }
}

/// Generates thumbnails and full-size stills from library media.
nonisolated enum Thumbnailer {
    static let thumbnailWidth: CGFloat = 480

    @concurrent
    static func writeThumbnail(for media: URL, isVideo: Bool, to destination: URL) async throws {
        let image = try await frame(of: media, isVideo: isVideo, maxPixel: thumbnailWidth)
        try write(image, to: destination, type: .jpeg, quality: 0.8)
    }

    /// Writes a full-resolution still (used as the macOS desktop picture / Lock Screen).
    @concurrent
    static func writeStill(for media: URL, isVideo: Bool, to destination: URL) async throws {
        let image = try await frame(of: media, isVideo: isVideo, maxPixel: nil)
        try write(image, to: destination, type: .heic, quality: 0.9)
    }

    private static func frame(of media: URL, isVideo: Bool, maxPixel: CGFloat?) async throws -> CGImage {
        if isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media))
            generator.appliesPreferredTrackTransform = true
            if let maxPixel { generator.maximumSize = CGSize(width: maxPixel, height: maxPixel) }
            // A frame a moment in avoids black fade-in openings.
            return try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        }
        guard let source = CGImageSourceCreateWithURL(media as CFURL, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let maxPixel { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        let image = maxPixel == nil
            ? CGImageSourceCreateImageAtIndex(source, 0, nil)
            : CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        guard let image else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
