#!/usr/bin/env bash
set -euo pipefail

trace_root="${1:?usage: stop_real_notify_trace.sh TRACE_DIR}"
pids="$trace_root/pids.txt"
if [[ -f "$pids" ]]; then
  tac "$pids" | while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done
fi
printf 'stopped=%s\n' "$(date --iso-8601=ns)" >> "$trace_root/meta.txt"
echo "$trace_root"
