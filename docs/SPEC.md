# Wlprz — Product Spec

Wlprz is a native macOS live-wallpaper app: video, image and GPU-shader "scene"
wallpapers on the desktop, per display, with playlists, schedules, and aggressive
power management.

## 1. Design principles

- **A wallpaper nobody can see should cost nothing.** Coverage-based pausing is the core
  battery feature.
- **One decode shared across mirrored displays**, pausing only when all are hidden.
- **Scenes are GPU shaders**, not pre-rendered video: tiny on disk, resolution
  independent, interactive.
- **No private APIs.** There is no public API for an animated Lock Screen, so Wlprz keeps
  the macOS desktop picture *in sync* with a still frame of the current wallpaper
  (`NSWorkspace.setDesktopImageURL`): the Lock Screen, Mission Control and the desktop
  after quitting all match.
- **The user's own media is the library**, alongside a set of original built-in scenes.
  No backend, accounts or catalogue.
- **Mood switching is concrete:** time-of-day schedules plus tags and filters, which are
  testable.
- **Settings are grouped by intent** (General / Playback / Displays), and the live reason
  playback is paused is always shown.
- **Automation through App Intents** (Shortcuts).

---

## 2. Feature spec

### 2.1 Wallpaper kinds
| Kind | Source | Rendering |
|---|---|---|
| Video | User file (mov/mp4/m4v/HEVC/ProRes) copied into the library | `AVQueuePlayer` + `AVPlayerLooper`, seamless loop, aspect-fill `AVPlayerLayer` |
| Image | User file (heic/jpg/png/tiff) | Aspect-fill layer, static (zero CPU when shown) |
| Scene | Built-in Metal shader (`[[stitchable]]`) | SwiftUI `colorEffect`, driven by `TimelineView` at the policy fps; pointer-reactive |

Every wallpaper has: id, title, kind, tags, favourite flag, motion class
(Static/Slow/Medium/Dynamic), energy class (Efficient/Balanced/Intensive), date added, and
for media an aspect ratio (measured on import, rotation applied; older items are measured
at launch). The ratio gives a **format**: Ultrawide at 2:1 and wider (21:9, 32:9), otherwise
Standard (16:9, 16:10). Scenes are resolution independent and fit every format.

Built-in scenes (original): Aurora, Nebula Drift, Liquid Orbs, Constellation, Dusk Waves.
Scenes respond to the pointer (`NSEvent.mouseLocation` sampled per frame, so no
Accessibility/Input Monitoring permission) and to mouse-down ripples.

### 2.2 Library window
- Sidebar: All, Videos, Images, Scenes, Favourites, then Playlists.
- Grid of thumbnails (scenes animate live, small, at low fps while hovered), search field matching
  title and tags, motion filter, format filter (Standard / Ultrawide), sort (Recent / Title).
- Inspector: preview, title, tags, favourite, "Set as wallpaper" (All displays or a
  specific display), add to playlist, reveal file, delete; shows motion, energy and format.
- Import: toolbar button, `fileImporter`, or drag and drop onto the window.

### 2.3 Creator (import pipeline)
- Pick video or image → title, tags.
- Video options: trim start/end, **Optimise** (re-encode to HEVC, strips audio when
  "Mute" is chosen) via `AVAssetExportSession`; percentage progress shown; cancellable.
- Thumbnail generated with `AVAssetImageGenerator` / ImageIO.

### 2.4 Displays
- **Mirror** (one source on every enabled display) or **Per display** (own source each).
- Per-display **Enabled** toggle; disabled displays show the macOS wallpaper.
- A source is a wallpaper or a playlist.
- Displays identified by `CGDisplayCreateUUIDFromDisplayID` so assignments survive
  reconnection and reordering.
- Windows sit at the desktop window level, below desktop icons, on all Spaces,
  ignore the mouse, and rebuild on `didChangeScreenParametersNotification`.

### 2.5 Playlists
- Ordered wallpaper list, **shuffle**, **rotate every N minutes** (0 = manual).
- Optional **time-of-day schedule**: slots `(start time → wallpaper)`; the active slot is
  the latest one that started at or before now, wrapping past midnight.
- "Next wallpaper" from the menu bar, Shortcuts, or rotation timer. On a scheduled
  playlist, "Next" steps through its wallpapers and holds until the next slot starts.

