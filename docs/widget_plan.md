# Plan: Add WidgetKit Widget to Ficino

## Context

Ficino currently shows music commentary via its menu bar popover and a floating NSPanel notification. Adding a macOS desktop/Notification Center widget gives a persistent, glanceable view of the latest commentary without opening anything.

The widget is display-only — the main app writes the latest commentary to a shared `UserDefaults` (via App Group), then tells WidgetKit to reload. The widget reads that data and renders it. No AI generation or MusicKit access happens in the widget extension.

## Approach

**Data sharing:** Shared `UserDefaults` via App Group (Team ID prefix format). The main app writes a small JSON-encoded struct after each commentary generation; the widget reads it in `getTimeline()`.

**Widget sizes:** `.systemSmall` (artwork + track + truncated commentary) and `.systemMedium` (artwork + track + fuller commentary).

**Reload policy:** `.never` — widget only updates when explicitly triggered by `WidgetCenter.shared.reloadTimelines(ofKind:)`.

**No shared Swift package** for the data model — the struct is ~6 fields, duplicated in both targets to avoid pulling FicinoCore's dependency chain into the widget.

---

## Manual Xcode Steps (before code changes)

These require the Xcode GUI since they modify the project file:

1. **Add App Group to Ficino target** — Signing & Capabilities → + App Groups → add group identifier (format: `<TeamID>.com.jlagedo.ficino.shared`)
2. **Create Widget Extension target** — File → New → Target → Widget Extension, name: `FicinoWidget`, uncheck "Include Configuration App Intent"
3. **Add App Group to FicinoWidget target** — same group identifier as step 1
4. **Set FicinoWidget deployment target** to macOS 26.0
5. **Delete Xcode-generated template files** in `app/FicinoWidget/` — we'll replace them

---

## Code Changes

### New files (4 widget extension files + 1 main app file)

**`app/Ficino/Services/WidgetDataWriter.swift`** (main app target)
- `WidgetData` struct (Codable): trackName, artist, album, commentary, timestamp, thumbnailData
- `WidgetDataWriter` enum with static `write(...)` method:
  - Encodes `WidgetData` to JSON
  - Writes to `UserDefaults(suiteName: appGroupID)`
  - Calls `WidgetCenter.shared.reloadTimelines(ofKind:)`

**`app/FicinoWidget/WidgetData.swift`** (widget target)
- Duplicate of the `WidgetData` struct + `SharedConstants` enum (app group ID, UserDefaults key, widget kind string)

**`app/FicinoWidget/FicinoTimelineProvider.swift`** (widget target)
- `CommentaryEntry: TimelineEntry` with `date` + optional `WidgetData`
- `FicinoTimelineProvider: TimelineProvider` — reads from shared UserDefaults, returns `.never` policy timeline

**`app/FicinoWidget/FicinoWidgetViews.swift`** (widget target)
- `SmallWidgetView`: 36×36 thumbnail + track name/artist + 3-line commentary preview
- `MediumWidgetView`: 56×56 thumbnail + track/artist/album + 4-line commentary
- Empty state: "Play something in Apple Music" with music note icon
- Thumbnail helper using `NSImage(data:)`

**`app/FicinoWidget/FicinoWidget.swift`** (widget target)
- `@main` entry point with `StaticConfiguration`
- `FicinoWidgetEntryView` that switches on `@Environment(\.widgetFamily)`
- Supported families: `.systemSmall`, `.systemMedium`

### Edited files

**`app/Ficino/Services/MusicCoordinator.swift`**

Add `WidgetDataWriter.write(...)` in `MusicCoordinator` after the thumbnail update in the track change handler:

```swift
// After thumbnail update, write to widget
WidgetDataWriter.write(
    trackName: track.name, artist: track.artist,
    album: track.album, commentary: result.commentary,
    thumbnailData: thumbnailData
)
```

---

## Verification

1. Complete the manual Xcode steps above
2. Build the main Ficino scheme — should compile with `WidgetDataWriter` included
3. Build the FicinoWidget scheme — should compile as a standalone extension
4. Run Ficino, play a track → commentary generates → check that the widget (added via desktop "Edit Widgets") updates with the track and commentary
