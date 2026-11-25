# Wlprz — project Swift standards

Overrides and extends `~/.claude/swift-standards.md`. Where they disagree, this file wins.

Last verified against upstream references: 2026-11-25

## Platform baseline

| Item | Value |
|---|---|
| Project | XcodeGen (`project.yml`); `Wlprz.xcodeproj` is generated, never hand-edited |
| Toolchain | Xcode 27 / Apple Swift 6.4.2 |
| Language mode | Swift 6 (`SWIFT_VERSION 6.0`), strict concurrency complete |
| Default isolation | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
| Approachable concurrency | YES (enables `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`) |
| Upcoming features | `ExistentialAny` |
| Deployment target | macOS 26.0, arm64 only |
| Sandbox | App Sandbox + `files.user-selected.read-only`; hardened runtime |
| App type | `LSUIElement` menu bar app |
| Tests | swift-testing, `WlprzTests` hosted in the app |
| Commands | `make build`, `make test` (DerivedData outside the iCloud-synced repo) |

## Header target labels

| Path | Line 3 |
|---|---|
| `Wlprz/**` (Swift and `.metal`) | `Wlprz · Wlprz` |
| `WlprzTests/**` | `WlprzTests · Wlprz` |
| `Scripts/*.swift` | `Scripts · Wlprz` (shebang above header) |

## Project conventions (observed; do not flag)

- Global header format is followed exactly, including in `Scenes.metal`.
- Default isolation is MainActor; `Domain/` types and pure helpers opt out with `nonisolated`.
  Domain imports Foundation only.
- `@Observable` final classes for app state (`AppModel`, `LibraryStore`, `WallpaperEngine`,
  `SceneRenderState`); framework objects excluded with `@ObservationIgnored`.
- `AppModel.shared` singleton is deliberate (App Intents need a route back to the engine).
- `// MARK: - Section` in multi-concern files; `try?` always carries a trailing `//` reason.
- Logging via `os.Logger`, subsystem `com.todddube.Wlprz`, one category per type.
- `@preconcurrency import AVFoundation` is accepted for AVFoundation types.

## Project rules

- With `NonisolatedNonsendingByDefault` on, a `nonisolated async` function runs on the
  caller's actor. Anything meant to leave the main actor (file copies, ImageIO, encoding)
  must be `@concurrent`.
- Do not run `make release` or `make run` during review.

Changes:
- 2026-11-25 — Created by swift-code-reviewer from project.yml, Makefile and source survey.
