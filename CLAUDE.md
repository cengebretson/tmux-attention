# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `README.md` for what the plugin does, its parts (TPM plugin, CLI, agent hooks), and setup.

## Layout

- `tmux-attention.tmux` — TPM entry: sets default `@tmux_attention_*` options, exports
  the `@tmux_attention_status` format, and installs clear-on-view hooks (all at index
  `[90]` on `after-select-window` / `client-attached` / `client-session-changed` /
  `pane-focus-in`, so re-sourcing updates in place).
- `scripts/tmux-attention` — POSIX-sh CLI: sets/clears the `@agent_attention` window
  state (`input`, `blocked`, `review`, `done`), maps agent event names to states,
  `get`/`list` in text or JSON, prints `status-format`/`catppuccin-format` snippets,
  `doctor [--probe]`, `version`.
- `scripts/clear-after-delay` — schedules the delayed marker clear. No-ops when the
  window has no marker or `@tmux_attention_clear_on_view` is off; compares
  `@agent_attention_updated_at` so a marker re-set during the delay survives; clears
  all four `@agent_attention*` options together (matching the CLI's `clear`).
- `scripts/setup` — installs agent hooks (via `install-hooks`) and a managed,
  marker-delimited status snippet in `~/.tmux.conf` (timestamped backups, pruned to five).
- `scripts/install-hooks` — installs/uninstalls/reports Claude Code and Codex hook
  entries (requires python3; entries carry a `# tmux-attention:` marker comment so
  install is idempotent and uninstall is path-independent).
- `docs/hooks.md` — agent hook reference; `docs/future-orc-integration.md` — design notes.

## Tests

Run the integration suite (spins up an isolated tmux server):

```bash
tests/check.sh
```

CI (`.github/workflows/ci.yml`) runs ShellCheck over the scripts/entry/harness and
then the same suite on every push and pull request.

## Pre-commit

`.pre-commit-config.yaml` runs ShellCheck over the scripts/entry/harness and then
the integration suite. Enable it once with `pre-commit install` (requires
[pre-commit](https://pre-commit.com) and `shellcheck` on PATH).

## Versioning and releases

SemVer. The current version lives in `VERSION` and is printable via `tmux-attention version` (read by `scripts/tmux-attention`). Notes are tracked in a Keep a Changelog `CHANGELOG.md`.

**Keep the changelog current:** every user-facing change adds a bullet to the `## [Unreleased]` section of `CHANGELOG.md` in the same commit that makes the change. `git release` promotes and dates that section but does **not** author the notes — write them as work lands.

Cut a release with the maintainer's `git release <x.y.z>` helper (bumps `VERSION`, promotes the changelog `[Unreleased]` section, runs `tests/check.sh`, commits, and tags) — or do those steps by hand. Pushing a `v*` tag triggers `.github/workflows/release.yml`, which re-runs the checks, verifies the tag matches `VERSION`, and publishes a GitHub release from that version's changelog section.
