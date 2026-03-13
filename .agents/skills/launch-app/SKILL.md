---
name: launch-app
description: Launch panmux for runtime validation on a local Linux desktop session.
---

# Launch App

This repository builds a GTK desktop app on top of Ghostty. Use this skill when a change touches the running app behavior, window UI, sidebar behavior, notifications, control-plane integration, or anything else that benefits from a real launch check.

## Preconditions

- Prefer a Linux graphical session with Wayland available.
- Run from the repository root.
- If the change only affects non-app code and no GUI session is available, document that runtime launch is blocked and fall back to the narrowest relevant build/test command.

## Launch

Run:

```bash
zig build run
```

## Verify

- Wait for the panmux window to appear.
- Confirm the app launches without an immediate crash.
- If the changed behavior is visible in the UI, exercise that flow directly in the running app.
- If the control plane or status integration was touched, use another terminal to run targeted `panmuxctl` checks such as:

```bash
panmuxctl list-tabs
panmuxctl set-status --state running --title "Validation"
panmuxctl clear-status --session-id "$PANMUX_SESSION_ID"
```

## Notes

- For macOS build-only verification, use the repo guidance instead of this runtime skill:

```bash
zig build -Demit-macos-app=false
```

- Close the launched app after validation so the workspace stays clean for the next step.
