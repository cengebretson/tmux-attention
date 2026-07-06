# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `README.md` for what the plugin does, its parts (TPM plugin, CLI, agent hooks), and setup.

## Tests

Run the integration suite (spins up an isolated tmux server):

```bash
tests/check.sh
```

## Pre-commit

`.pre-commit-config.yaml` runs ShellCheck over the scripts/entry/harness and then
the integration suite. Enable it once with `pre-commit install` (requires
[pre-commit](https://pre-commit.com) and `shellcheck` on PATH).

## Versioning and releases

SemVer. The current version lives in `VERSION` and is printable via `tmux-attention version` (read by `scripts/tmux-attention`). Notes are tracked in a Keep a Changelog `CHANGELOG.md`.

**Keep the changelog current:** every user-facing change adds a bullet to the `## [Unreleased]` section of `CHANGELOG.md` in the same commit that makes the change. `git release` promotes and dates that section but does **not** author the notes — write them as work lands.

Cut a release with the maintainer's `git release <x.y.z>` helper (bumps `VERSION`, promotes the changelog `[Unreleased]` section, runs `tests/check.sh`, commits, and tags) — or do those steps by hand. Pushing a `v*` tag triggers `.github/workflows/release.yml`, which re-runs the checks, verifies the tag matches `VERSION`, and publishes a GitHub release from that version's changelog section.
