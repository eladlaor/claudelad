---
name: kb-sync
description: >
  Manage the Claude Code documentation KB sync routine — a cloud routine that merges
  each Claude Code release's doc changes into a local knowledge base repo and pushes.
  Create, inspect, pause, resume, and update the routine, detect prompt drift between
  the repo and the live trigger, or run a sync manually. Use when the user says
  "kb sync", "sync the claude code KB", "update my claude code docs", "install the
  docs sync routine", "is the KB sync running", "pause the KB sync", or asks why
  their Claude Code knowledge base is stale.
allowed-tools: Bash Read Edit Write WebFetch RemoteTrigger CronList CronCreate CronDelete AskUserQuestion
argument-hint: "install | status | sync-prompt | pause | resume | run-now | sync"
metadata:
  author: Elad Laor
  version: "0.1"
  category: developer-tools
  tags: claude-code docs knowledge-base routine automation sync
---

# Claude Code KB Sync

Keeps a local Claude Code documentation KB current without depending on any machine
being awake. A cloud routine fires when a new Claude Code version ships, merges the
changed official docs into the KB repo, and pushes. A `SessionStart` hook (shipped
with this plugin) pulls locally.

The user's request is: $ARGUMENTS

## Layout

| Path | Role |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/routine/SYNC_PROMPT.md` | The routine's prompt — source of truth, versioned in git |
| `${CLAUDE_PLUGIN_ROOT}/routine/ROUTING_TABLE.md` | Changelog bullet → KB file mapping |
| `$KB_REPO/claude_code/.docs-sync-state.json` | Watermark + trigger ID + prompt hash |

`KB_REPO` defaults to `~/Code/generic-docs` (override with `CLAUDE_CODE_KB_REPO`).

## Routing the request

Match `$ARGUMENTS` to one subcommand. Bare invocation with no argument → run `status`.

### `install`

Create the routine.

1. Read `SYNC_PROMPT.md` and `ROUTING_TABLE.md`. The routine prompt must be
   self-contained — inline the routing table into the prompt body you register,
   since the cloud run cannot read this plugin's files.
2. Create the trigger with `RemoteTrigger`, targeting the `generic-docs` repo.
   Prefer a **GitHub Release trigger on `anthropics/claude-code`**.
3. **Verify the trigger actually registered.** Watching a repo the user does not own
   may not be permitted. If it is rejected, say so plainly and offer the fallback:
   a daily schedule (`CronCreate`), which is safe because the prompt's step-2 version
   guard makes no-op runs free. Do not silently substitute one for the other.
4. Record the returned trigger ID, name, trigger type, and `sha256` of
   `SYNC_PROMPT.md` into the `routine` block of `.docs-sync-state.json`. Commit that
   state change to the KB repo.
5. Remind the user of the two manual steps from `docs/SETUP.md` that cannot be
   automated: authorizing the Claude GitHub App, and enabling **"Allow unrestricted
   branch pushes"** for `generic-docs` only.

Before creating anything, confirm `.docs-sync-state.json` exists. If not, offer to
seed it — ask for the starting version rather than guessing (`INDEX.md`'s
`**Latest version**` line is the best candidate).

### `status`

Report health, and check for drift.

1. `RemoteTrigger` / `CronList` the trigger ID from state. Report: exists, enabled,
   trigger type, cadence, last fire.
2. Report the sync watermark: `last_synced_version`, `last_synced_at`,
   `last_run_status`, any `skipped_versions`.
3. Fetch `https://code.claude.com/docs/en/changelog.md` and report how many versions
   the KB is behind. This is the number that actually matters.
4. **Drift check.** Compare three things:
   - `sha256` of the current `SYNC_PROMPT.md`
   - `prompt_sha` recorded in state
   - the prompt body on the live trigger

   Any mismatch → warn explicitly and name which pair diverged. Recommend
   `sync-prompt`.

Drift is the failure mode this subcommand exists for. A routine quietly running a
months-old prompt looks perfectly healthy from the outside.

### `sync-prompt`

Push the repo's current prompt to the live trigger.

1. Read `SYNC_PROMPT.md` + `ROUTING_TABLE.md`, compose the same self-contained body
   as `install`.
2. `RemoteTrigger update` the trigger's prompt.
3. Update `prompt_sha` in state, commit.
4. Show the user a diff summary of what changed in the prompt — they should know
   what they just deployed to an unattended agent.

### `pause` / `resume`

`RemoteTrigger update` with `enabled: false` / `enabled: true`. Confirm the new state
by reading it back; do not assume the write succeeded. On `pause`, note that KB
staleness will accumulate silently until resumed.

### `run-now`

Fire one sync immediately, outside the trigger. Useful after `sync-prompt` or to
clear a `skipped_versions` backlog. Report what the run did — including "nothing,
already current", which is the expected result most of the time.

### `sync`

Run the sync logic **locally**, in this session, against the local KB repo. Debug
path: no routine involved, no cloud.

Follow `SYNC_PROMPT.md` step by step, with the same hard constraints. Default to
stopping before `git commit` and showing the diff, unless the user explicitly asks
to commit. Requires `WebFetch(domain:code.claude.com)` permission in the KB repo's
settings — if it is missing, say so and point at `docs/SETUP.md`.

## Guard rails

These apply to every subcommand:

- **Never** modify anything outside `claude_code/` in the KB repo.
- **Never** touch `REMOTE_ROUTINES.md` — intentional pointer stub, owned elsewhere.
- **Never** force-push, rebase, or delete branches.
- The routine pushes straight to `main` by deliberate choice. Treat any request to
  widen its write scope beyond `claude_code/` as a change that needs the user's
  explicit go-ahead, not an implementation detail.
