# CLAUDE.md

**Wlprz** is a native macOS (26+, Apple silicon, sandboxed) live-wallpaper menu bar app.
The spec is `docs/SPEC.md` and feature status is `docs/TRACKER.md`. Keep both current.

## Commands
`make build` · `make test` · `make run` · `make icon`. The .xcodeproj is generated from
`project.yml`, so never hand-edit it.

## Layout
- `Domain/`: pure, `nonisolated`, Foundation-only, fully unit-tested. `PlaybackPolicy` holds
  every play/pause/fps rule. Change rules there and in its tests, not in the engine.
- `Infrastructure/`: persistence (`LibraryStore`, one JSON doc in Application Support),
  import/thumbnail pipeline, power/coverage sampling, system wallpaper sync.
- `Engine/`: `WallpaperEngine` reconciles displays → desktop windows and shared
  `VideoSession`s, ticks every 2 s, applies the policy. Scenes are `[[stitchable]]` shaders in
  `Scenes.metal` used via SwiftUI `colorEffect`.
- `Presentation/`, `Intents/`: SwiftUI UI and App Intents (via `AppModel.shared`).

## Invariants
- Default actor isolation is MainActor. Domain types are explicitly `nonisolated`.
- A wallpaper shown on several displays is ONE session; it pauses only when all are hidden.
- Built-in scene ids are fixed UUIDs (`BuiltInScenes`) and must never change.
- No private APIs. There is no live Lock Screen; we sync a still via `NSWorkspace.setDesktopImageURL`.
