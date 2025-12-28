# InputStats

A minimal macOS menubar app that tracks your daily keyboard and mouse activity with iCloud sync across devices.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Live counter** in menubar with customizable display (keystrokes, words, clicks, or distance)
- **Tracks all input**: Keystrokes, words, mouse clicks, mouse scrolls, mouse travel distance
- **Daily statistics**: Today, Yesterday, 7-day avg, 30-day avg, Record
- **History window** with visual bar charts for all metrics
- **iCloud sync** across all your Macs using CRDT (Conflict-free Replicated Data Types)
- **Configurable settings**: Mouse DPI for accurate distance calculation, distance format options
- **Start at Login** option
- **No Xcode required** - builds with Swift Package Manager
- **Privacy-focused** - all data stays in your iCloud, no third-party servers

## Installation

### Manual Download

1. Download latest `.zip` from [Releases](../../releases) page
2. Unzip and drag `InputStats.app` to your Applications folder
3. **First launch**: Right-click app → "Open" (required to bypass Gatekeeper since app is not signed)
4. Grant Accessibility permission when prompted

### Build from Source

Requirements:
- macOS 13+
- Swift 5.9+

```bash
# Clone repository
git clone https://github.com/yourusername/InputStats.git
cd InputStats

# Build release version
swift build -c release

# Copy binary to app bundle and run
cp .build/release/InputStats InputStats.app/Contents/MacOS/
open InputStats.app
```

## How It Works

### Keystroke & Mouse Monitoring

Uses `CGEventTap` to listen for keyboard and mouse events system-wide. This requires **Accessibility permission** which you'll be prompted to grant on first launch.

### Word Counting

Counts words by detecting when you start typing a new word (transition from space/enter to a letter). Accurate for normal typing.

### Mouse Distance

Calculates mouse travel distance by tracking pixel movement between events. DPI setting allows accurate conversion to real-world units.

### CRDT Sync

Each device maintains a G-Counter (Grow-only Counter) for each metric. When syncing via iCloud:

```
Device A: {A: 100, B: 50}
Device B: {A: 80, B: 70}
Merged:   {A: 100, B: 70}  // max() of each device's count
```

This ensures counts always converge correctly regardless of sync order or timing - no conflicts possible!

### Data Storage

- **Local**: `~/Library/Application Support/TypingStats/`
- **iCloud**: `NSUbiquitousKeyValueStore` (automatic, up to 1MB)

## Project Structure

```
Sources/TypingStats/
├── TypingStatsApp.swift      # App entry point & menu
├── Core/
│   ├── KeystrokeMonitor.swift    # CGEventTap wrapper for keyboard
│   ├── MouseMonitor.swift        # CGEventTap wrapper for mouse
│   ├── PermissionManager.swift   # Accessibility permissions
│   └── StatusItemManager.swift   # Menubar icon + count
├── Data/
│   ├── AppSettings.swift         # User preferences
│   ├── GCounter.swift            # CRDT implementation
│   ├── DailyStats.swift          # Daily record model
│   ├── DeviceID.swift            # Hardware UUID
│   ├── LocalStore.swift          # JSON persistence
│   ├── iCloudSync.swift          # iCloud key-value store
│   └── StatsRepository.swift     # Data coordinator
└── UI/
    ├── HistoryWindow.swift       # History view
    └── SettingsWindow.swift     # Settings view
```

## Privacy

InputStats:
- Only counts input events, never records what you type or click
- Stores data locally and in your personal iCloud
- Has no analytics, telemetry, or network calls (except iCloud sync)
- Is fully open source for you to audit

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Multi.app](https://multi.app/blog/pushing-the-limits-nsstatusitem) for NSStatusItem + NSHostingView technique
