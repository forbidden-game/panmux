#!/usr/bin/env bash
set -euo pipefail

CODEX_BIN="${PANMUX_CODEX_BIN:-codex}"
TITLE="${PANMUX_CODEX_TITLE:-Codex}"
RUNNING_BODY="${PANMUX_CODEX_RUNNING_BODY:-session running}"
SESSION_ID="${PANMUX_SESSION_ID:-codex-$$-$(date +%s%N)}"

export PANMUX_SESSION_ID="$SESSION_ID"
export PANMUX_AGENT_TYPE="${PANMUX_AGENT_TYPE:-codex}"
export PANMUX_AGENT_LABEL="${PANMUX_AGENT_LABEL:-$TITLE}"

if command -v panmuxctl >/dev/null 2>&1; then
  panmuxctl set-status \
    --state running \
    --title "$TITLE" \
    --body "$RUNNING_BODY" \
    --session-id "$SESSION_ID" \
    --agent-type "${PANMUX_AGENT_TYPE}" \
    --agent-label "${PANMUX_AGENT_LABEL}" \
    >/dev/null 2>&1 || true
fi

status=0
if ! "$CODEX_BIN" "$@"; then
  status=$?
fi

if command -v panmuxctl >/dev/null 2>&1; then
  panmuxctl clear-status \
    --session-id "$SESSION_ID" \
    >/dev/null 2>&1 || true
fi

exit $status
