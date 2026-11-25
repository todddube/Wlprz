# Wlprz — Feature Tracker

Audit of `docs/SPEC.md` against the code. Last updated 2026-11-25.
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
| 2.1 | Video wallpapers (looping, aspect fill) | ✅ | HEVC test clip seen looping on the desktop |
| 2.1 | Image wallpapers | ✅ | 2560×1080 test image seen aspect-filled on the desktop |
| 2.1 | Motion, energy, aspect ratio / format | ✅ | Format rules and image measurement tested |
| 2.2 | Library: sidebar, grid, search, motion + format filters, sort | 🟡 | Built; UI not exercised. **W13** |
| 2.2 | Grid scenes animate live (on hover) | 🟡 | **W13** |
| 2.2 | Inspector (incl. format) | 🟡 | **W13** |
| 2.2 | Import via toolbar, fileImporter, drag and drop | 🟡 | **W13** |
| 2.3 | Creator: title, tags, trim, HEVC optimise, keep audio, % progress | 🟡 | **W13** |
| 2.4 | Mirror vs per-display, per-display enable | ✅ | Engine tests; mirror seen on 2 real displays |
| 2.4 | Settings: mirror / per-display source pickers | 🟡 | **W13** |
| 2.4 | Stable display ids, rebuild on screen change | 🟡 | |
| 2.5 | Playlists: order, shuffle, interval, schedule | ✅ | Domain + engine tests; editor UI **W13** |
| 2.5 | "Next" (library, playlist, scheduled override) | ✅ | Engine tests |
| 2.6 | Policy rules (pause/fps/resolution, Still, memory) | ✅ | 13 policy tests |
| 2.6 | Shared session pauses only when every display is hidden | ✅ | Engine test |
| 2.6 | Coverage sampling | ✅ | Grid and CG↔AppKit flip tested |
| 2.6 | Unload hidden video after 30 s, reload on reveal, never on user pause | ✅ | Engine tests |
| 2.7 | Menu bar extra (+ version, About item, paused icon) | ✅ | Built; icon may be hidden by Bartender/notch on crowded menu bars |
| 2.7 | Reopen opens Library; Library Settings button; Show in Dock option | ✅ | Reopen and Settings button verified via accessibility |
| 2.7 | About window + Settings About tab (version 0.5.0, build, GitHub/README/Issues links) | ✅ | Info.plist values verified in the built app |
| — | Standardised versioning (`make version` / `set-version`, build = commit count) | ✅ | |
| 2.7 | Sync macOS wallpaper (still) | ✅ | Video and image on 2 displays; shared still; old copies cleaned. Can't restore an Aerial (SPEC §2.7) |
| 2.7 | Launch at login | 🟡 | Usually needs the app in /Applications |
| 2.7 | Audio (mute, volume, one display only) | 🟡 | **W13** |
| 2.7 | HDR toggle | 🟡 | |
| 2.7 | App Intents / Shortcuts | ➖ | Built; Shortcuts.app testing dropped by request |
| 2.8 | Settings tabs | 🟡 | **W13** |
| 2.1 | Scene GPU budget (own Metal pipeline, per-scene render detail) | ✅ | 90 % → 29 % system GPU, 614 → 108 MB; see SPEC §2.1 |
| extra | Desktop motion: Still | ✅ | Policy + engine tests (reloads an unloaded video) |
| extra | Community catalogue, Discover, accounts, licensing | ➖ | |
| extra | Live animated Lock Screen | ➖ | No public API; still-frame sync instead |
| — | Source control | ✅ | github.com/todddube/Wlprz (private) |

## 2. Work plan

Priority: P1 = spec gap or unverified core path, P2 = parity / polish, P3 = nice to have.

| ID | P | Work item | Status |
|---|---|---|---|
| W1 | P1 | End-to-end: video and image playback, macOS wallpaper sync on 2 displays | ☑ |
| W2 | P1 | Settings → Displays: mirror-source and per-display source pickers | ☑ |
| W3 | P1 | Creator: determinate export progress | ☑ |
| W4 | P1 | Memory pressure in the policy | ☑ |
| W5 | P1 | Domain tests: coverage flip, slot boundaries, memory/Still policy | ☑ |
| W6 | P2 | "Next" on a scheduled playlist | ☑ |
| W7 | P2 | Desktop motion: Animated / Still | ☑ |
| W8 | P3 | Spec text: grid scenes animate on hover | ☑ |
| W9 | — | Run each App Intent from Shortcuts.app | dropped |
| W10 | P3 | Aspect ratio on import + backfill; Standard / Ultrawide filter | ☑ |
| W11 | P3 | git init + push | ☑ |
| W12 | P2 | Engine tests via `EngineDependencies` (11 tests) | ☑ |
| W13 | P2 | Manual UI pass: Library (filters, drag-drop import), Inspector, Creator with progress, Playlist editor, Settings pickers, audio | ☐ |
