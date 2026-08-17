# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Resolve the script through symlinks before locating files beside it.
  Symlinking the CLI onto `PATH` is a normal install, but `dirname "$0"` then
  pointed at the link's directory, so `version` reported `unknown` and
  `shell-init` emitted the symlink's path instead of the plugin's. Both now
  follow the link, including a chain of them.

## [0.8.0] - 2026-08-16

### Added

- `shell-init <fish|bash|zsh> [command...]`, emitting the shell integration that
  makes pane ownership usable. Ownership shipped in 0.7.0 with no way to drive
  it: the owner id has to reach the agent's environment at launch, and only the
  shell can put it there — a hook reading it back off the pane would let a dead
  agent's late hook match the pane's current owner, which is the case ownership
  exists to catch.
- The two helpers (`tmux_attention_claim`, `tmux_attention_disown`) are always
  emitted; a full wrapper only for commands named explicitly. Wrapping is opt-in
  because replacing a command someone already wraps would silently drop what
  their version did — those users compose the helpers into their own wrapper.
  Wrappers are fail-safe: outside tmux, or with the plugin missing, they run the
  command unchanged and preserve its exit status.

## [0.7.0] - 2026-08-16

### Added

- Optional pane ownership, guarding against stale markers. `claim --owner <id>`
  stamps a pane and clears any marker it inherited; a launcher hands the same id
  to the agent it starts, via `--owner` or `TMUX_ATTENTION_OWNER`. A write whose
  id disagrees with the pane's is refused, which is what stops a dead agent's
  late hook — or the previous occupant of a recycled pane — from leaving a
  marker that looks live. `disown` removes the stamp.
- `@agent_pane_attention_verified` records whether a write matched the pane
  owner, and `get --format json` reports it alongside `owner`. The flag is
  cleared by `disown`, since verification cannot outlive the stamp that granted
  it.

Ownership is opt-in and only a *mismatch* refuses: a caller presenting no id
still writes, recorded unverified, so ad-hoc panes and manual use are
unchanged. It catches staleness and accidents, not a determined writer — anyone
who can run tmux can set the option too.

## [0.6.2] - 2026-08-11

### Added

- Add an idempotent `turn-active` transition and generated Codex `PreToolUse`
  hook so automatic continuations restore working context after an intermediate
  `Stop` event.

## [0.6.1] - 2026-08-06

### Added

- Add `turn-done`, an atomic completed-turn transition that clears pane-local
  active context and sets a `done` marker with response-ready metadata.

### Changed

- Generated Claude Code and Codex `Stop` hooks now call `turn-done`, so both
  surfaces show the same check marker when an agent response is ready.

## [0.6.0] - 2026-08-03

### Changed

- Make attention and active-agent context authoritative per pane, allowing
  multiple agents to work independently in one window. Existing window options
  remain as derived summaries for status integrations, using
  `input > blocked > review > done > working` priority.
- Clear-on-view now clears only the pane actually viewed and recomputes the
  window summary, preserving attention in other panes.
- `get` and `list` now report pane-scoped state and pane identity.

## [0.5.4] - 2026-08-03

### Added

- Add a configurable working-agent icon (`@tmux_attention_icon_working`) and
  `@tmux_attention_tab_icon`, a compact format that prioritizes attention,
  then an active agent turn, for replacing rather than prefixing tab numbers.

## [0.5.3] - 2026-07-24

### Changed

- Active context now renders only the derived project label. Prompt hooks no
  longer send an agent name, and `turn-start` no longer requires `--agent`.

## [0.5.2] - 2026-07-24

### Added

- Agent turn context for status modules. Claude Code and Codex prompt hooks now
  call `turn-start`, which records the agent and derives the project from the
  pane's Git branch, repository, or working directory. Stop hooks call
  `turn-stop`. The `@tmux_attention_context` format renders
  `<project> · <agent>` while a turn is active and falls back to the current
  pane directory otherwise.
- `context-format` prints the reusable agent-context format token, and
  `turn-start --project` supports an explicit project label when automatic
  derivation is not appropriate.

## [0.5.1] - 2026-07-21

### Fixed

- `clear-after-delay` no longer leaks a non-zero exit status when its final
  `run-shell -b` scheduling call transiently fails to reach the tmux server.
  The script is fired by the `client-attached`, `client-session-changed`, and
  `after-select-window` hooks, precisely the attach/detach/session-change
  moments when a backgrounded tmux command can momentarily fail; that failure
  became the script's exit status and surfaced as
  `'"…/clear-after-delay" "@N"' returned 1`. The scheduling call is now guarded
  (a failed schedule is not actionable, since the next focus event reschedules).

## [0.5.0] - 2026-07-12

### Changed

- Hot-path tmux calls are now batched into single tmux invocations: the CLI
  sets or clears all four marker options in one call (previously four) and
  reads `session_attached`/`window_active` in one call; `clear-after-delay`
  reads the marker state and timestamp in one call and its scheduled clear
  removes all four options in one call; the plugin applies its load-time
  defaults and hooks in one call. Behavior is unchanged.
