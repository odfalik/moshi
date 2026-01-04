# Moshi Roadmap

## Planned Features

### Session Handoff via QR Code
**Priority:** High

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
