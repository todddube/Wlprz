# Wlprz

Live wallpapers for macOS: videos, images and interactive GPU shader scenes on your
desktop, per display, with playlists, schedules and battery-aware playback.

**Version 0.5.0** · macOS 26+ · Apple silicon

## Using it
Wlprz is a menu bar app: look for its icon in the menu bar (no Dock icon by default).
From there you get Pause, Next, each display's wallpaper, the Library, Settings and About.

Can't see the icon? A crowded menu bar can hide it behind the camera notch, and menu bar
managers such as Bartender hide new items. Either way:
- open Wlprz again from Finder or Spotlight to bring up the Library, which has a
  Settings button in its toolbar;
- turn on **Settings → General → Show Wlprz in the Dock**;
- or allow it to show in your menu bar manager.

See [docs/SPEC.md](docs/SPEC.md) for the full spec and design principles, and
[docs/TRACKER.md](docs/TRACKER.md) for feature status.

## Features
- **Video, image and scene wallpapers.** Five original Metal scenes (Aurora, Nebula Drift,
  Liquid Orbs, Constellation, Dusk Waves) follow the pointer and react to clicks.
- **Library:** search titles and tags, filter by motion and by format (Standard /
  Ultrawide), favourites, sort by date or title.
- **Creator:** import videos or images (button, file picker or drag and drop), trim the
  loop, re-encode to HEVC with a progress bar, tag them.
- **Displays:** mirror one wallpaper everywhere (one shared decode) or choose per display,
  from the library or Settings; turn Wlprz off per display.
- **Playlists:** shuffle, rotate every N minutes, or a time-of-day schedule; "Next" works
  on all of them.
- **Desktop motion:** Animated, or Still to freeze every wallpaper at zero cost.
- **Power policy:** pauses behind full-screen apps, when covered (optional "When exposed"),
  on battery or in Low Power Mode (optional), and while asleep or locked. Throttles scenes
  when warm, under memory pressure or mostly covered. Frees hidden video memory after 30 s.
  The menu bar always says why playback is paused.
- **Performance modes:** Automatic, Maximum, Efficient. Scenes are drawn by Wlprz's own
  Metal pipeline at a reduced internal resolution: a few milliseconds of GPU per frame.
- **Lock Screen match:** keeps the macOS wallpaper set to a still of what's playing, so the
  Lock Screen and the desktop after quitting match.
- **Menu bar** controls, **Shortcuts** actions, launch at login, audio and HDR toggles.

## Requirements and privacy
- macOS 26 or later, Apple silicon.
- Sandboxed. It asks for no permissions: window coverage uses window bounds only (no
  Screen Recording), and the pointer is polled (no Accessibility or Input Monitoring).
- Your library lives in `~/Library/Containers/com.todddube.Wlprz/Data/Library/Application Support/Wlprz`.

## Build
Requires Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and the
Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`). The `.xcodeproj` is generated
from `project.yml` and isn't checked in.

```bash
make build   # generate project + Debug build
make test    # swift-testing suites: policy, rotation, persistence, coverage, engine
make run     # build and launch
make icon    # redraw the app icon
make version              # print version and build
make set-version V=0.5.1   # change the version (project.yml is the single source)
```

The version lives only in `project.yml` (`MARKETING_VERSION`); the build number is the
git commit count.

## Layout
| Folder | Contents |
|---|---|
| `Wlprz/Domain` | Pure value types and rules (`PlaybackPolicy`, `PlaylistRotation`), fully unit-tested |
| `Wlprz/Infrastructure` | Library persistence, import/thumbnail pipeline, power and coverage sampling, wallpaper sync |
| `Wlprz/Engine` | `WallpaperEngine`, desktop windows, shared video sessions, shader scenes |
| `Wlprz/Presentation`, `Wlprz/Intents` | SwiftUI windows and App Intents |
| `docs/` | `SPEC.md` (spec) and `TRACKER.md` (feature status) |

## License
MIT. See [LICENSE](LICENSE).
