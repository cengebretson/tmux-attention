# Future Orc integration spec

This document describes future `tmux-attention` changes that would make it a
clean attention-state provider for `orc watch`, `tmux-fzf-jump`, and other tmux
tools without breaking the current plugin behavior.

The current implementation should remain valid:

- `tmux-attention input|blocked|review|done|clear` keeps working.
- The window option `@agent_attention` remains the canonical rendered summary.
- `@tmux_attention_status` keeps rendering in tmux status lines.
- Existing Claude/Codex hooks keep calling the same CLI states.
- Existing tmux status integrations should not need changes.

## Goal

Make `tmux-attention` a small, stable attention-state contract for the whole
tmux setup:

- agent hooks set attention state;
- tmux status renders attention state;
- picker/dashboard tools can query attention state;
- workflow tools such as `orc` can optionally set or clear attention state;
- pane-scoped state can support multiple agents without breaking window-scoped
  status rendering.

## Current contract

Today, attention is authoritative per pane, with a derived window summary:

```sh
tmux set-option -pq -t "$TMUX_PANE" @agent_pane_attention "$state"
tmux show-options -p -t "$target" -v @agent_pane_attention
tmux show-options -w -t "$target" -v @agent_attention # derived summary
```

Supported states:

| State | Meaning |
|-------|---------|
| `input` | agent needs user input or permission |
| `blocked` | agent could not continue |
| `review` | agent completed and should be reviewed |
| `done` | work completed |
| empty | no attention marker |

Aliases:

| Alias | Meaning |
|-------|---------|
| `clear` | clear marker |
| `none` | clear marker |
| `off` | clear marker |

`tmux-attention get` and `tmux-attention list` expose this state without
requiring tools to know the internal option names.

## Desired future contract

### CLI read API

Read-only commands are available:

```sh
tmux-attention get
tmux-attention get --target <tmux-target>
tmux-attention get --format text
tmux-attention get --format json
```

Behavior:

- `get` defaults to the current pane when inside tmux.
- `--target` accepts a pane id or another tmux target that resolves to a pane.
- Missing or empty attention prints nothing in text mode and exits `0`.
- Invalid target exits non-zero with a short error on stderr.

Text output:

```text
blocked
```

JSON output:

```json
{
  "scope": "pane",
  "target": "%12",
  "window_id": "@3",
  "state": "blocked",
  "source": "agent",
  "updated_at": null
}
```

`source`, `reason`, and `updated_at` are populated when writes include metadata.

### CLI target writes

Target-aware writes are available:

```sh
tmux-attention blocked --target <tmux-target>
tmux-attention clear --target <tmux-target>
```

This lets tools such as `orc` update attention for a known ticket window without
having to run from that window.

Rules:

- Existing no-flag behavior remains unchanged.
- `--target` writes pane-local authoritative state and refreshes its window
  summary.
- `clear`, `none`, and `off` still clear the marker.

### Machine-readable list API

List output is available for dashboards and fuzzy pickers:

```sh
tmux-attention list
tmux-attention list --session <session>
tmux-attention list --format text
tmux-attention list --format json
```

Text output should be easy to consume:

```text
session:1 blocked
session:2 input
```

JSON output:

```json
[
  {
    "session": "work",
    "window_index": "1",
    "window_id": "@3",
    "window_name": "develop",
    "state": "blocked"
  }
]
```

This lets `tmux-fzf-jump` rank or decorate windows that need attention
without duplicating tmux format strings.

### Stable format variables

Keep `@tmux_attention_status` as the status-line helper. Consider adding a few
stable tmux format helpers:

```tmux
@tmux_attention_state_format
@tmux_attention_icon_format
@tmux_attention_label_format
```

The current status string can keep using icons only. Picker/dashboard tools may
want text labels.

## Pane scope and window compatibility

Pane-scoped state is authoritative for windows that run multiple agents:

```tmux
@agent_pane_attention         # authoritative pane state
@agent_attention              # derived window summary
```

