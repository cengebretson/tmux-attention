# Tmux Attention Marker

Generic attention marker for terminal agents running inside tmux. It stores a typed state in tmux and shows an event-specific icon in the window tab.

## Architecture

This should be a tmux-first tool, not a Fish-first tool.

Recommended split:

| Layer | Responsibility |
|-------|----------------|
| Tmux plugin | Own `@agent_attention`, icons, status rendering helpers, clear-on-view hooks, and default options |
| Portable CLI | Provide `tmux-attention input|blocked|review|done|clear` from any shell or hook runner |
| Fish integration | Optional completions or wrapper for interactive convenience |
| Agent hooks | Optional Claude/Codex installers that call the portable CLI |

The core API is the tmux window option:

```tmux
@agent_attention=input
@agent_attention=blocked
@agent_attention=review
@agent_attention=done
```

Everything else should read from or write to that state.

## User-Facing Command

Use:

```sh
tmux-attention
tmux-attention input
tmux-attention blocked
tmux-attention review
tmux-attention done
tmux-attention clear
```

Default behavior:

- `tmux-attention` defaults to `tmux-attention input`
- Sets a window-local tmux option: `@agent_attention=<state>`
- Keeps the marker visible while the window/session is hidden
- Clears the marker shortly after the marked window is selected/viewed
- Falls back to a terminal bell when not running inside tmux

States:

| State | Icon | Intended Use |
|-------|------|--------------|
| `input` | `󱐋` | Agent needs user input |
| `blocked` | `` | Agent is blocked or hit an error requiring intervention |
| `review` | `󰛨` | Agent has output ready for review |
| `done` | `` | Agent finished a task |
| `clear` | none | Clear the marker |

## CLI Helper

Current prototype location:

```text
~/.config/fish/functions/tmux-attention.fish
```

This is fine for local iteration, but it should not be the long-term core implementation if this becomes reusable. Agent hooks and other shells should not depend on Fish being installed or initialized.

Preferred reusable location:

```text
~/.local/bin/tmux-attention
```

Preferred implementation language:

```text
POSIX sh or bash
```

Implementation contract:

```sh
tmux set-window-option -t "$TMUX_PANE" @agent_attention input
```

The clear is handled by tmux hooks in `tmux.conf`, not only by the helper. This keeps the marker visible if it was set in a background window or another session.

## Theme Integration

The tmux plugin should provide a status-format option that reads the same generic state:

```tmux
#{E:@tmux_attention_status}
```

Current local files:

```text
~/.config/tmux/appearance1.conf
~/.config/tmux/appearance2.conf
```

The icon is intentionally inserted before the window number/name so it is visible even when the tab is short.

Default icons can ship with the tmux plugin, but users should be able to override them with tmux options:

```tmux
set -g @tmux_attention_icon_input "󱐋"
set -g @tmux_attention_icon_blocked ""
set -g @tmux_attention_icon_review "󰛨"
set -g @tmux_attention_icon_done ""
set -g @tmux_attention_status "#{?#{==:#{@agent_attention},input},#{@tmux_attention_icon_input} ,}"
```

Presentation belongs to tmux. The CLI should set only state, not icons or colors.

Users still decide where the marker appears in their theme. Example Catppuccin integration:

```tmux
set -g @catppuccin_window_text "#{E:@tmux_attention_status}#W"
set -g @catppuccin_window_current_text "#{E:@tmux_attention_status}#W"
```

## Bell Settings

The main tmux config enables bell handling:

```tmux
set -g bell-action any
set -g visual-bell on
```

File:

```text
~/.config/tmux/tmux.conf
```

The custom `@agent_attention` state is the preferred agent path because terminal BEL propagation can be unreliable through tool runners.

## Agent Usage

When an agent is blocked waiting for user input inside tmux, run:

```fish
tmux-attention input
```

When an agent is blocked by an error or missing external condition, run:

```fish
tmux-attention blocked
```

To set or clear the state manually:

```bash
tmux set-window-option -t "$TMUX_PANE" @agent_attention input
tmux set-window-option -t "$TMUX_PANE" @agent_attention ''
```

## Validation

Syntax-check the current Fish prototype:

```fish
fish -n ~/.config/fish/functions/tmux-attention.fish
```

Reload tmux:

```bash
tmux source-file ~/.config/tmux/tmux.conf
```

Short auto-clear test:

```fish
tmux-attention
tmux select-window -t "$TMUX_PANE"
sleep 9
tmux show-window-options -t "$TMUX_PANE" -v @agent_attention
```

