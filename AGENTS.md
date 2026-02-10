# AlmostHumanAfterAll

macOS menu bar app that listens to Apple Music track changes and delivers Claude-powered commentary via floating notifications.

## Build & Run

**Do NOT run `build.sh`** — building and launching is the human's job. Never call `./build.sh` or trigger builds.

```bash
./build.sh          # builds + runs with logs in terminal (Ctrl+C to quit)
```

Binary output: `./build/Build/Products/Debug/AlmostHumanAfterAll.app`

## Architecture

```
Apple Music → DistributedNotificationCenter → MusicListener → AppState → ClaudeService → FloatingNotification
                                                                  ↓
                                                           ArtworkService (AppleScript)
```

**Single persistent Claude process** using `--input-format stream-json` / `--output-format stream-json`. Process stays alive across tracks, maintaining conversation context. Uses Haiku for speed/cost.

## Project Structure

```
AlmostHumanAfterAll/
├── AlmostHumanAfterAllApp.swift    # @main, MenuBarExtra scene, auto-starts services
├── Info.plist                      # LSUIElement=YES (no Dock icon), AppleEvents description
├── AlmostHumanAfterAll.entitlements # Sandbox OFF
├── Assets.xcassets/
├── Models/
│   ├── TrackInfo.swift             # Parsed from DistributedNotification userInfo
│   ├── CommentEntry.swift          # History entry (track + comment + personality + artwork)
│   ├── Personality.swift           # 6 personalities with system prompts + allowedTools
│   └── AppState.swift              # @MainActor coordinator, connects all services
├── Services/
│   ├── MusicListener.swift         # Subscribes to com.apple.Music.playerInfo
│   ├── ClaudeService.swift         # Actor, persistent stream-json process to claude CLI
│   ├── ArtworkService.swift        # NSAppleScript to get album artwork from Music.app
│   └── NotificationService.swift   # Floating NSPanel + SwiftUI notification view
└── Views/
    ├── MenuBarView.swift           # Main popover layout
    ├── NowPlayingView.swift        # Current track + artwork + comment
    ├── HistoryView.swift           # Scrollable comment history
    ├── PersonalityPickerView.swift # Personality selector
    └── SettingsView.swift          # Pause, skip threshold, notification duration
```

## Key Design Decisions

- **No sandbox** — required for Process spawning, AppleScript, DistributedNotificationCenter
- **No external dependencies** — pure Swift/SwiftUI/AppKit
- **Persistent Claude process** — stream-json keeps one `claude` process alive, avoids cold start per track
- **Haiku model** — fast + cheap, sufficient for 2-3 sentence music commentary
- **Floating NSPanel** — custom notification window instead of UNUserNotificationCenter (configurable duration, better design, no Focus mode issues)
- **`--system-prompt` override** — prevents Claude Code's default coding assistant prompt from interfering with music commentary
- **AppleScript for artwork** — DistributedNotification doesn't include artwork data

## Logging

All services log with `NSLog` using bracketed prefixes. Run the binary directly to see output:

- `[MusicListener]` — track notifications from Apple Music
- `[AppState]` — track acceptance/rejection, task coordination
- `[Claude]` — process lifecycle, stream events, results
- `[Artwork]` — AppleScript artwork fetching
- `[Notification]` — floating window show/dismiss

## Personalities

| Personality | Icon | Vibe |
|---|---|---|
| Snarky Critic | `pencil.and.scribble` | Pitchfork reviewer, rates everything 6.8 |
| Daft Punk Robot | `cpu` | Only speaks using Daft Punk lyrics |
| Brazilian Tio | `sun.max.fill` | Only knows MPB, judges everything else |
| Hype Man | `flame.fill` | Unreasonably excited about every track |
| Vinyl Snob | `opticaldisc.fill` | Insists the original pressing sounded better |
| Claudy | `book.fill` | Warm music historian, uses WebSearch for real facts |

## Claude CLI Flags

```
claude -p
  --input-format stream-json      # NDJSON on stdin, keeps process alive
  --output-format stream-json     # NDJSON responses on stdout
  --verbose                       # required for stream-json output with -p
  --model claude-haiku-4-5-20251001
  --tools "WebSearch"             # makes WebSearch available
  --allowedTools "WebSearch"       # auto-approves it (both flags required in -p mode)
  --system-prompt "..."           # overrides default coding assistant prompt
```

Stream-json message format (input):
```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
```

Stream-json result format (output):
```json
{"type":"result","subtype":"success","result":"commentary text","session_id":"..."}
```
