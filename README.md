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

After TPM installs the plugin, run setup:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup codex
```

Setup installs agent hooks and adds a managed status snippet to `~/.tmux.conf`.
Use `claude` or `all` instead of `codex` if you want those hooks:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup claude
~/.config/tmux/plugins/tmux-attention/scripts/setup all
```

For Claude Code, use `/hooks` to verify the installed hooks. For Codex, use
`/hooks` to review and trust the installed hooks before they can run. Reload tmux
after setup:

```sh
tmux source-file ~/.tmux.conf
```

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

Run setup with Catppuccin wiring:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup all --status-line catppuccin
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

The simpler setup command wraps hook installation and status-line config:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/setup all
~/.config/tmux/plugins/tmux-attention/scripts/setup codex --status-line none
~/.config/tmux/plugins/tmux-attention/scripts/setup all --status-line catppuccin
```

Claude Code users can verify installed hooks with `/hooks`. Codex users must
review and trust installed hooks with `/hooks` before Codex will run them.

## Test

Run the local check script:

```sh
tests/check.sh
```

The check starts an isolated tmux server and verifies plugin loading, default
options, user overrides, hook installation, and CLI state changes.

## Troubleshooting

### Marker Does Not Show

Confirm the plugin is loaded:

```sh
tmux show-option -gqv @tmux_attention_status
```

If that prints a status format, make sure your tmux theme includes:

```tmux
#{E:@tmux_attention_status}
```

You can print default snippets with:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention status-format
~/.config/tmux/plugins/tmux-attention/scripts/tmux-attention catppuccin-format
```

### Hooks Are Not Firing

Check whether hooks are installed:

```sh
~/.config/tmux/plugins/tmux-attention/scripts/install-hooks --status all
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
- `reference/tmux-attention.fish` is kept only as the original local prototype.
- Clear-on-view hooks are installed at tmux hook index `90`, so re-sourcing the
  plugin updates the hook instead of appending duplicates.

## License

MIT. See [LICENSE](LICENSE).
