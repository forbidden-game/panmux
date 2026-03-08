# panmux

`panmux` is a Ghostty GTK fork for coding-agent terminal workflows on Linux/Wayland.

It is not trying to fully clone `cmux`. The current goal is narrower and more practical: keep Ghostty's terminal core, then add the few workflow features that matter most when you live inside tools like Codex.

## What panmux does

`panmux` currently focuses on four things:

- a vertical sidebar for tabs
- cwd shown directly in the sidebar for each tab
- `Alt+1..9` tab switching with visible shortcut hints
- a small control plane that lets external tools update tab state

That means `panmux` is useful even before it grows into a bigger terminal product: it already makes long-running agent sessions easier to scan, switch, and monitor.

## What panmux changes compared to Ghostty

`panmux` does **not** replace Ghostty's terminal engine, renderer, PTY model, or tab/split core.

Instead, the current work stays intentionally narrow:

- reworks the GTK window shell around Ghostty's existing Linux frontend
- adds a left sidebar as the primary tab UI
- surfaces cwd from Ghostty's existing pwd signal path
- adds a per-window Unix socket control plane with JSON-line messages
- injects `PANMUX_*` environment variables into shell children
- lets external tools mark a tab as `running`, `done`, `error`, `info`, or clear it
- maps Ghostty desktop notifications into tab/sidebar status updates

In short: **Ghostty remains the terminal; panmux adds agent-oriented window control and status UX on top.**

## Why this exists

When using coding agents in a terminal, the hard part is often not terminal emulation itself. The hard part is coordination:

- Which tab is doing what?
- Which session finished?
- Which tab is still busy?
- Which working directory does this tab belong to?

Ghostty already provides a strong terminal foundation on Linux. `panmux` uses that instead of starting over, and focuses on the extra UI/control-plane layer needed for agent-heavy workflows.

## Current status

The current validated baseline on Arch Linux + Hyprland + Wayland is:

- vertical sidebar is working
- cwd is shown in the sidebar
- `Alt+1..9` switches tabs
- `panmuxctl notify` works
- `panmuxctl set-status` works
- `panmuxctl clear-status` works
- `panmuxctl focus-tab` works
- `panmuxctl list-tabs` works
- shell children receive:
  - `PANMUX_INSTANCE_ID`
  - `PANMUX_SOCKET_PATH`
  - `PANMUX_TAB_ID`
  - `PANMUX_SURFACE_ID`

## Codex integration: what is real today

`panmux` does **not** modify Codex source code.

The current integration strategy is external:

- `scripts/panmux_codex_notify.py` is a bridge for Codex-style notify payloads
- `scripts/panmux_codex_wrapper.sh` is a weaker fallback that can set status before/after a Codex process runs
- interactive Codex completion has been observed to emit `OSC 9;pong`
- Ghostty already turns `OSC 9` into a desktop notification
- `panmux` now maps that notification path back into tab state

That gives us a practical "turn completed" signal without pretending that ordinary shell exit is the same thing as a real agent completion event.

## Color rendering note

One subtle issue was traced to environment inheritance, not rendering bugs.

`panmux` itself correctly renders ANSI and truecolor output. A temporary "Codex is all white / input box lost its gray background" problem turned out to come from launching test windows under a parent environment that had `NO_COLOR=1`.

The local `panmux` launcher now removes `NO_COLOR` at process start so Codex can render normally.

## Local install

Right now the recommended install path is local-prefix install, not distro packaging.

Use:

- `scripts/install_local_panmux.sh`

That script:

- builds `ReleaseFast`
- installs into `~/.local/opt/panmux/<git-sha>`
- points `~/.local/opt/panmux/current` at the active version
- installs `~/.local/bin/panmux`
- installs `~/.local/bin/panmuxctl`
- installs `~/.local/share/applications/panmux.desktop`
- launches with `--gtk-single-instance=false` by default
- removes `NO_COLOR` before starting the app

## Repository layout

This repository is now the single source of truth for `panmux`.

- runtime code lives in the Ghostty GTK fork
- `docs/` contains implementation notes and validation reports
- `scripts/` contains local install and Codex integration helpers

If you keep tracking upstream Ghostty, the recommended remote layout is:

- your `panmux` GitHub repo as `origin`
- `ghostty-org/ghostty` as `upstream`

## Scope boundaries

Current non-goals or not-yet-done items:

- no attempt to fully recreate cmux
- no Electron/Tauri wrapper
- no prompt parsing for cwd
- no fake "Codex complete" signal based on generic shell lifecycle
- no `pi` integration yet
- no claim that libghostty embedding is the better path right now

## More detail

For deeper implementation context, see:

- `docs/IMPLEMENTATION_BLUEPRINT.md:1`
- `docs/PATCH_MAP.md:1`
- `docs/PHASE0_SPIKE_REPORT.md:1`
