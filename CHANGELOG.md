# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/cengebretson/tmux-attention/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cengebretson/tmux-attention/releases/tag/v0.1.0
