# Panmux Reply State

## Goal

This document defines the current panmux reply-state model for Codex sessions.

It exists to keep one distinction explicit:

- `seen` means the user has looked at a reply
- `running` means the user has actually resumed the conversation

Those are not the same thing.

## Scope

For the current implementation, treat:

- `tab == workspace`
- a workspace as the aggregation boundary for reply-state purposes

Multiple sessions may still exist in one workspace, especially with splits, but
reply-state still lives on individual sessions and transitions are routed by
`session_id` and `surface_id` instead of assuming the whole workspace can be
acknowledged at once.

## Session State

Each Codex session tracks:

- `reply_attention = none | unseen | seen`
- `draft_started = false | true`
- `phase = starting | running | waiting_user | completed | failed | exited`

The user-facing tab state is derived from `reply_attention` first and session
activity second.

For reply-state purposes:

- `starting`, `running`, `waiting_user`, and `failed` are still reply-relevant
- `completed` and `exited` are not

Selectors and helpers must distinguish:

- process-running state
- reply-relevant state

Do not reuse a "process active" helper to decide whether `failed` or
`waiting_user` should still appear in reply-state UI.

## Display Rules

The workspace badge is derived in this order:

1. If any reply-relevant Codex session in the workspace has `reply_attention = unseen`, show `unseen`
2. Else if any reply-relevant Codex session in the workspace has `reply_attention = seen`, show `seen`
3. Else if any process-running Codex session exists in the workspace, show `running`
4. Else show no Codex reply badge

`unseen` is stronger than `seen`, and `seen` is stronger than `running`.

## Event Rules

### Codex starts or resumes

When a Codex session is started or rebound:

- set `phase` from the source event, typically `starting` or `running`
- keep `reply_attention = none`
- keep `draft_started = false`
- keep the session reply-relevant while that phase remains reply-relevant

### Codex completion notify arrives

When panmux receives a Codex completion notification:

- create or refresh the attention item
- if the turn completed normally, set `phase = waiting_user`
- if the turn failed, set `phase = failed`
- set `reply_attention = unseen`
- set `draft_started = false`

A completion notification must not leave the session in `running`.

For Codex reply attention, refresh uses this key:

1. `session_id + turn_id`, when `turn_id` is present
2. otherwise `session_id`

Refreshing means updating the existing logical reply item for that key instead
of blindly appending another unread item for the same reply.

### User views the session

When the user selects the tab, re-activates the window, or otherwise views a
specific Codex session:

- resolve the target session by explicit identity first; if none is present,
  use the currently selected workspace + selected surface binding
- only that target session may transition `unseen -> seen`
- `seen` must not become `running`
- other sessions in the same workspace must not be acknowledged implicitly

### User starts drafting a reply

When input looks like a real reply draft:

- set `draft_started = true`
- do not clear `seen` or `unseen` yet

The implementation intentionally uses conservative heuristics here. It should
prefer false negatives over false positives.

### User submits a reply

A session may return to `running` only when:

- the same session has `draft_started = true`
- the submit action is attributed to that same session/surface

Then:

- set `phase = running`
- set `reply_attention = none`
- set `draft_started = false`

There is no workspace-wide acknowledge action that may skip this transition and
clear `unseen` or `seen` directly to `none`.

## Routing Rules

These routing rules are the most important part of the model.

### Session identity

Prefer:

1. `session_id`
2. `surface_id`
3. only then fallback behavior, if explicitly intended

Do not infer a different split just because a tab currently has another active
surface.

### Split binding

If an update includes an explicit `surface_id`, it may rebind the session to
that split.

If an update identifies a session but omits `surface_id`, it must preserve the
existing split binding instead of clearing or replacing it.

This applies especially to partial `notify`, `set-status`, and `clear-status`
calls.

### Session-scoped clear

If `clear-status` is called with `session_id` but without `surface_id`, it must
clear by session identity alone.

It must not inject the page's currently active surface as an extra filter.

If a zero-argument `clear-status` form is retained for compatibility, treat it
as legacy current-target clear behavior and not as a reply-state transition API.

## Non-Goals

The current model does not try to prove that a reply was semantically accepted
by Codex. It only tracks local UI state transitions well enough to avoid these
common mistakes:

- treating "looked at it" as "replied to it"
- treating one split as proof that every split in the tab has been seen
- rebinding session state to whichever split happens to be active

## Testing Guidance

Any future change in this area should cover at least:

- `unseen -> seen` without returning to `running`
- `seen -> running` only after reply submission
- split rebinding with explicit `surface_id`
- partial updates without `surface_id` preserving the old split binding
- session-scoped `clear-status` without `surface_id`
- selected-tab / selected-surface view events only acknowledging the target
  session
- multi-session workspaces where one split stays `unseen` while another is `seen`
