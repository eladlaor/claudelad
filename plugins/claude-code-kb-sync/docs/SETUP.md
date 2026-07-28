# Setup

Two steps cannot be automated — they are browser OAuth consent flows. Everything
else is handled by `/claude-code-kb-sync:kb-sync install`.

## Table of Contents

- [Prerequisites](#prerequisites)
- [1. Prepare the KB repo](#1-prepare-the-kb-repo)
- [2. Manual: authorize GitHub](#2-manual-authorize-github)
- [3. Install the routine](#3-install-the-routine)
- [4. Verify](#4-verify)
- [Configuration](#configuration)
- [Maintenance](#maintenance)

## Prerequisites

- A git repo holding the KB, with a `claude_code/` directory of Markdown docs.
- Each KB file ends with a `**Official docs**: https://code.claude.com/docs/en/<slug>`
  footer. The routine uses this as its page-to-file index.
- Claude Code with routines available on your account.

## 1. Prepare the KB repo

**Commit any outstanding work first.** The routine pushes to this repo; an
uncommitted tree guarantees a collision on the first sync.

Create the state file at `claude_code/.docs-sync-state.json`:

```json
{
  "last_synced_version": "2.1.202",
  "last_synced_at": null,
  "last_run_status": "seed",
  "files_touched": [],
  "skipped_versions": [],
  "routine": {}
}
```

Set `last_synced_version` to the version your KB currently reflects — the
`**Latest version**` line at the bottom of `INDEX.md` is usually right. Everything
after it gets backfilled, 15 versions per run.

Add `WebFetch(domain:code.claude.com)` to the KB repo's
`.claude/settings.local.json` under `permissions.allow` (append — do not replace the
existing list). Needed for the local `sync` debug path.

## 2. Manual: authorize GitHub

Neither step can be scripted.

**Install the Claude GitHub App** and grant it access to the KB repo. Run
`/web-setup` in Claude Code, or authorize during routine creation.

**Enable "Allow unrestricted branch pushes" — for the KB repo only.** By default a
routine can push only to `claude/`-prefixed branches. This plugin's routine commits
straight to `main`, which requires the toggle.

> Scope it to the one repo. This setting is what turns a bad routine run into a bad
> push, and it should never be on for a repo whose history you cannot casually
> revert. One commit per run, restricted to `claude_code/`, is what keeps that
> recoverable with a single `git revert`.

## 3. Install the routine

```
/claude-code-kb-sync:kb-sync install
```

Creates the trigger, inlines the prompt and routing table, and records the trigger
ID into the state file.

It attempts a **GitHub Release trigger on `anthropics/claude-code`**. That repo is
not yours, and whether a routine may watch a third-party repo is not guaranteed. If
it is rejected, the skill offers a **daily schedule** instead — equivalent in
practice, because the prompt exits immediately when no new version exists.

## 4. Verify

```
/claude-code-kb-sync:kb-sync status
```

Expect: trigger exists and is enabled, watermark matches your seed, and a report of
how many versions the KB is behind.

Then confirm the routine actually fires. `anthropics/claude-code` releases roughly
daily, so a real firing should appear within 24–48h. **If nothing fires in 48h, the
trigger is not working** — switch to the daily schedule. A trigger that never fires
is the failure mode to watch for, because it looks identical to "no new versions."

For an immediate end-to-end test, `run-now`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_CODE_KB_REPO` | `~/Code/generic-docs` | KB repo root |
| `CLAUDE_CODE_KB_SUBDIR` | `claude_code` | KB directory within the repo |
| `CLAUDE_CODE_KB_LOG` | `~/.claude/kb-sync-pull.log` | SessionStart pull log |

## Maintenance

**After editing `SYNC_PROMPT.md`, run `sync-prompt`.** Editing the repo copy does
not change what the cloud runs. `status` warns when they diverge — this is the
plugin's most important check, since a routine running a stale prompt looks healthy
from every other angle.

**Watch `INDEX.md` size.** It accumulates a changelog block per run. Past ~600
lines, split history into `INDEX_HISTORY.md`; the routine reads only the Document
Map and topmost block, but the file still has to be opened.

**Check the pull log** at `~/.claude/kb-sync-pull.log` if the local KB seems stale.
The hook skips silently when `claude_code/` has uncommitted changes — deliberate, so
it never clobbers in-flight edits, but it means local edits stop updates until
committed.
