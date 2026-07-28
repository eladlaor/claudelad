# claude-code-kb-sync

Keep a local Claude Code documentation knowledge base current automatically. A cloud routine merges each release's doc changes into your KB repo and pushes; a SessionStart hook pulls it locally.

## Table of Contents

- [Why This Plugin?](#why-this-plugin)
- [How It Works](#how-it-works)
- [Install](#install)
- [Setup](#setup)
- [Usage](#usage)
- [Safety](#safety)
- [Uninstall](#uninstall)

## Why This Plugin?

Claude Code ships a release roughly every day. If you keep your own distilled notes
on how it works — settings keys, hook events, permission syntax — they start rotting
the moment you write them, and you find out only when Claude confidently tells you
something that was true three months ago.

Re-reading the official docs on every question is the usual fallback, but it burns
tokens on pages that haven't changed and gives you no durable artifact. A local KB
solves that, right up until it goes stale.

This closes the loop. When a new version ships, a cloud routine reads the changelog,
works out which of your KB files the change actually touches, re-fetches only those
official pages, merges the delta into your prose without rewriting your documents,
and pushes one revertable commit. Your laptop can be closed. Locally, a
`SessionStart` hook fast-forwards the repo so every new session starts current.

The changelog is what makes this cheap: `code.claude.com` publishes no per-page
`last-modified`, so the alternative is re-reading every page every time. Routing
changelog bullets to files means a typical run fetches one or two pages, and a run
with no doc-visible changes costs nothing at all.

## How It Works

```
anthropics/claude-code release
        │
        ▼
  cloud routine  ──► read state ──► changelog delta ──► route to files
        │                                                     │
        │                          fetch only affected pages ─┘
        │                                    │
        │                          merge surgically, one commit
        ▼
   git push main ──────────────────────────────┐
                                               ▼
                          SessionStart hook: git pull --ff-only
```

State lives in `claude_code/.docs-sync-state.json` — the version watermark, the
trigger ID, and a hash of the deployed prompt. The routine is a cold start with no
memory; the state file and git history are the only continuity.

## Install

```
/plugin install claude-code-kb-sync@claudelad
```

## Setup

Requires a one-time GitHub authorization and routine creation — see
[docs/SETUP.md](docs/SETUP.md).

## Usage

```
/claude-code-kb-sync:kb-sync <subcommand>
```

| Subcommand | Purpose |
|---|---|
| `install` | Create the routine, record its ID into the state file |
| `status` | Trigger health, how many versions behind, **prompt drift check** |
| `sync-prompt` | Deploy the repo's `SYNC_PROMPT.md` to the live routine |
| `pause` / `resume` | Disable / re-enable the routine |
| `run-now` | Fire one sync immediately |
| `sync` | Run the sync locally in-session (debug, no cloud) |

**Example:** `/claude-code-kb-sync:kb-sync status` → `enabled · release trigger ·
last synced v2.1.220 (2d ago) · 3 versions behind · prompt drift: none`.

`status` is the one worth running periodically. A routine executing a months-old
prompt reports as perfectly healthy — drift detection is the only thing that
catches it.

## Safety

The routine pushes directly to `main` by design, so its blast radius is bounded
elsewhere:

- Writes confined to `claude_code/`; any other path aborts the run.
- One commit per run — `git revert` undoes a bad sync entirely.
- Never rebases, force-pushes, or deletes branches.
- Unrestricted-push should be enabled for the KB repo alone.
- Changelog items whose effect on documented behavior is unclear are skipped and
  listed in the commit body, never invented.

The local hook is equally conservative: `--ff-only` (never merges), detached so it
cannot stall startup, and a no-op whenever `claude_code/` has uncommitted changes.

## Uninstall

```
/claude-code-kb-sync:kb-sync pause
/plugin uninstall claude-code-kb-sync@claudelad
```

Pause first — uninstalling the plugin removes the hook and the skill, but the cloud
routine keeps running.
