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
git clone https://github.com/pranavkarthik10/InputStats.git
cd InputStats

# Build release version
swift build -c release

# Copy binary to app bundle and run
cp .build/release/InputStats InputStats.app/Contents/MacOS/
open InputStats.app
```
