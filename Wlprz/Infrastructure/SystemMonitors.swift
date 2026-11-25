//
//  SystemMonitors.swift
//  Wlprz · Wlprz
//
//  Samples power, thermal, sleep/lock and window-coverage state for the playback policy.
//

import AppKit
import CoreGraphics
import IOKit.ps

// MARK: - Power

/// Reads the battery and Low Power Mode state.
nonisolated enum PowerState {
    /// `true` when the Mac is drawing from its internal battery.
    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false } // desktops have no power-source info; treat as AC
        return (type as String) == kIOPSBatteryPowerValue
    }

    static var thermal: SystemConditions.Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}

// MARK: - Displays

/// A connected screen, with the stable identity used to key its settings.
struct DisplayInfo: Identifiable, Hashable {
    /// `CGDisplayCreateUUIDFromDisplayID`, stable across reconnects and reordering.
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    /// The screen frame in AppKit (bottom-left origin) coordinates.
    let frame: CGRect
    let maxFPS: Int

    /// A display described directly; used by tests, which have no real screens to spare.
    init(id: String, displayID: CGDirectDisplayID = 0, name: String, frame: CGRect, maxFPS: Int = 60) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.maxFPS = maxFPS
    }

    init?(screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        self.id = string
        self.displayID = displayID
        self.name = screen.localizedName
        self.frame = screen.frame
        self.maxFPS = max(30, screen.maximumFramesPerSecond)
    }

    static var current: [DisplayInfo] { NSScreen.screens.compactMap(DisplayInfo.init(screen:)) }

    var screen: NSScreen? {
        NSScreen.screens.first { DisplayInfo(screen: $0)?.displayID == displayID }
    }
}

// MARK: - Window coverage

/// Measures how much of each display other apps' windows cover.
///
/// Uses `CGWindowListCopyWindowInfo` bounds only (no titles), which needs no Screen
/// Recording permission. Windows are rasterised onto a coarse grid so overlapping
/// windows aren't double-counted.
nonisolated enum CoverageSampler {
    private static let columns = 48
    private static let rows = 30

    /// Coverage 0…1 per display id.
    static func sample(displays: [DisplayInfo], excludingPID pid: pid_t) -> [String: Double] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }

        let windows: [CGRect] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != pid,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return rect
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var result: [String: Double] = [:]
        for display in displays {
            result[display.id] = coverage(of: cgFrame(forAppKit: display.frame, primaryHeight: primaryHeight), by: windows)
        }
        return result
    }

    /// Converts an AppKit screen frame (bottom-left origin) to CG window space, whose origin
    /// is the top-left corner of the primary display.
    static func cgFrame(forAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The fraction of `frame` covered by the union of `windows`, on a grid.
    static func coverage(of frame: CGRect, by windows: [CGRect]) -> Double {
        let relevant = windows.compactMap { w -> CGRect? in
            let clipped = w.intersection(frame)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
        guard !relevant.isEmpty, frame.width > 0, frame.height > 0 else { return 0 }
        let cellW = frame.width / CGFloat(columns)
        let cellH = frame.height / CGFloat(rows)
        var covered = 0
        for row in 0..<rows {
            for col in 0..<columns {
                let center = CGPoint(x: frame.minX + (CGFloat(col) + 0.5) * cellW,
                                     y: frame.minY + (CGFloat(row) + 0.5) * cellH)
                if relevant.contains(where: { $0.contains(center) }) { covered += 1 }
            }
        }
        return Double(covered) / Double(columns * rows)
    }
}
