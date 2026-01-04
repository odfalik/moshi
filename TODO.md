# Moshi - TODO & Roadmap

## Known Limitations

### SSH Implementation
- [x] ~~Custom SSH implementation doesn't work~~ - Replaced with Citadel library
- [ ] SSH agent forwarding not supported on iOS
- [ ] Host key verification just accepts all keys (security risk)

### Mosh Support
- [ ] **Mosh is not implemented** - Would require either:
  - Compiling `mosh-client` for iOS (complex, see [BlinkShell's approach](https://github.com/blinksh/blink))
  - Implementing the Mosh/SSP UDP protocol from scratch
- [ ] For now, use plain SSH with keepalives as a workaround

### Tmux Integration
- [ ] No automatic tmux session management
- [ ] No session listing UI
- [ ] No support for attaching to existing tmux sessions automatically
- [ ] auto-install
- [ ] do we want to do anything with tmux control mode?

### Terminal Emulation
- [ ] Terminal emulator is basic - may have issues with complex TUIs
- [ ] No sixel/image support
- [ ] No true color (24-bit) support yet
- [ ] text selection, copy/paste

### Authentication
- [ ] SSH agent not available on iOS
- [~] No support for hardware keys (YubiKey, etc.) - not a priority

### Platform
- [ ] iOS only - no macOS Catalyst support currently
- [~] PTY shell requires iOS 18.0+ (fallback mode for iOS 17) - this is a non-issue

### Settings
- [ ] font settings, color theme
- [ ] fully customizable "macro sets" and "macros"

---

## Roadmap

### High Priority

#### Session Handoff via QR Code
Enable seamless handoff of active terminal or Claude Code sessions from desktop to phone (and vice versa).

**Concept:**
- Generate a QR code on the source device containing encrypted session credentials
- Scan with Moshi app on target device to instantly connect to the same session
- For tmux sessions: automatically attach to the existing tmux session
- For Mosh: transfer the Mosh session key securely
- Consider: could also work for handing off from phone back to desktop

**Use cases:**
- Start working on desktop, continue on phone while mobile
- Quick "grab and go" when leaving desk
- Share session access temporarily with another device

**Technical considerations:**
- QR payload encryption (use device-to-device key exchange or time-limited tokens)
- tmux session naming conventions for easy reattachment
- Mosh session migration limitations
- Potential integration with Universal Clipboard / Handoff APIs on Apple platforms

### Medium Priority

- [ ] Import OpenSSH config (~/.ssh/config)
- [ ] iCloud sync for hosts
- [ ] Shortcuts/Siri integration
- [ ] Split view for multiple sessions
- [ ] Local port forwarding UI
- [ ] SFTP file browser
- [ ] Proper host key verification and storage

### Future Enhancements

- [ ] RSA key support (currently only Ed25519)
- [ ] Certificate-based authentication
- [ ] Jump host / ProxyJump support
- [ ] Connection profiles with different settings

---

## Dependencies

| Package | Purpose | URL |
|---------|---------|-----|
| Citadel | SSH client | https://github.com/orlandos-nl/Citadel |
| SwiftNIO | Async networking | https://github.com/apple/swift-nio |
| NIOSSH | SSH protocol | https://github.com/apple/swift-nio-ssh |