### 2.6 Playback policy
Inputs: user pause, displays asleep, session locked, on battery, Low Power Mode,
thermal state, memory pressure, per-display window coverage, settings.

| Rule | Effect |
|---|---|
| User paused | pause all |
| Desktop motion: Still | pause all (frame held, nothing unloaded) |
| Displays asleep / screen locked | pause all |
| On battery + "Pause on battery" | pause all |
| Low Power Mode + "Pause in Low Power Mode" | pause all |
| Display fully covered (full-screen app) | pause that display |
| "When exposed" + coverage > 50 % | pause that display |
| Thermal critical / memory pressure critical | pause scenes |
| Coverage ≥ 90 %, thermal serious, memory warning, Low Power Mode | scenes capped at 30 fps |
| Performance: Automatic | scenes 30 fps, 60 fps while mouse button down on AC |
| Performance: Maximum | display max refresh (30 in Low Power Mode) |
| Performance: Efficient | scenes 30 fps at half resolution; videos unaffected (AVFoundation only honours decode-size limits for HLS; import with **Optimise** to reduce cost) |
| Hidden for > 30 s | video sessions unload their player item to free memory, reload on reveal |

A wallpaper shown on several displays is one **session**; it plays if any of its
displays may play. The menu bar shows the current pause reason.

Coverage is computed from `CGWindowListCopyWindowInfo` (on-screen, layer 0, other
apps, alpha > 0) rasterised onto a coarse grid per display (handles overlap), sampled
every 2 s and immediately on app activation changes.

### 2.7 System integration
- **Menu bar extra**: now-playing per display, Pause/Resume, Next, Open Library,
  Settings, Quit.
- **Sync macOS wallpaper** (default on): writes a full-resolution still of the current
  wallpaper and sets it as the system desktop picture for that display → matching Lock
  Screen and a seamless desktop after quit. One still is extracted per video and shared by
  every display; each display gets its own uniquely named copy, and older copies are
  deleted once macOS points at the new one. Scenes leave the system wallpaper alone.
  *Limitation:* an Aerial or dynamic macOS wallpaper has no public API to set it back, so
  once sync has replaced one, turning sync off or quitting doesn't restore it.
- **Launch at login** via `SMAppService.mainApp`.
- **Audio**: muted by default; optional volume; only one display's player emits sound.
- **HDR** toggle for EDR video.
- **App Intents / Shortcuts**: Set Wallpaper, Next Wallpaper, Pause/Resume, Play
  Playlist.

### 2.8 Settings
- General: Launch at login, Sync macOS wallpaper.
- Playback: Performance mode, Desktop motion (Animated / Still), Pause on battery, Pause
  in Low Power Mode, Desktop playback (Always / When exposed), Audio (mute + volume), HDR.
- Displays: Mirror vs per display; the mirror source, or per-display enable + source
  (any wallpaper or playlist).

### 2.9 Non-goals
Community catalogue, accounts, licensing/watermark, live animated Lock Screen,
Intel support.

---

## 3. Architecture

```
Wlprz/
  App/            WlprzApp (scenes), AppModel (composition root, singleton for intents)
  Domain/         Pure value types + policy: Wallpaper, Playlist, Preferences,
                  DisplayAssignment, PlaybackPolicy, PlaylistRotation, BuiltInScenes
  Infrastructure/ LibraryStore (JSON in Application Support), MediaImporter,
                  Thumbnailer, PowerMonitor, CoverageMonitor, DisplayIdentity,
                  SystemWallpaperSync, LaunchAtLogin
  Engine/         WallpaperEngine (sessions, windows, policy loop), DesktopWindow,
                  VideoSession, SceneView, shaders (Scenes.metal)
  Presentation/   LibraryView, InspectorView, CreatorView, PlaylistEditor,
                  MenuBarView, SettingsView
  Intents/        App Intents + AppShortcutsProvider
WlprzTests/       Domain: policy, rotation, persistence, format, coverage
                  Engine: assignment, mirror transitions, Next, cursors, schedule
                  overrides, shared sessions, unload timing (fake displays + clock
                  via EngineDependencies; the test host app stays idle)
docs/TRACKER.md   Feature status and work plan
```

Rules: `Domain` imports Foundation only and is fully unit-tested. All UI state is
`@MainActor` (default isolation). Platform: macOS 26+, Apple silicon, sandboxed with
user-selected read-only file access.