Expected result after the sleep:

An empty value.

## Hook Installer Contract

The portable `tmux-attention` CLI can grow install commands for agent hooks:

```sh
tmux-attention --install claude
tmux-attention --install codex
tmux-attention --install all
```

The install command should only wire agent events to this shared display API. Hooks must not know tmux theme details.

```sh
tmux-attention input
tmux-attention blocked
tmux-attention review
tmux-attention done
tmux-attention clear
```

### Command Shape

Supported installer commands:

| Command | Action |
|---------|--------|
| `tmux-attention --install claude` | Install Claude hooks and helper script |
| `tmux-attention --install codex` | Install Codex hooks/plugin and helper script |
| `tmux-attention --install all` | Install both Claude and Codex hooks |
| `tmux-attention --uninstall claude` | Remove only the Claude hook entries managed by this helper |
| `tmux-attention --uninstall codex` | Remove only the Codex hook/plugin entries managed by this helper |
| `tmux-attention --status` | Show detected hook installation state |

The installer must be idempotent:

- Re-running install should not duplicate hook entries.
- Existing unrelated hooks must be preserved.
- Any JSON edit should keep a timestamped backup beside the edited file.
- Managed hook entries should have a stable marker string such as `tmux-attention` so uninstall can remove only its own entries.

### Hook Scripts

Hooks should call small shell scripts rather than embedding long commands in JSON.

Suggested paths:

```text
~/.config/tmux/hooks/tmux-attention-claude.sh
~/.config/tmux/hooks/tmux-attention-codex.sh
```

Each script should accept an event/state argument:

```bash
tmux-attention input
tmux-attention blocked
tmux-attention review
tmux-attention done
tmux-attention clear
```

The scripts should be POSIX shell or bash, not Fish, because agent hook runners usually execute non-interactive shell commands.

## Plugin Shape

If extracted, this should primarily be a tmux plugin.

Suggested repo shape:

```text
tmux-attention/
  tmux-attention.tmux
  scripts/tmux-attention
  scripts/install-claude-hook
  scripts/install-codex-hook
  completions/tmux-attention.fish
  docs/hooks.md
  README.md
```

Default install through TPM:

```tmux
set -g @plugin 'cengebretson/tmux-attention'
```

The plugin should:

- Define default icon options.
- Define a reusable status-format option or snippet.
- Install clear-on-view tmux hooks.
- Put `scripts/tmux-attention` on an easy path or document how to symlink/copy it to `~/.local/bin`.
- Keep Fish support optional.

Fish/Fisher can still be useful for completions, but the core behavior belongs in tmux plus a portable shell CLI.

### Claude Hook Plan

Claude should install through the global settings file:

```text
~/.config/claude/settings.json
```

Candidate event mapping:

| Claude Event | Marker | Notes |
|--------------|--------|-------|
| `Notification` | `input` | Best fit for permission prompts or user attention events if the hook input identifies that case |
| `StopFailure` | `blocked` | Turn ended due to API/tool/runtime failure |
| `Stop` | optional `review` or `done` | Useful only if the user wants every completed turn to mark the window |

Default Claude install should start conservative:

- Install `Notification -> input`
- Install `StopFailure -> blocked`
- Do not install `Stop -> done` by default, because it may mark every normal response

### Codex Hook Plan

Codex should install through a small personal plugin hook rather than editing random generated cache files.

Suggested plugin path:

```text
~/.codex/plugins/tmux-attention/
```

The plugin should define hook entries that call the shared hook script. Candidate mapping:

| Codex Event | Marker | Notes |
|-------------|--------|-------|
| `Stop` | optional `review` or `done` | Fires at normal turn completion; likely too noisy by default |
| `UserPromptSubmit` | `clear` | Clear a stale marker when the user comes back and submits input |
| error/failure hook, if available | `blocked` | Preferred for true blocked/error state |

Default Codex install should be conservative until there is a reliable event for "needs user input":

- Install `UserPromptSubmit -> clear`
- Do not install `Stop -> done` by default unless explicitly requested
- Keep global `~/.codex/AGENTS.md` instructions as the reliable semantic path for `input` and `blocked`

### Open Question

The display API is settled: `@agent_attention=<state>`. The only unresolved part is event fidelity. A hook can reliably react to known lifecycle events, but it cannot always infer semantic states like "waiting for user input" unless the agent exposes a specific event or hook payload for that condition.
