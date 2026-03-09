<p align="center">
  <img src="images/icons/icon_128.png" alt="panmux icon" width="96" />
</p>

<h1 align="center">panmux</h1>

<p align="center">
  A Ghostty GTK fork for coding-agent terminal workflows on Linux/Wayland.
</p>

<p align="center">
  <a href="./README.md"><strong>English</strong></a>
  ·
  <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Linux%20%2F%20Wayland-1f6feb" />
  <img alt="ui" src="https://img.shields.io/badge/frontend-GTK-2da44e" />
  <img alt="base" src="https://img.shields.io/badge/base-Ghostty-f59e0b" />
  <img alt="status" src="https://img.shields.io/badge/status-active%20prototype-dc2626" />
  <img alt="license" src="https://img.shields.io/badge/license-MIT-6f42c1" />
</p>

> Keep Ghostty's fast terminal core. Add the control layer that agent-heavy terminal work actually needs.

The icon shown here is the same artwork shipped in the app bundles and desktop assets.

`panmux` is not trying to be a full `cmux` clone. The scope is deliberately tighter: preserve Ghostty's terminal engine, then improve the Linux GTK shell around it so long-running agent sessions are easier to scan, switch, and coordinate.

## Why panmux

When you live in terminal-based coding agents, the hard part is often not emulation. It is coordination:

- Which tab is busy right now?
- Which session already finished?
- Which working directory does this tab belong to?
- How do external tools signal useful state without screen scraping?

`panmux` exists to answer those questions with a workflow-oriented tab UI and a small control plane, while still standing on Ghostty's terminal foundation.

## Feature snapshot

| Area | What is available today |
| --- | --- |
| Tab UX | Vertical sidebar, visible tab shortcuts, `Alt+1..9` switching |
| Context | Current working directory shown directly in the sidebar |
| Automation | Per-window Unix socket control plane with JSON-line messages |
| Status | External tools can mark a tab as `running`, `info`, `error`, or clear it |
| Notifications | Ghostty desktop notifications are mapped back into sidebar/tab status |
| Child processes | Shell children receive `PANMUX_INSTANCE_ID`, `PANMUX_SOCKET_PATH`, `PANMUX_TAB_ID`, and `PANMUX_SURFACE_ID` |

## What panmux changes compared to Ghostty

`panmux` does **not** replace Ghostty's renderer, PTY model, terminal engine, or split/tab core.

It currently stays intentionally narrow:

- reworks the GTK window shell around Ghostty's existing Linux frontend
- adds a left sidebar as the primary tab UI
- surfaces cwd from Ghostty's existing pwd signal path
- adds a per-window Unix socket control plane
- injects `PANMUX_*` environment variables into shell children
- turns notification events into tab/sidebar status updates

In one line: **Ghostty remains the terminal; panmux adds agent-oriented window control and status UX on top.**

## Current validated baseline

The current validated baseline on Arch Linux + Hyprland + Wayland is:

- vertical sidebar is working
- cwd is shown in the sidebar
- `Alt+1..9` switches tabs
- `panmuxctl notify` works
- `panmuxctl set-status` works
- `panmuxctl clear-status` works
- `panmuxctl focus-tab` works
- `panmuxctl list-tabs` works

## Codex integration: what is real today

`panmux` does **not** modify Codex source code. The integration strategy is external and practical:

- `scripts/panmux_codex_notify.py` bridges Codex-style notify payloads
- bare interactive `codex` commands now auto-mark the tab as `running` via shell preexec detection
- `scripts/panmux_codex_wrapper.sh` remains a weaker fallback for explicit process-level status updates
- interactive Codex completion has been observed to emit `OSC 9;pong`
- Ghostty already maps `OSC 9` to desktop notifications
- `panmux` uses that path to reflect completion back into tab state as `info`

That gives a useful completion signal without pretending that generic shell exit is the same thing as a real agent event.

## Rendering note

`panmux` renders ANSI and truecolor output correctly. A temporary "Codex is all white" issue was traced to inherited environment state, not rendering bugs: a parent shell had `NO_COLOR=1`.

The local launcher now strips `NO_COLOR` before starting the app so Codex can render normally.

## Install locally

The recommended path right now is local-prefix install rather than distro packaging:

```bash
scripts/install_local_panmux.sh
```

That script:

- builds `ReleaseFast`
- installs into `~/.local/opt/panmux/<git-sha>`
- points `~/.local/opt/panmux/current` at the active version
- installs `~/.local/bin/panmux`
- installs `~/.local/bin/panmuxctl`
- installs `~/.local/share/applications/panmux.desktop`
- launches with `--gtk-single-instance=false` by default
- removes `NO_COLOR` before starting the app

## Repository guide

This repository is the single source of truth for `panmux`.

- runtime code lives in the Ghostty GTK fork
- [`docs/IMPLEMENTATION_BLUEPRINT.md`](./docs/IMPLEMENTATION_BLUEPRINT.md) explains the implementation shape
- [`docs/PATCH_MAP.md`](./docs/PATCH_MAP.md) tracks the fork delta
- [`docs/PHASE0_SPIKE_REPORT.md`](./docs/PHASE0_SPIKE_REPORT.md) records the early validation work
- `scripts/` contains local install and Codex integration helpers

If you keep tracking upstream Ghostty, the recommended remote layout is:

- your `panmux` GitHub repo as `origin`
- `ghostty-org/ghostty` as `upstream`

## Scope boundaries

Current non-goals or not-yet-done items:

- no attempt to fully recreate `cmux`
- no Electron or Tauri wrapper
- no cwd prompt parsing hacks
- no fake "Codex complete" signal based on generic shell lifecycle
- no `pi` integration yet
- no claim that libghostty embedding is the better path right now
