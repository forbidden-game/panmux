#!/usr/bin/env bash
set -euo pipefail

trace_root="${1:-}"
if [[ -z "$trace_root" ]]; then
  trace_root="/tmp/panmux-real-trace-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$trace_root"

meta="$trace_root/meta.txt"
pids="$trace_root/pids.txt"
: > "$pids"

log_pid() {
  printf '%s\n' "$1" >> "$pids"
}

start_bg() {
  local name="$1"
  shift
  ("$@") > "$trace_root/$name.log" 2>&1 &
  log_pid "$!"
}

start_bg notifications dbus-monitor --session "interface='org.freedesktop.Notifications'"
start_bg mako-list bash -lc '
  last=""
  while true; do
    now="$(date --iso-8601=ns)"
    cur="$(makoctl list 2>/dev/null || true)"
    if [[ "$cur" != "$last" ]]; then
      printf "=== %s ===\n%s\n\n" "$now" "$cur"
      last="$cur"
    fi
    sleep 0.2
  done
'
start_bg hypr-active bash -lc '
  last=""
  while true; do
    now="$(date --iso-8601=ns)"
    cur="$(hyprctl -j activewindow 2>/dev/null || true)"
    if [[ "$cur" != "$last" ]]; then
      printf "=== %s ===\n%s\n\n" "$now" "$cur"
      last="$cur"
    fi
    sleep 0.2
  done
'
start_bg ghostty-clients bash -lc '
  last=""
  while true; do
    now="$(date --iso-8601=ns)"
    cur="$(hyprctl -j clients 2>/dev/null | jq -c "[.[] | select(.class == \"io.github.forbidden_game.panmux\" or .class == \"com.mitchellh.ghostty\") | {address, pid, title, focusHistoryID, workspace: .workspace.id}]" || true)"
    if [[ "$cur" != "$last" ]]; then
      printf "=== %s ===\n%s\n\n" "$now" "$cur"
      last="$cur"
    fi
    sleep 0.2
  done
'
start_bg codex-log-tail bash -lc '
  log="$HOME/.codex/log/codex-tui.log"
  touch "$log"
  tail -n 0 -F "$log"
'

cat > "$trace_root/README.txt" <<EOF
Trace dir: $trace_root

1. In your usual Ghostty window/tab, run your normal command (recommended: cx).
2. Reproduce exactly the behavior where you usually get a notification.
3. Important: when Codex is thinking, move focus to a non-Ghostty app (e.g. Zed or Chrome) if that matches your normal usage.
4. After the notification appears, exit Codex.
5. Tell Codex this trace dir: $trace_root
6. Stop trace with: /home/pxz/Work/tries/panmux/scripts/stop_real_notify_trace.sh $trace_root

Optional PTY capture from the same Ghostty shell:
  script -q -f "$trace_root/codex.typescript"
  # then run cx inside that nested shell, reproduce once, then exit twice.
EOF

{
  printf 'trace_root=%s\n' "$trace_root"
  printf 'started_at=%s\n' "$(date --iso-8601=ns)"
  printf 'ghostty_pids=%s\n' "$(pgrep -a ghostty | tr '\n' ';' || true)"
  printf 'codex_processes=%s\n' "$(ps -ef | rg 'codex' | rg -v 'rg ' | tr '\n' ';' || true)"
  printf 'mako_mode=%s\n' "$(makoctl mode 2>/dev/null || true)"
} > "$meta"

printf '%s\n' "$trace_root"
