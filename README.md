# AlmostHumanAfterAll

A macOS menu bar app that listens to Apple Music and delivers Claude-powered commentary on every track you play.

## What it does

When a song starts playing in Apple Music, AlmostHumanAfterAll catches the track change, sends the metadata to Claude via the CLI, and pops a native macOS notification with Claude's take on the song.

## Personalities

Pick a vibe from the menu bar:

| Personality | Vibe |
|---|---|
| Snarky Critic | Pitchfork reviewer who rates everything 6.8 |
| Daft Punk Robot | Only speaks using words from Daft Punk lyrics |
| Brazilian Tio | Only knows MPB, judges everything else |
| Hype Man | Unreasonably excited about every single track |
| Vinyl Snob | Insists the original pressing sounded better |

## Tech Stack

- **Swift / SwiftUI** — menu bar popover UI
- **DistributedNotificationCenter** — catches `com.apple.Music.playerInfo` events
- **Claude Code CLI** (`claude -p`) — no API key needed, runs on your Claude Code subscription
- **UserNotifications** — native macOS notifications with album art

## Building

Open `AlmostHumanAfterAll.xcodeproj` in Xcode and build, or run:

```sh
./build.sh
```

## Requirements

- macOS 14+
- [Claude Code CLI](https://claude.ai/claude-code) installed at `/usr/local/bin/claude`
- Apple Music

## Token Economics

Zero API cost. Claude Code subscription covers all calls. The only resource burned is Claude's patience as you loop the same album for the third time.

*"Third time on Discovery today. We get it, you're nostalgic."*
