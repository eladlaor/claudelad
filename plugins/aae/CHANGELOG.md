# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `aae` plugin with a local marketplace manifest, installable from this directory.
- `aae-guide` agent — the MongoDB Atlas Agent Engine specialist, carried over from
  the user-scoped `eng-atlas-agent-engine` agent and renamed.
- `aae-docs-watch` skill for checking and explaining AAE documentation changes on demand.
- `aae-docs-watch.sh` watcher that detects documentation changes by SHA-256 content
  hashing of every page's `.md` rendering, with `--quick` (inventory only) and
  `--full` (per-page content) modes, per-page unified diffs, and a JSON report.
- `SessionStart` hook that reports pending documentation changes once per result,
  to both the user and Claude, and then marks the result acknowledged.
- `install-schedule.sh` to manage a launchd job for periodic full crawls, since
  Claude Code plugins cannot declare scheduled work themselves.
- `install-ae-shortcut.sh` to create an `ae` shortcut for the `agentengine` CLI as a
  symlink on `PATH`, so it resolves in non-interactive shells where a shell alias
  would not — making it usable from Claude Code and Codex, not only at an
  interactive prompt. Detects an existing `ae` on `PATH`, at the link location, or
  declared as an alias or function in a shell rc file, and prompts for confirmation
  before shadowing it; a collision with no terminal available is an error rather
  than a silent overwrite. `uninstall` refuses to remove anything that is not its
  own symlink.

- `aae-delete-agent` skill — complete teardown of a single Atlas Agent Engine agent:
  workspace, sessions, workspace-scoped secrets, Atlas database user, monorepo
  manifest entry and local folder. Opens with a read-only inventory and a single
  explicit confirmation, orders remote teardown before local so the workspace is
  never stranded, and refuses to delete a shared Atlas database user while other
  agents in the project still depend on it.
- `aae-add-agent` skill — adds one agent to an existing Atlas Agent Engine monorepo,
  since `agentengine create` only scaffolds whole new projects. Scaffolds in a scratch
  directory (or copies a sibling with `--from`, excluding its workspace binding and
  local secrets), transplants the agent folder, appends it to the root `agent.yaml`,
  and optionally registers a single workspace from the agent's own directory,
  verifying that no existing workspace changed.
- `knowledge/specs/BEHAVIOR_SPEC.md` — the v1.0 behaviour spec. Fixes scope at two
  tiers (public docs plus CLI releases) for Claude Code only, states the watcher exit
  codes, state layout and SessionStart hook output as stable contracts, and defines
  twelve acceptance criteria of which five are already verified.

### Changed

- `AAE_WATCH_DESIGN.md` now describes private knowledge sources as a single optional,
  user-configured tier rather than naming specific trackers, spaces, or channels. The
  plugin ships no source list and no queries; the watcher is usable by any Atlas Agent
  Engine user, not only within one organization.
