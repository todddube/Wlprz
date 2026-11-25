# Wlprz — Feature Tracker

Audit of `docs/SPEC.md` against the code, 2026-11-25.
Update this file as items move. Status key:

- ✅ **Done**: implemented and verified (unit test, or seen working in the running app)
- 🟡 **Built, unverified**: code exists and compiles, but nobody has seen it work end to end
- ❌ **Missing**: in the spec, not in the code
- ➖ **Out of scope**: deliberate non-goal (SPEC §2.9)

## 1. Spec coverage

| § | Feature | Status | Notes |
|---|---|---|---|
| 2.1 | Scene wallpapers (5 original shaders) | ✅ | Aurora seen on the desktop |
| 2.1 | Scenes follow pointer / click ripple | 🟡 | Code path exists; not visually checked |
| 2.1 | Video wallpapers (looping, aspect fill) | ✅ | HEVC 1080p test clip seen playing on the desktop (frame counter advancing) |
| 2.1 | Image wallpapers | 🟡 | **W1** |
| 2.1 | Motion + energy classes | ✅ | |
| 2.2 | Library: sidebar, grid, search, motion filter, sort | 🟡 | Built; UI not exercised |
| 2.2 | Grid scenes render live at low fps | 🟡 | Animates on hover only (cheaper); spec text to match. **W8** |
| 2.2 | Inspector: preview, title/tags, favourite, set (all / one display), add to playlist, reveal, delete | 🟡 | |
| 2.2 | Import via toolbar, fileImporter, drag and drop | 🟡 | **W1** |
| 2.3 | Creator: title, tags, trim, HEVC optimise, keep audio | 🟡 | **W1** |
| 2.3 | Creator: export **progress** shown | 🟡 | Percentage bar from `AVAssetExportSession.states`; not yet seen in the UI |
| 2.4 | Mirror vs per-display, per-display enable | 🟡 | Single display here; multi-display untested |
| 2.4 | Settings: pick **mirror source / per-display source** | 🟡 | `SourcePicker` in Displays tab |
| 2.4 | Stable display ids, rebuild on screen change | 🟡 | |
| 2.5 | Playlists: order, shuffle, interval, schedule | ✅ (domain) / 🟡 (UI) | Rotation logic tested; engine cursors untested. **W5** |
| 2.5 | "Next" with a *scheduled* playlist | 🟡 | Overrides until the next slot; `nextSlotStart` unit-tested |
| 2.6 | Policy rules (pause/fps/resolution) | ✅ | 11 unit tests |
| 2.6 | Memory pressure → cap scenes 30 fps / pause scenes at critical | ✅ | Policy tested; DispatchSource feeds it |
| 2.6 | Coverage sampling | ✅ | Grid and CG↔AppKit flip tested |
| 2.6 | Unload hidden video after 30 s | 🟡 | **W5** |
| 2.7 | Menu bar extra | ✅ | Seen running |
| 2.7 | Sync macOS wallpaper (still) | 🟡 | Needs a video/image wallpaper. **W1** |
| 2.7 | Launch at login | 🟡 | Usually needs the app in /Applications |
| 2.7 | Audio (mute, volume, one display only) | 🟡 | **W1** |
| 2.7 | HDR toggle | 🟡 | |
| 2.7 | App Intents / Shortcuts | 🟡 | Not run from Shortcuts.app. **W9** |
| 2.8 | Settings tabs | 🟡 | Source pickers and Desktop motion added |
| extra | Desktop Motion: **Still** (show a frozen frame, zero cost) | ✅ (policy) / 🟡 (UI) | Playback → Motion |
| extra | Format filter (Standard / Ultrawide) | ❌ | Low value for a personal library. **W10** |
| extra | Community catalogue, Discover, accounts, licensing | ➖ | |
| extra | Live animated Lock Screen | ➖ | No public API; still-frame sync instead |
| — | Engine unit tests (cursors, next, mirror transitions) | ❌ | Needs `DisplayInfo` injection into the engine. **W12** |
| — | Source control | ❌ | Not a git repo. **W11** (needs your go-ahead) |

## 2. Work plan

Priority: P1 = spec gap or unverified core path, P2 = parity / polish, P3 = nice to have.

| ID | P | Work item | Status |
|---|---|---|---|
| W1 | P1 | End-to-end smoke test: video playback ☑. Still to do: import through the UI, image, still sync (changes your real wallpaper, so needs your OK), audio | ◐ |
| W2 | P1 | Settings → Displays: mirror-source picker and per-display source picker (wallpaper or playlist) | ☑ |
| W3 | P1 | Creator: determinate export progress (`AVAssetExportSession.states`) | ☑ |
| W4 | P1 | Memory pressure in `SystemConditions` + policy (warning → 30 fps scenes, critical → pause scenes) + tests; spec §2.6 | ☑ |
| W5 | P1 | Tests: coverage CG↔AppKit flip, slot boundaries, memory/Still policy (30 tests now) | ☑ |
| W6 | P2 | "Next" on a scheduled playlist: jump to the next slot's wallpaper | ☑ |
| W7 | P2 | Desktop motion setting: Animated / Still (policy pauses with reason `.motionOff`, no unload) | ☑ |
| W8 | P3 | Spec text: grid scenes animate on hover | ☑ |
| W9 | P2 | Run each App Intent from Shortcuts.app | ☐ |
| W10 | P3 | Store pixel size on import; Standard / Ultrawide filter | ☐ |
| W11 | P3 | `git init` + first commit (only when asked) | ☐ |
| W12 | P2 | Engine tests: inject displays + temp `LibraryStore`; cover cursors, Next, mirror→per-display, unload timing | ☐ |
| W13 | P2 | Manual UI pass: Library, Inspector, Creator (with progress), Playlist editor, Settings source pickers | ☐ |