- `setup` now uses a shared `strip_managed_block` helper for the backup +
  managed-block-strip logic previously duplicated between `write_status_snippet`
  and `remove_status_snippet` (no behavior change).

### Fixed

- `--source` and `--reason` now reject values containing a tab or newline
  (exit 2), since both are stored as tab-separated fields elsewhere (`list`'s
  text and JSON output); a control character in either could previously
  misalign downstream columns.

## [0.4.0] - 2026-07-12

### Fixed

- `install-hooks` now parses arguments in any order, so
  `install-hooks claude --uninstall` uninstalls instead of silently installing;
  unknown or extra arguments now error with exit 2.
- `install-hooks --uninstall` no longer creates or rewrites hook config files
  that have nothing to remove: a missing file stays missing (previously it was
  created with empty hooks), and a config without managed entries is no longer
  reformatted or backed up.
- `tmux-attention doctor` now propagates the doctor check's exit status instead
  of always exiting 0.
- `tmux-attention --help` now documents the `--source` / `--reason` flags and
  the full event list; the README documents the `blocked`, `stop_failure`,
  `hook_failure`, `review_required`, and `needs_review` event mappings; the
  `CODEX_HOME` default for the Codex hooks path is documented in
  `install-hooks --help` and docs/hooks.md.

### Removed

- The unused, undocumented `@tmux_attention_cli` tmux option is no longer set
  by the plugin (nothing read it).

## [0.3.2] - 2026-07-06

### Fixed

- The delayed clear-on-view now clears `@agent_attention_source`,
  `@agent_attention_reason`, and `@agent_attention_updated_at` along with the
  marker, matching the CLI's `clear`, so no stale metadata survives an
  auto-clear.
- The delayed clear also compares `@agent_attention_updated_at`, so a marker
  re-set with the same state during the delay window is no longer cleared
  early.
- Plugin defaults now use tmux's set-if-unset option semantics instead of
  probing missing user options, avoiding `invalid option` startup messages.

### Added

- Pre-commit config (`.pre-commit-config.yaml`) running ShellCheck and the
  integration tests; enable with `pre-commit install`.

## [0.3.1] - 2026-06-24

### Fixed

- `@tmux_attention_clear_on_view off` now also suppresses the CLI's post-set
  auto-clear on the active window, so a marker set on the window you are viewing
  persists until cleared explicitly. Previously only the focus/select hooks
  honored the opt-out.

## [0.3.0] - 2026-06-23

### Added

- `tmux-attention` state writes now accept `--target` / `-t` to mark another
  tmux pane or window without relying on `TMUX_PANE`.
- Added `tmux-attention get` and `tmux-attention list` with text and JSON output
  for scripts, pickers, and dashboards.
- Added optional marker metadata via `--source` and `--reason`, stored alongside
  `@agent_attention` as window options with an update timestamp.
- Added `tmux-attention event <event>` as a small adapter for normalized event
  streams such as `approval_required`, `task_complete`, and `session_started`.

## [0.2.4] - 2026-06-18

### Fixed

- Delayed clear timers no longer emit a tmux `returned 1` message when the
  marker changed before the timer fired.

## [0.2.3] - 2026-06-17

### Fixed

- Delayed clear timers now only clear the marker state they observed when they
  were scheduled, so an older timer cannot erase a newer attention state.
- README release guidance now points at the `VERSION` file instead of the old
  hardcoded version constant, and documents that markers are window-scoped.

## [0.2.2] - 2026-06-16

### Fixed

- Clear-on-view now also fires when a window is reached via `switch-client`
  (e.g. jumping with tmux-fzf-jump), which previously left the marker stuck
  because only `after-select-window` and `client-attached` were hooked. Added
  `client-session-changed` (session switches) and `pane-focus-in` (any pane
  focus; needs `focus-events on`) at the same stable index 90.
- `clear-after-delay` no longer spawns a `sleep` when the target window has no
  marker, so the now-frequent focus/select hooks stay cheap.

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

[Unreleased]: https://github.com/cengebretson/tmux-attention/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/cengebretson/tmux-attention/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/cengebretson/tmux-attention/compare/v0.6.2...v0.7.0
[0.6.2]: https://github.com/cengebretson/tmux-attention/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/cengebretson/tmux-attention/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/cengebretson/tmux-attention/compare/v0.5.4...v0.6.0
[0.5.4]: https://github.com/cengebretson/tmux-attention/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/cengebretson/tmux-attention/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/cengebretson/tmux-attention/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/cengebretson/tmux-attention/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/cengebretson/tmux-attention/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/cengebretson/tmux-attention/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/cengebretson/tmux-attention/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/cengebretson/tmux-attention/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/cengebretson/tmux-attention/compare/v0.2.4...v0.3.0
[0.2.4]: https://github.com/cengebretson/tmux-attention/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/cengebretson/tmux-attention/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/cengebretson/tmux-attention/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/cengebretson/tmux-attention/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/cengebretson/tmux-attention/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/cengebretson/tmux-attention/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/cengebretson/tmux-attention/releases/tag/v0.1.0
