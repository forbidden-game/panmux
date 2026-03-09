<p align="center">
  <img src="images/icons/icon_128.png" alt="panmux icon" width="128" />
</p>

<h1 align="center">panmux</h1>

<p align="center">
  <strong>🚀 The terminal built for coding agents</strong>
</p>

<p align="center">
  A Ghostty fork that adds the control layer agent-heavy workflows actually need
</p>

<p align="center">
  <a href="./README.md"><strong>English</strong></a>
  ·
  <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Linux%20%2F%20Wayland-1f6feb" />
  <img alt="ui" src="https://img.shields.io/badge/frontend-GTK4-2da44e" />
  <img alt="base" src="https://img.shields.io/badge/base-Ghostty-f59e0b" />
  <img alt="status" src="https://img.shields.io/badge/status-active%20prototype-dc2626" />
  <img alt="license" src="https://img.shields.io/badge/license-MIT-6f42c1" />
</p>

---

## 💡 Why panmux?

When you live in terminal-based coding agents like **Codex** or **pi**, the hard part isn't emulation—it's **coordination**:

- 🤔 Which tab is busy right now?
- ✅ Which session already finished?
- 📁 Which working directory does this tab belong to?
- 🔔 How do external tools signal useful state without screen scraping?

**panmux** answers these questions with a workflow-oriented UI and a small control plane, while standing on Ghostty's blazing-fast terminal foundation.

> **Core Philosophy:** Keep Ghostty's fast terminal core. Add the control layer that agent-heavy terminal work actually needs.

---

## ✨ Key Features

### 🎯 Agent-First Design

Built from the ground up for coding agent workflows:

- **📊 Vertical Sidebar** — See all your sessions at a glance, not hidden in tabs
- **📂 Live Working Directory** — Know where each session is operating
- **⚡ Status Management** — External tools can mark tabs as `running`, `info`, `error`, or `done`
- **🔔 Smart Notifications** — Desktop notifications mapped back into sidebar status

### ⌨️ Keyboard-Driven

- **Alt+1..9** — Instant tab switching with visible shortcuts
- **No mouse required** — Navigate your entire workflow from the keyboard

### 🔌 Powerful Control Plane

- **Unix Socket API** — JSON-line protocol for external tool integration
- **Multi-Instance Isolation** — Each window has its own control socket
- **Environment Variables** — `PANMUX_INSTANCE_ID`, `PANMUX_SOCKET_PATH`, `PANMUX_TAB_ID`, `PANMUX_SURFACE_ID`
- **CLI Tool** — `panmuxctl` for scripting and automation

### 🎨 Modern Stack

- **Zig + GTK4** — Native performance with modern UI
- **Ghostty Core** — Industry-leading terminal emulation
- **Wayland Native** — First-class Linux desktop integration

---

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/ghostty-panmux.git
cd ghostty-panmux

# Install locally (recommended for development)
./scripts/install_local_panmux.sh
```

This installs to `~/.local/opt/panmux/` and creates:
- `~/.local/bin/panmux` — Main terminal
- `~/.local/bin/panmuxctl` — Control CLI
- `~/.local/share/applications/panmux.desktop` — Desktop launcher

### Basic Usage

```bash
# Launch panmux
panmux

# In any tab, control the current session
panmuxctl notify --title "Build" --body "Complete" --state done
panmuxctl set-status --state running --title "Testing"
panmuxctl clear-status

# Switch tabs
panmuxctl focus-tab --tab 2