Compatibility rules:

- Default write and read scope is `pane`.
- Default status render scope remains the derived window summary.
- Pane state always rolls up to window-scoped rendering.
- Existing `@agent_attention` status snippets keep working forever.

The current rollup policy is:

```text
input > blocked > review > done > working
```

At equal priority, the newest pane marker supplies the summary metadata.

## Orc integration

`orc watch` can use the current implementation immediately by reading
`@agent_attention` from each ticket's tmux session/window.

With the future CLI, `orc` should prefer:

```sh
tmux-attention get --target <session>:<stage>
```

Future optional writes:

| Orc event | tmux-attention command |
|-----------|------------------------|
| `orc mark <ticket> pause` | `tmux-attention blocked --target <session>:<stage>` |
| `orc mark <ticket> next` | `tmux-attention review --target <session>:<stage>` or `done` |
| `orc mark <ticket> done` | `tmux-attention done --target <session>:<stage>` |
| `orc mark <ticket> start` | `tmux-attention clear --target <session>:<stage>` |
| `orc mark <ticket> resume` | `tmux-attention clear --target <session>:<stage>` |

`orc` should treat `tmux-attention` as optional. If the CLI is unavailable, Orc
can still render durable workflow state from `STATE.yaml`.

## tmux-fzf-jump integration

`tmux-fzf-jump` should be able to show attention markers next to sessions,
windows, or panes.

Current integration can keep using tmux options directly. Future integration can
use:

```sh
tmux-attention list --format json
```

Potential behavior:

- sort attention windows above normal windows;
- decorate rows with state icons;
- add a filter for attention-only targets;
- clear-on-jump remains handled by `tmux-attention` clear-on-view hooks.

## Hook metadata

Current hooks only set a state. Future hooks may pass metadata:

```sh
tmux-attention input --source codex --reason permission
tmux-attention blocked --source claude --reason stop-failure
```

Metadata should be optional and should not affect status rendering unless a tool
queries JSON output.

Possible metadata fields:

| Field | Example |
|-------|---------|
| `source` | `codex`, `claude`, `orc` |
| `reason` | `permission`, `stop-failure`, `stage-paused` |
| `updated_at` | unix timestamp or ISO-8601 |
| `message` | short human-readable detail |

Metadata can be stored in separate tmux options so the existing
`@agent_attention` option remains simple:

```tmux
@agent_attention
@agent_attention_source
@agent_attention_reason
@agent_attention_updated_at
@agent_attention_message
```

## Backward compatibility requirements

- Do not rename `@agent_attention`.
- Do not remove `@tmux_attention_status`.
- Do not change the meaning of current states.
- Do not require Python for the CLI read/write path.
- Do not require hooks for manual state setting.
- Keep POSIX `sh` compatibility for `scripts/tmux-attention`.
- Keep the TPM plugin lightweight.

## Suggested phases

### Phase 1: read API

- Add `tmux-attention get`.
- Add `--target`.
- Add tests for current pane, explicit target, empty state, invalid target.

### Phase 2: target writes

- Add `--target` to state-setting commands.
- Keep existing no-flag behavior unchanged.
- Add tests for writing and clearing explicit windows.

### Phase 3: list API

- Add `tmux-attention list`.
- Support text and JSON output.
- Use tmux formats rather than parsing human display text.

### Phase 4: metadata

- Add optional `--source`, `--reason`, and `--message`.
- Add JSON output fields.
- Keep status rendering unchanged by default.

### Phase 5: pane-scoped state (delivered)

- Store authoritative state as native pane options.
- Keep derived window options as the compatibility rendering layer.
- Recompute the window with fixed attention priority after every pane change.

## Open questions

- Should `review` or `done` be the default state for normal agent stop events?
- Should `get` print `clear`, `none`, or empty text for no marker?
- Should metadata expire when clear-on-view clears the marker?
- Should list output include windows with no marker when requested?
- Should the fixed window rollup priority become configurable?
