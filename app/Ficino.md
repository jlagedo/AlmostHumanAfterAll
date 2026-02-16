# Ficino

A macOS menu bar app that listens to Apple Music and delivers Claude-powered commentary on every track you play.

## Architecture

```
┌──────────────────────────────────────────┐
│  Menu Bar Agent (Swift)                  │
│                                          │
│  DistributedNotificationCenter           │
│  "com.apple.Music.playerInfo"            │
│         ↓                                │
│  Parse artist, track, album, artwork     │
│         ↓                                │
│  Process("claude", ["-p", prompt])       │
│         ↓                                │
│  UNUserNotificationCenter                │
│  with album art + Claude's comment       │
└──────────────────────────────────────────┘
```

## Components

### 1. Track Listener

`DistributedNotificationCenter` subscribes to `com.apple.Music.playerInfo`. Fires on every track change with metadata: artist, track name, album, duration, play state.

### 2. Claude Backend

Shells out to `claude -p` — no API key needed, runs on Claude Code subscription. The system prompt sets the personality.

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
process.arguments = ["-p", "--system-prompt", personality, prompt]
```

### 3. Notifications

`UNUserNotificationCenter` with album artwork (via MusicKit or notification payload). The comment appears as a native macOS notification.

### 4. Menu Bar

Persistent menu bar icon with:
- Current track + last comment
- Comment history (scrollable)
- Personality selector (snarky critic, Daft Punk robot, Brazilian tio, hype man)
- Pause/resume toggle
- Skip threshold (ignore tracks played < N seconds)

## Personalities

System prompts that define Claude's commentary style:

| Personality | Vibe |
|---|---|
| Snarky Critic | Pitchfork reviewer who rates everything 6.8 |
| Daft Punk Robot | Only speaks using words from Daft Punk lyrics |
| Brazilian Tio | Only knows MPB, judges everything else |
| Hype Man | Unreasonably excited about every single track |
| Vinyl Snob | Insists the original pressing sounded better |

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (menu bar popover)
- **Track detection:** DistributedNotificationCenter
- **LLM:** Claude Code CLI (`claude -p`)
- **Notifications:** UserNotifications framework
- **Album art:** MusicKit (optional, for richer notifications)
- **Distribution:** Swift Package Manager (command-line) or Xcode project (.app)

## Token Economics

Zero API cost. Claude Code subscription covers all calls. The only resource burned is Claude's patience as you loop the same album for the third time.

*"Third time on Discovery today. We get it, you're nostalgic."*
