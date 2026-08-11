# Agent Hooks

`tmux-attention` can install optional agent hooks that call the portable CLI.
The TPM plugin itself does not edit agent configuration files.

Hook installation requires `python3` (used to edit the JSON hook config files
safely). The status marker and CLI do not need it.

## Install

After TPM installs the plugin, the simplest path is setup:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup
~/.config/tmux/plugins/tmux-attention/scripts/setup codex
~/.config/tmux/plugins/tmux-attention/scripts/setup claude
```

Setup defaults to Codex hooks, writes a managed status snippet to `~/.tmux.conf`,
and accepts `--reload` to source the config immediately. Use `all` only when you
want both Claude Code and Codex hooks.

Common setup commands:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup --reload
~/.config/tmux/plugins/tmux-attention/scripts/setup claude --reload
~/.config/tmux/plugins/tmux-attention/scripts/setup all --status-line catppuccin
~/.config/tmux/plugins/tmux-attention/scripts/setup codex --status-line none
~/.config/tmux/plugins/tmux-attention/scripts/setup all --uninstall
```

To manage only agent hooks, run:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks claude
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks codex
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks all
```

For Claude Code, use `/hooks` after installation to verify the installed hooks.
For Codex, open `/hooks` after installation and trust the new hook definitions.

Check what is installed:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks --status all
```

Uninstall only `tmux-attention` managed hook entries:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks --uninstall all
```

Print the JSON snippets without editing files:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks --print all
```

The installer creates timestamped backups before changing existing files.
Managed hook commands include a `tmux-attention` marker so future installs and
uninstalls update only this plugin's entries.

## Claude Code

Default target:

```text
~/.claude/settings.json
```

Installed hooks:

| Event | Matcher | Command |
|-------|---------|---------|
| `Notification` | `permission_prompt|idle_prompt` | `tmux-attention input` |
| `StopFailure` | none | `tmux-attention blocked` |
| `UserPromptSubmit` | none | `tmux-attention turn-start` |
| `Stop` | none | `tmux-attention turn-done --source claude --reason response_ready` |

After installing Claude Code hooks, use `/hooks` in Claude Code to verify the
installed hook definitions. The Claude Code hook menu is read-only; edits are
made in the settings JSON file.

## Codex

Default target:

```text
~/.codex/hooks.json
```

If `CODEX_HOME` is set, the default becomes `$CODEX_HOME/hooks.json`
(`TMUX_ATTENTION_CODEX_HOOKS` still overrides the full path).

Installed hooks:

| Event | Matcher | Command |
|-------|---------|---------|
| `PreToolUse` | `.*` | `tmux-attention turn-active` |
| `PermissionRequest` | `.*` | `tmux-attention input` |
| `UserPromptSubmit` | none | `tmux-attention turn-start` |
| `Stop` | none | `tmux-attention turn-done --source codex --reason response_ready` |

After installing Codex hooks, use `/hooks` in Codex to review and trust the
installed hook definitions. Codex skips non-managed hooks until they are
trusted.

`Stop` represents a completed agent turn, not the end of the whole project or
conversation. `turn-done` clears active context and sets the `done` marker
atomically, so the check icon means "response ready." The next
`UserPromptSubmit` clears that marker through `turn-start`.

Codex may continue an overall task after an intermediate `Stop`, including
automatic goal continuations. The next `PreToolUse` calls the idempotent
`turn-active` transition, restoring working context and clearing the premature
completion marker without rewriting state on every tool call.

The `turn-start` hooks derive a project label from the pane's Git branch,
repository, or current directory. Include `#{E:@tmux_attention_context}` in a
status module to render the project during a turn and the pane's current
directory when no agent is running.

## Custom Paths

For tests or custom locations:

```sh
TMUX_ATTENTION_CLAUDE_SETTINGS=/tmp/claude-settings.json \
TMUX_ATTENTION_CODEX_HOOKS=/tmp/codex-hooks.json \
scripts/install-hooks all
```
