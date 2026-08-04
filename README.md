# tmux-attention

[![CI](https://github.com/cengebretson/tmux-attention/actions/workflows/ci.yml/badge.svg)](https://github.com/cengebretson/tmux-attention/actions/workflows/ci.yml)

Generic attention marker for terminal agents running inside tmux.

## Requirements

- tmux
- A POSIX `sh` (the CLI and TPM plugin need nothing more)
- `python3` — only for installing/uninstalling agent hooks via `setup` or
  `install-hooks`. The status marker and CLI work without it.

The plugin has three parts:

| Part | What it does |
|------|--------------|
| TPM plugin | Defines tmux options, status rendering, icons, and clear-on-view hooks |
| CLI | Sets attention state and active agent context for the current tmux window |
| Agent hooks | Call the CLI when Claude Code or Codex starts, stops, or needs attention |

For normal use, install the TPM plugin and then install the agent hooks. The
TPM plugin alone can render a marker, but nothing automatic sets that marker
until hooks or another integration calls the CLI.

## Quick Start

Add the plugin to your tmux config:

```tmux
set -g @plugin 'cengebretson/tmux-attention'
```

Then press `prefix + I` to install plugins, or run TPM's install command.

After TPM installs the plugin, run setup. With no target, setup installs Codex
hooks and writes a managed status snippet to `~/.tmux.conf`:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup --reload
```

Use `claude` or `all` if you want different hooks:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup claude
~/.config/tmux/plugins/tmux-attention/scripts/setup all
```

For Claude Code, use `/hooks` to verify the installed hooks. For Codex, use
`/hooks` to review and trust the installed hooks before they can run.

If you prefer to edit tmux config yourself, add the status helper wherever your
theme renders window text:

```tmux
set -g window-status-format "#{E:@tmux_attention_status}#I:#W"
set -g window-status-current-format "#{E:@tmux_attention_status}#I:#W"
```

The CLI can print that snippet:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention status-format
```

To show the active agent's project in another status module, with the current
pane directory as the automatic fallback, use:

```tmux
#{E:@tmux_attention_context}
```

For example:

```tmux
set -ga status-right " 󰉋 #{E:@tmux_attention_context} "
```

The CLI can print the format token:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention context-format
```

## Configure

Put overrides before TPM loads the plugin in your main tmux config.

```tmux
set -g @tmux_attention_icon_input "󱐋"
set -g @tmux_attention_icon_blocked ""
set -g @tmux_attention_icon_review "󰛨"
set -g @tmux_attention_icon_done ""
set -g @tmux_attention_icon_working "󰚩"
set -g @tmux_attention_clear_delay "8"
set -g @tmux_attention_clear_on_view "on"

set -g @plugin 'cengebretson/tmux-attention'
```

Catppuccin example:

```tmux
set -g @catppuccin_window_text "#{E:@tmux_attention_status}#W"
set -g @catppuccin_window_current_text "#{E:@tmux_attention_status}#W"
```

For a single leading tab glyph, `#{E:@tmux_attention_tab_icon}` renders the
highest-priority state: an attention icon first, then the working icon while an
agent turn is active, otherwise nothing. This lets a custom format fall back to
its normal window number only when the plugin has no state to show.

Print the Catppuccin snippet:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention catppuccin-format
```

Run setup with Catppuccin wiring:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup --status-line catppuccin --reload
```

## Use

The portable CLI is `scripts/tmux-attention`.

```sh
tmux-attention
tmux-attention input
tmux-attention blocked
tmux-attention blocked --target <tmux-target>
tmux-attention blocked --source moshi --reason approval_required
tmux-attention --target <tmux-target> clear
tmux-attention event approval_required --target <tmux-target>
tmux-attention get --target <tmux-target>
tmux-attention get --target <tmux-target> --format json
tmux-attention list --format json
tmux-attention review
tmux-attention done
tmux-attention clear
tmux-attention turn-start
tmux-attention turn-start --project FLYWL-2533
tmux-attention turn-stop
tmux-attention status-format
tmux-attention catppuccin-format
tmux-attention context-format
tmux-attention doctor
tmux-attention doctor --probe
tmux-attention version
```

After TPM installs the plugin, you can put the CLI on your `PATH`:

```sh
ln -s ~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention ~/.local/bin/tmux-attention
```

The command defaults to `input`. Without `--target`, it uses the current tmux
pane. If it is run outside tmux without an explicit target, it falls back to a
terminal bell.

Markers are window-scoped: `tmux-attention` writes the `@agent_attention` window
option for the target window. `--target` accepts the same tmux targets as
`set-window-option -t`, such as a pane id (`%12`) or window target
(`session:window`). If multiple agent panes share one tmux window, the most
recent state wins for that window.

Writes can include optional metadata:

```sh
tmux-attention input --source moshi --reason approval_required
```

Metadata is stored in separate window options:

| Option | Meaning |
|--------|---------|
| `@agent_attention_source` | integration or tool that set the marker |
| `@agent_attention_reason` | event or reason that produced the marker |
| `@agent_attention_updated_at` | Unix timestamp for the last marker write |

Use `get` or `list` for scripts and pickers:

```sh
tmux-attention get --target %12
tmux-attention get --target %12 --format json
tmux-attention list --session work --format json
```

External event systems can use a small adapter command:

```sh
tmux-attention event approval_required --target %12 --source moshi
tmux-attention event task_complete --target %12 --source moshi
tmux-attention event session_started --target %12 --source moshi
```

The adapter maps event names to marker states:

| Event | State |
|-------|-------|
| `approval_required` | `input` |
| `blocked`, `stop_failure`, `hook_failure` | `blocked` |
| `review_required`, `needs_review` | `review` |
| `task_complete` | `done` |
| `session_started` | `clear` |
| `tool_running`, `tool_finished` | no-op |

`tool_running` and `tool_finished` are accepted as no-ops so noisy event
streams can call the adapter safely. Unless `--reason` is passed, each
state-setting event stores its own event name as the reason, and `--source`
defaults to `event`.

## Active Agent Context

Agent hooks mark a turn active from prompt submission until the agent's `Stop`
event. While active, `#{E:@tmux_attention_context}` renders:

```text
FLYWL-2533
```

When no agent turn is active, the same format renders the basename of
`pane_current_path`, so ordinary tmux windows keep their normal project
display.

`turn-start` derives its project label in this order:

1. Jira-style key in the current Git branch, such as `FLYWL-2533`
2. Git repository name
3. Current directory name

Use `--project` to override the derived label. Context is window-scoped, like
attention state, but records its owning pane so a stale `Stop` from another
pane cannot clear a newer agent turn.

The context window options are:

| Option | Meaning |
|--------|---------|
| `@agent_context_active` | `1` while an agent turn is running |
| `@agent_context_project` | derived or supplied project label |
| `@agent_context_pane` | pane that owns the active context |
| `@agent_context_updated_at` | Unix timestamp for the latest turn start |

## Agent Hooks

Optional Claude Code and Codex hooks can call the same CLI. Setup wraps hook
installation and status-line config:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup codex --status-line none
~/.config/tmux/plugins/tmux-attention/scripts/setup all --status-line catppuccin
~/.config/tmux/plugins/tmux-attention/scripts/setup all --uninstall
```

See [docs/hooks.md](docs/hooks.md) for exact hook files, events, and lower-level
`install-hooks` commands.

Prompt-submit hooks call `turn-start`, which also clears the previous attention
marker. Stop hooks call `turn-stop`, returning the context format to its PWD
fallback. Permission and failure hooks continue to set the existing attention
states.

## Test

Run the local check script:

```sh
tests/check.sh
```

The check starts an isolated tmux server and verifies plugin loading, default
options, user overrides, hook installation, agent context, and CLI state
changes. CI runs the same checks plus ShellCheck on every push and pull request.

## Releasing

The version lives in `VERSION`, and CI enforces that `v*` tags match it:

1. `VERSION`
2. A matching `## [X.Y.Z]` entry in [CHANGELOG.md](CHANGELOG.md)
3. The `vX.Y.Z` git tag

Bump `VERSION`, promote the changelog entry, then push with
`git push origin main --follow-tags`.

## Troubleshooting

### Marker Does Not Show

Confirm the plugin is loaded:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention doctor
```

From inside tmux, add `--probe` to set, render, and clear a test marker so you
can confirm the icon round-trips through your status line:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention doctor --probe
```

If the doctor says your status line is missing the plugin, make sure your tmux
theme includes:

```tmux
#{E:@tmux_attention_status}
```

You can print default snippets with:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention status-format
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention catppuccin-format
```

If agent project context is missing from a custom status module, include:

```tmux
#{E:@tmux_attention_context}
```

### Hooks Are Not Firing

Check whether hooks are installed:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention doctor
```

Claude Code's `/hooks` menu is useful for verifying hook configuration. Codex
requires hook review/trust before non-managed hooks run; in Codex, use `/hooks`
to inspect and trust the installed hook definitions.

### Command Not Found

Hooks use the full plugin path by default. For manual use from your shell,
either call the script directly:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention input
```

Or symlink it onto your `PATH`:

```sh
ln -s ~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention ~/.local/bin/tmux-attention
```

## States

| State | Default Icon | Intended Use |
|-------|--------------|--------------|
| `input` | `󱐋` | Agent needs user input |
| `blocked` | `` | Agent is blocked or hit an error requiring intervention |
| `review` | `󰛨` | Agent has output ready for review |
| `done` | `` | Agent finished a task |
| `clear` | none | Clear the marker |

## Notes

- Core behavior is POSIX shell plus tmux; Fish is not required.
- Clear-on-view hooks are installed at tmux hook index `90`, so re-sourcing the
  plugin updates the hook instead of appending duplicates.

## Related Plugins

- [tmux-fzf-jump](https://github.com/cengebretson/tmux-fzf-jump) switches to any
  tmux session, window, or pane with fzf and can display `tmux-attention` states.

## License

MIT. See [LICENSE](LICENSE).
