# Moshi - Mobile SSH/Mosh Terminal for iOS

A modern, feature-rich terminal client for iOS with native Mosh support, tmux integration, and an ergonomic macro keyboard designed for developers.

![CI](https://github.com/YOUR_USERNAME/moshi/actions/workflows/ci.yml/badge.svg)

## Features

### Core Connectivity
- **SSH Support** - Full SSH2 protocol implementation with key and password authentication
- **Mosh Integration** - Native Mosh protocol for reliable mobile connections that survive network changes
- **Tailscale Ready** - Works seamlessly over Tailscale VPN for secure remote access

### Session Management
- **Multi-Tab Interface** - Manage multiple connections simultaneously
- **Automatic tmux Integration** - Sessions persist on the server, seamlessly reattach on reconnect
- **Session Restoration** - Automatically reconnect to previous sessions on app launch

### Terminal Emulator
- **Full ANSI/VT100 Support** - Complete terminal emulation with 256-color and true color support
- **Customizable Themes** - Built-in themes including Dracula, Nord, Tokyo Night, Solarized, and more
- **Configurable Fonts** - Choose from popular monospace fonts with adjustable sizes
- **Scrollback Buffer** - 10,000+ lines of scrollback with search functionality

### Macro Keyboard
Ergonomically designed keyboard rows for efficient terminal use:

- **Special Keys** - ESC, Tab, Ctrl+C/D/Z/L, Arrow keys, Function keys
- **Bash/CLI** - Common shell commands, pipes, redirects
- **Git** - Status, diff, add, commit, push, pull, stash operations
- **Claude Code** - Optimized macros for Claude Code workflows (/edit, /add, /context, etc.)
- **Tmux** - Window/pane management, split, zoom, navigation
- **Custom** - Create and save your own macros

### Voice Input
- **Dictation Support** - Type commands using voice input
- **On-device Processing** - Privacy-focused speech recognition when available
- **Voice Commands** - Natural language shortcuts for common operations

### Security
- **Keychain Storage** - Credentials secured with iOS Keychain
- **Biometric Authentication** - Face ID / Touch ID protection for SSH keys
- **Ed25519/RSA/ECDSA Keys** - Generate and manage SSH keys directly in the app
- **No Cloud Sync** - All data stays on your device

## Requirements

- iOS 17.0+
- iPhone or iPad
- Xcode 15.0+ (for building)

## Building

1. Clone the repository:
```bash
git clone https://github.com/YOUR_USERNAME/moshi.git
cd moshi
```

2. Open in Xcode:
```bash
open Moshi.xcodeproj
```

3. Select your development team in Signing & Capabilities

4. Build and run on your device or simulator

## Testing

Run the test suite:
```bash
xcodebuild test \
  -project Moshi.xcodeproj \
  -scheme Moshi \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## Project Structure

```
Moshi/
├── MoshiApp.swift          # App entry point
├── ContentView.swift       # Main navigation
├── Models/                 # Data models
│   ├── Host.swift         # Host configuration
│   ├── Session.swift      # Active session state
│   ├── ConnectionState.swift
│   └── Theme.swift        # Terminal themes
├── Views/                  # SwiftUI views
│   ├── HostListView.swift
│   ├── HostEditView.swift
│   ├── SessionTabView.swift
│   ├── SettingsView.swift
│   └── ...
├── Network/               # Networking layer
│   ├── SSHConnection.swift
│   ├── MoshClient.swift
│   └── NetworkMonitor.swift
├── Terminal/              # Terminal emulation
│   ├── TerminalView.swift
│   ├── TerminalEmulator.swift
│   ├── ANSIParser.swift
│   ├── TerminalRenderer.swift
│   └── MacroKeyboard.swift
├── Managers/              # Business logic
│   ├── SessionManager.swift
│   ├── HostManager.swift
│   ├── KeychainManager.swift
│   ├── MacroManager.swift
│   ├── TmuxIntegration.swift
│   └── DictationManager.swift
└── Utilities/
    ├── Extensions.swift
    └── Logging.swift
```

## Configuration

### Host Settings
- Hostname/IP and port
- Username and authentication method
- Mosh enable/disable with port range
- Auto-attach tmux with custom session names
- Color tags and grouping

### App Settings
- Theme selection
- Font family and size
- Cursor style and blink
- Keyboard preferences
- Security options

## Roadmap

- [ ] SFTP file browser
- [ ] Port forwarding UI
- [ ] Snippet manager
- [ ] Sync via iCloud (optional)
- [ ] Widget for quick connect
- [ ] Keyboard shortcuts (iPad)
- [ ] Split view support (iPad)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [Termius](https://termius.com/), [Blink Shell](https://blink.sh/), and [Prompt](https://panic.com/prompt/)
- Terminal themes adapted from popular color schemes
- Built with SwiftUI and modern iOS APIs
