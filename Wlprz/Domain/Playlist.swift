//
//  Playlist.swift
//  Wlprz · Wlprz
//
//  Playlists and the pure rules that pick which of their wallpapers plays next.
//

import Foundation

/// An ordered set of wallpapers that rotates automatically.
nonisolated struct Playlist: Codable, Hashable, Identifiable, Sendable {
    /// A time-of-day slot: from `startMinute` (minutes after midnight) on, show `wallpaperID`.
    struct ScheduleSlot: Codable, Hashable, Identifiable, Sendable {
        var id = UUID()
        var startMinute: Int
        var wallpaperID: UUID
    }

    var id: UUID = UUID()
    var name: String
    var wallpaperIDs: [UUID] = []
    var shuffle: Bool = false
    /// Minutes between automatic changes; `0` means only change on request.
    var intervalMinutes: Int = 30
    /// When non-empty the schedule decides what plays, and the interval and shuffle are ignored.
    var schedule: [ScheduleSlot] = []

    var usesSchedule: Bool { !schedule.isEmpty }
}

/// Pure playlist rotation, separated from timers so it can be tested deterministically.
nonisolated enum PlaylistRotation {
    /// The wallpaper that should follow `current` in `playlist`.
    ///
    /// - Parameters:
    ///   - current: the wallpaper showing now, or `nil` when the playlist is just starting.
    ///   - available: ids that still exist in the library; deleted items are skipped.
    ///   - date: the time used for scheduled playlists.
    /// - Returns: `nil` when the playlist has nothing playable.
    static func next<G: RandomNumberGenerator>(
        in playlist: Playlist,
        after current: UUID?,
        available: Set<UUID>,
        at date: Date,
        calendar: Calendar = .current,
        using generator: inout G
    ) -> UUID? {
        if playlist.usesSchedule {
            return scheduled(in: playlist, at: date, calendar: calendar, available: available)
        }
        let items = playlist.wallpaperIDs.filter(available.contains)
        guard !items.isEmpty else { return nil }
        guard items.count > 1 else { return items[0] }

        if playlist.shuffle {
            // Never repeat the current wallpaper: a shuffle that "changes" to the same
            // image looks like a bug to the user.
            let candidates = items.filter { $0 != current }
            return candidates.randomElement(using: &generator)
        }
        guard let current, let index = items.firstIndex(of: current) else { return items[0] }
        return items[(index + 1) % items.count]
    }

    /// Convenience overload using the system random number generator.
    static func next(in playlist: Playlist, after current: UUID?, available: Set<UUID>, at date: Date = .now) -> UUID? {
        var generator = SystemRandomNumberGenerator()
        return next(in: playlist, after: current, available: available, at: date, using: &generator)
    }

    /// The slot active at `date`: the latest slot that started at or before that time of day,
    /// wrapping to yesterday's last slot before the first slot of the day.
    static func scheduled(in playlist: Playlist, at date: Date, calendar: Calendar = .current, available: Set<UUID>) -> UUID? {
        let slots = playlist.schedule
            .filter { available.contains($0.wallpaperID) }
            .sorted { $0.startMinute < $1.startMinute }
        guard let last = slots.last else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return (slots.last { $0.startMinute <= minute } ?? last).wallpaperID
    }

    /// When the slot active at `date` ends: the next slot start later today, or the first
    /// slot tomorrow. Like ``scheduled(in:at:calendar:available:)``, it ignores slots whose
    /// wallpaper is gone and slots that don't change the wallpaper. `nil` if unscheduled.
    static func nextSlotStart(
        in playlist: Playlist, after date: Date, calendar: Calendar = .current, available: Set<UUID>
    ) -> Date? {
        let slots = playlist.schedule.filter { available.contains($0.wallpaperID) }.sorted { $0.startMinute < $1.startMinute }
        // A slot is a real boundary only when its wallpaper differs from the one before it (cyclically).
        let starts = slots.indices.filter { i in
            slots[i].wallpaperID != slots[(i + slots.count - 1) % slots.count].wallpaperID
        }.map { slots[$0].startMinute }
        guard let first = starts.first else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if let next = starts.first(where: { $0 > minute }) {
            return calendar.date(bySettingHour: next / 60, minute: next % 60, second: 0, of: date)
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return nil }
        return calendar.date(bySettingHour: first / 60, minute: first % 60, second: 0, of: tomorrow)
    }
}
