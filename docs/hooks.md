# Agent Hooks

`tmux-attention` can install optional agent hooks that call the portable CLI.
The TPM plugin itself does not edit agent configuration files.

## Install

After TPM installs the plugin, the simplest path is setup:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup codex
~/.config/tmux/plugins/tmux-attention/scripts/setup claude
~/.config/tmux/plugins/tmux-attention/scripts/setup all
```

Setup installs hooks and writes a managed status snippet to `~/.tmux.conf`.
Pass `--status-line none` if your tmux status is already configured manually.

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
| `UserPromptSubmit` | none | `tmux-attention clear` |

After installing Claude Code hooks, use `/hooks` in Claude Code to verify the
installed hook definitions. The Claude Code hook menu is read-only; edits are
made in the settings JSON file.

## Codex

Default target:

```text
~/.codex/hooks.json
```

Installed hooks:

| Event | Matcher | Command |
|-------|---------|---------|
| `PermissionRequest` | `.*` | `tmux-attention input` |
| `UserPromptSubmit` | none | `tmux-attention clear` |

After installing Codex hooks, use `/hooks` in Codex to review and trust the
installed hook definitions. Codex skips non-managed hooks until they are
trusted.

`Stop -> review` is intentionally not installed by default because it can mark
every normal turn as needing review.

## Custom Paths

For tests or custom locations:

```sh
TMUX_ATTENTION_CLAUDE_SETTINGS=/tmp/claude-settings.json \
TMUX_ATTENTION_CODEX_HOOKS=/tmp/codex-hooks.json \
scripts/install-hooks all
```
