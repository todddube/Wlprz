# Wlprz

Live wallpapers for macOS: videos, images and interactive GPU shader scenes on your
desktop, per display, with playlists, schedules and battery-aware playback.

See [docs/SPEC.md](docs/SPEC.md) for the full spec and design principles, and
[docs/TRACKER.md](docs/TRACKER.md) for feature status.

## Features
- **Video, image and scene wallpapers.** Five original Metal scenes (Aurora, Nebula Drift,
  Liquid Orbs, Constellation, Dusk Waves) follow the pointer and react to clicks.
- **Creator:** import videos/images, trim the loop, re-encode to HEVC, tag them.
- **Displays:** mirror one wallpaper everywhere (one shared decode) or pick per display;
  turn Wlprz off per display.
- **Playlists:** shuffle, rotate every N minutes, or a time-of-day schedule.
- **Power policy:** pauses behind full-screen apps, when covered (optional "When exposed"),
  on battery / Low Power Mode (optional), while asleep or locked; throttles scenes when
  warm or mostly covered; frees hidden video memory after 30 s.
- **Performance modes:** Automatic, Maximum, Efficient.
- **Lock Screen match:** keeps the macOS wallpaper set to a still of what's playing.
- **Menu bar** controls, **Shortcuts** actions, launch at login, audio and HDR toggles.

## Build
Requires Xcode 27, XcodeGen and the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`).

```bash
make build   # generate project + Debug build
make test    # swift-testing suites for policy, rotation, persistence, coverage
make run     # build and launch
make icon    # redraw the app icon
```
