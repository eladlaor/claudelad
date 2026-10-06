# aae

MongoDB Atlas Agent Engine is in Public Preview. Its docs change weekly, its CLI shipped five releases in six days, and its own limitations page warns that formats may change without a backward-compatible migration path.

The practical failure mode isn't missing an announcement. It's an agent answering confidently from a model of the product that was correct last week.

This plugin keeps that from happening: a specialist agent for Atlas Agent Engine, a watcher that detects when the documentation actually changes, and an `ae` shortcut for the `agentengine` CLI.

## When Is This Useful?

- **Asking anything about Atlas Agent Engine**: the `aae-guide` agent knows the runtime model, the agent contract, the config surface, and the failure modes — and verifies against live docs rather than recalling
- **Staying current**: a nightly watcher tells you which documentation pages changed, with per-page diffs
- **Typing less**: `ae deploy list` instead of `agentengine deploy list`
- **Tearing an agent down cleanly**: `aae-delete-agent` removes the workspace, its sessions, its secrets and its local folder in the one order that works — there is no single CLI command for this, and `workspace delete` alone leaves most of it behind

## Install

```
/plugin install aae@claudelad
```

## Setup

Record a documentation baseline once:

```
${CLAUDE_PLUGIN_ROOT}/scripts/aae-docs-watch.sh --full
```

The first run reports no changes by design — there is nothing to compare against until a baseline exists.

Optional, for checks that run while Claude Code is closed:

```
${CLAUDE_PLUGIN_ROOT}/scripts/install-schedule.sh install      # daily 09:00 via launchd
```

Optional, to type `ae` instead of `agentengine`:

```
${CLAUDE_PLUGIN_ROOT}/scripts/install-ae-shortcut.sh install
```

## Uninstall

```
/plugin uninstall aae@claudelad
```

The launchd job and the `ae` shortcut are installed separately and are not removed by uninstalling the plugin. Remove them with `install-schedule.sh uninstall` and `install-ae-shortcut.sh uninstall`.

## How It Works

**Change detection by content hashing.** The docs site publishes a machine-readable page inventory at `docs/agentengine/llms.txt` (196 pages), and appending `.md` to any docs URL returns clean markdown whose bytes are stable across repeated fetches. So the watcher stores a SHA-256 per page; a hash that moves means the page genuinely changed.

The obvious cheaper approach is unavailable: those responses carry **no `Last-Modified` and no `ETag`**, and no sitemap publishes a `lastmod` for them. Conditional requests cannot work, so hashing is the only dependable method rather than an over-engineered one. A full crawl is about 40 seconds and 2.4 MB; `--quick` fetches the inventory alone in about a second and detects pages added, removed, or retitled.

**The `ae` shortcut is a symlink, not a shell alias** — deliberately. An alias is interactive-only and is not inherited by non-interactive shells, which is exactly where Claude Code and Codex run commands. An alias would work when you type it and fail for every agent-issued command. The installer refuses to shadow an existing `ae` without asking, and checks PATH, the link location, and your shell rc files, because an alias beats a PATH symlink in interactive shells.

See [knowledge/usage_guides/USER_GUIDE.md](knowledge/usage_guides/USER_GUIDE.md) for the full guide, [knowledge/plans/AAE_WATCH_DESIGN.md](knowledge/plans/AAE_WATCH_DESIGN.md) for the design of the broader change-watcher (CLI release detection, optional private sources, Codex parity), and [knowledge/CONTRIBUTION_IDEAS.md](knowledge/CONTRIBUTION_IDEAS.md) for things worth building on top of Atlas Agent Engine.
