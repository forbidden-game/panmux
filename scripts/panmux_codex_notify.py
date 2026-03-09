#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
from typing import Any

TURN_COMPLETE = "agent-turn-complete"
RESUMABLE_STATE = "_panmux_codex_resume"


def get_path(obj: Any, *path: str) -> Any:
    cur = obj
    for part in path:
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def first_nonempty(obj: dict[str, Any], paths: list[tuple[str, ...]]) -> str | None:
    for path in paths:
        value = get_path(obj, *path)
        if isinstance(value, str):
            stripped = value.strip()
            if stripped:
                return stripped
    return None


def shorten(text: str, limit: int = 160) -> str:
    flat = " ".join(text.split())
    if len(flat) <= limit:
        return flat
    return flat[: limit - 1] + "…"


def event_type(payload: dict[str, Any]) -> str | None:
    return first_nonempty(payload, [
        ("type",),
        ("event_type",),
        ("event", "type"),
    ])


def state_for(payload: dict[str, Any]) -> str:
    status = first_nonempty(payload, [
        ("status",),
        ("result",),
        ("turn_status",),
        ("event", "status"),
    ])
    if status and status.lower() in {"error", "failed", "failure"}:
        return "error"
    if get_path(payload, "error") not in (None, False, ""):
        return "error"
    return "info"


def panmux_state_for(payload: dict[str, Any]) -> str:
    state = state_for(payload)
    # Keep Codex turn-complete resumable without exposing the private marker in UI.
    if event_type(payload) == TURN_COMPLETE and state == "info":
        return RESUMABLE_STATE
    return state


def title_for(payload: dict[str, Any]) -> str:
    return first_nonempty(payload, [
        ("title",),
        ("event", "title"),
        ("metadata", "title"),
    ]) or "Codex"


def body_for(payload: dict[str, Any]) -> str:
    body = first_nonempty(payload, [
        ("message",),
        ("subtitle",),
        ("event", "message"),
        ("event", "subtitle"),
        ("last_assistant_message",),
        ("turn", "summary"),
    ])
    if body:
        return shorten(body)
    et = event_type(payload)
    return et or "turn complete"


def main() -> int:
    raw = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    raw = raw.strip()
    if not raw:
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0

    if not isinstance(payload, dict):
        return 0

    if event_type(payload) != TURN_COMPLETE:
        return 0

    panmuxctl = shutil.which("panmuxctl")
    if not panmuxctl:
        return 0

    cmd = [
        panmuxctl,
        "notify",
        "--title",
        title_for(payload),
        "--body",
        body_for(payload),
        "--state",
        panmux_state_for(payload),
    ]

    try:
        subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=os.environ.copy())
    except OSError:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