# List all tabs
panmuxctl list-tabs
```

---

## 🎮 What's Different from Ghostty?

panmux **does not** replace Ghostty's renderer, PTY model, or terminal engine.

It adds a focused set of enhancements:

| Component | Change |
|-----------|--------|
| **Window Shell** | Reworked GTK window with vertical sidebar |
| **Tab UI** | Left sidebar replaces top tab bar |
| **Working Directory** | Visible in sidebar, sourced from Ghostty's pwd signal |
| **Control Plane** | Per-window Unix socket with JSON-line protocol |
| **Environment** | Injects `PANMUX_*` variables into shell children |
| **Notifications** | Desktop notifications mapped to tab status |

**In one line:** Ghostty remains the terminal; panmux adds agent-oriented window control and status UX on top.

---

## 🔗 Codex Integration

panmux integrates with Codex **without modifying Codex source code**.

### Current Integration Points

1. **Notification Bridge** — `scripts/panmux_codex_notify.py` bridges Codex notify payloads
2. **Shell Detection** — Interactive `codex` commands auto-mark tabs as `running`
3. **Wrapper Fallback** — `scripts/panmux_codex_wrapper.sh` for explicit status updates
4. **OSC 9 Signal** — Codex completion signals mapped to tab state via Ghostty's notification path

### Example Workflow

```bash
# Tab automatically marked as "running" when you start Codex
codex "implement user authentication"

# When Codex completes, tab shows "done" status
# If you're in another tab, you'll see an attention indicator
```

---

## 📋 Current Status

**Validated on:** Arch Linux + Hyprland + Wayland

### ✅ Working Features

- ✅ Vertical sidebar navigation
- ✅ Working directory display
- ✅ `Alt+1..9` tab switching
- ✅ `panmuxctl notify` / `set-status` / `clear-status`
- ✅ `panmuxctl focus-tab` / `list-tabs`
- ✅ Multi-instance isolation
- ✅ Environment variable injection
- ✅ Desktop notification mapping

### 🚧 Scope Boundaries

**Not trying to be:**
- ❌ A full `cmux` clone
- ❌ An Electron/Tauri wrapper
- ❌ A prompt-parsing cwd detector
- ❌ A generic shell lifecycle tracker

**Current non-goals:**
- `pi` integration (planned for later)
- Full session restore/persistence
- macOS-specific features

---

## 📚 Documentation

- **[Implementation Blueprint](./docs/IMPLEMENTATION_BLUEPRINT.md)** — Technical architecture and design decisions
- **[Patch Map](./docs/PATCH_MAP.md)** — Fork delta tracking for upstream sync
- **[Phase 0 Spike Report](./docs/PHASE0_SPIKE_REPORT.md)** — Early validation work
- **[Scripts](./scripts/)** — Local install and Codex integration helpers

---

## 🛠️ Development

### Build

```bash
zig build
```

For faster macOS builds (if you don't need the app bundle):
```bash
zig build -Demit-macos-app=false
```

### Test

```bash
# Run all tests (slow)
zig build test

# Run specific tests
zig build test -Dtest-filter=<test name>
```

### Format

```bash
# Zig code
zig fmt .

# Swift code (macOS)
swiftlint lint --fix

# Other files
prettier -w .
```

---

## 🤝 Contributing

This is an active prototype. Contributions are welcome, but please note:

- **No issues or PRs yet** — The project is in rapid iteration
- **Focus on Linux/GTK** — macOS support is inherited from Ghostty but not the primary focus
- **Agent workflows first** — Features should serve coding agent use cases

---

## 🔄 Upstream Sync

This repository tracks Ghostty as upstream:

```bash
# Recommended remote setup
git remote add origin <your-panmux-fork>
git remote add upstream https://github.com/ghostty-org/ghostty
```

We maintain a minimal fork delta focused on:
- GTK window shell modifications
- Sidebar UI components
- Control plane integration
- Environment variable injection

---

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.

Based on [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto and contributors.

---

## 🙏 Acknowledgments

- **[Ghostty](https://github.com/ghostty-org/ghostty)** — The incredible terminal emulator that makes this possible
- **[cmux](https://github.com/manaflow-ai/cmux)** — Inspiration for agent-oriented terminal UI
- **[Codex](https://codex.so)** — The coding agent that drove the need for better terminal coordination

---

<p align="center">
  <strong>Built with ❤️ for developers who live in the terminal</strong>
</p>
