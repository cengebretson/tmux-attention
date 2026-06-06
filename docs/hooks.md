# Agent Hooks

`tmux-attention` can install optional agent hooks that call the portable CLI.
The TPM plugin itself does not edit agent configuration files.

## Install

After TPM installs the plugin, run:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks claude
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks codex
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks all
```

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

`Stop -> review` is intentionally not installed by default because it can mark
every normal turn as needing review.

## Custom Paths

For tests or custom locations:

```sh
TMUX_ATTENTION_CLAUDE_SETTINGS=/tmp/claude-settings.json \
TMUX_ATTENTION_CODEX_HOOKS=/tmp/codex-hooks.json \
scripts/install-hooks all
```
