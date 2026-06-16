# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-06-15

### Fixed

- Installed hook commands now use a portable `"$HOME"`-relative CLI path when the
  plugin lives under `$HOME`, instead of an absolute machine-specific path, so a
  tracked `settings.json` / `hooks.json` works across machines. Both hook runners
  execute the command through a shell (Claude Code via the user's shell, Codex
  via `$SHELL -lc`), so `$HOME` expands at run time. Paths outside `$HOME` keep
  their absolute form. Re-run `setup` (or `install-hooks`) to rewrite existing
  entries.

## [0.2.0] - 2026-06-15

### Added

- `tmux-attention doctor --probe` sets, renders, and clears a test marker from
  inside tmux to confirm the icon round-trips through the status line.

### Changed

- `setup` now reminds you to restart Claude Code / Codex (agent hooks load at
  session start), suggests `doctor --probe` as a final check, and documents the
  custom-theme path (`--status-line none` plus a manual
  `#{E:@tmux_attention_status}`) in its `--help` output.

### Fixed

- Hook status detection (`install-hooks --status`, used by `doctor`) now matches
  on the stable `tmux-attention:` marker comment instead of the full command
  string, so it no longer falsely reports "not installed" when the plugin's
  absolute CLI path differs from the one recorded in the config. This makes
  status consistent with the already marker-based uninstall.

## [0.1.1] - 2026-06-15

### Changed

- The version now lives in a `VERSION` file (read by `tmux-attention version`) instead of a hardcoded constant.

### Added

- A tag-triggered release workflow that publishes a GitHub release from the changelog.

## [0.1.0] - 2026-06-14

### Added

- TPM plugin (`tmux-attention.tmux`) that defines options, status rendering,
  configurable icons, and clear-on-view hooks at the stable hook index `90`.
- Portable POSIX CLI (`scripts/tmux-attention`) with `input`, `blocked`,
  `review`, `done`, and `clear` states, plus `status-format`,
  `catppuccin-format`, `doctor`, `version`, and `help` subcommands.
- `scripts/install-hooks` to install, uninstall, and report status of Claude
  Code and Codex agent hooks, with timestamped backups and managed markers so
  only this plugin's entries are touched.
- `scripts/setup` to wire hooks and a managed `~/.tmux.conf` status snippet in
  one step, with `--status-line`, `--tmux-config`, `--no-hooks`, `--reload`,
  and `--uninstall` options.
- Integration test suite (`tests/check.sh`) that runs against an isolated tmux
  server and a GitHub Actions CI workflow running ShellCheck and the tests.
- Documentation: `README.md` and `docs/hooks.md`.

[Unreleased]: https://github.com/cengebretson/tmux-attention/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/cengebretson/tmux-attention/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/cengebretson/tmux-attention/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/cengebretson/tmux-attention/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/cengebretson/tmux-attention/releases/tag/v0.1.0
