#!/usr/bin/env bash
set -euo pipefail

CODEX_BIN="${PANMUX_CODEX_BIN:-codex}"
TITLE="${PANMUX_CODEX_TITLE:-Codex}"
RUNNING_BODY="${PANMUX_CODEX_RUNNING_BODY:-session running}"
DONE_BODY="${PANMUX_CODEX_DONE_BODY:-session exited}"
ERROR_BODY="${PANMUX_CODEX_ERROR_BODY:-session exited with error}"

if command -v panmuxctl >/dev/null 2>&1; then
  panmuxctl set-status --state running --title "$TITLE" --body "$RUNNING_BODY" >/dev/null 2>&1 || true
fi

status=0
if ! "$CODEX_BIN" "$@"; then
  status=$?
fi

if command -v panmuxctl >/dev/null 2>&1; then
  if [[ $status -eq 0 ]]; then
    panmuxctl set-status --title "$TITLE" --body "$DONE_BODY" --state info >/dev/null 2>&1 || true
  else
    panmuxctl set-status --title "$TITLE" --body "$ERROR_BODY" --state error >/dev/null 2>&1 || true
  fi
fi

exit $status
