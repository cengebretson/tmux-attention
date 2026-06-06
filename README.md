# tmux-attention

Generic attention marker for terminal agents running inside tmux.

The plugin has three parts:

| Part | What it does |
|------|--------------|
| TPM plugin | Defines tmux options, status rendering, icons, and clear-on-view hooks |
| CLI | Sets or clears the current tmux window's `@agent_attention` state |
| Agent hooks | Call the CLI when Claude Code or Codex needs attention |

For normal use, install the TPM plugin and then install the agent hooks. The
TPM plugin alone can render a marker, but nothing automatic sets that marker
until hooks or another integration calls the CLI.

## Quick Start

Add the plugin to your tmux config:

```tmux
set -g @plugin 'cengebretson/tmux-attention'
```

Then press `prefix + I` to install plugins, or run TPM's install command.

After TPM installs the plugin, install agent hooks for the agent you use:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks codex
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks claude
```

Or install hooks for both:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks all
```

Add the status helper wherever your theme renders window text:

```tmux
set -g window-status-format "#{E:@tmux_attention_status}#I:#W"
set -g window-status-current-format "#{E:@tmux_attention_status}#I:#W"
```

The CLI can print that snippet:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention status-format
```

## Configure

Put overrides before TPM loads the plugin in your main tmux config.

```tmux
set -g @tmux_attention_icon_input "󱐋"
set -g @tmux_attention_icon_blocked ""
set -g @tmux_attention_icon_review "󰛨"
set -g @tmux_attention_icon_done ""
set -g @tmux_attention_clear_delay "8"
set -g @tmux_attention_clear_on_view "on"

set -g @plugin 'cengebretson/tmux-attention'
```

Catppuccin example:

```tmux
set -g @catppuccin_window_text "#{E:@tmux_attention_status}#W"
set -g @catppuccin_window_current_text "#{E:@tmux_attention_status}#W"
```

Print the Catppuccin snippet:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention catppuccin-format
```

## Use

The portable CLI is `scripts/tmux-attention`.

```sh
tmux-attention
tmux-attention input
tmux-attention blocked
tmux-attention review
tmux-attention done
tmux-attention clear
tmux-attention status-format
tmux-attention catppuccin-format
```

After TPM installs the plugin, you can put the CLI on your `PATH`:

```sh
ln -s ~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention ~/.local/bin/tmux-attention
```

The command defaults to `input`. If it is run outside tmux, it falls back to a
terminal bell.

## Agent Hooks

Optional Claude Code and Codex hooks can call the same CLI:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks claude
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks codex
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks all
```

See [docs/hooks.md](docs/hooks.md) for the exact files and events the installer
uses.

| Command | Purpose |
|---------|---------|
| `install-hooks claude` | Install Claude Code hooks |
| `install-hooks codex` | Install Codex hooks |
| `install-hooks all` | Install both hook sets |
| `install-hooks --status all` | Show installed state |
| `install-hooks --print all` | Print JSON without editing files |
| `install-hooks --uninstall all` | Remove managed hook entries |

## Test

Run the local check script:

```sh
tests/check.sh
```

The check starts an isolated tmux server and verifies plugin loading, default
options, user overrides, hook installation, and CLI state changes.

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
- `reference/tmux-attention.fish` is kept only as the original local prototype.
- Clear-on-view hooks are installed at tmux hook index `90`, so re-sourcing the
  plugin updates the hook instead of appending duplicates.
