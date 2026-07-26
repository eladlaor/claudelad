# gdoc-watch

Turns Claude Code into an **advisor over a Google Doc you're actively editing**. You
write in the browser; you ask questions in the terminal. Claude always sees the current
state of the doc, and tells you what changed since you last asked.

```
/gdoc-watch https://docs.google.com/document/d/<ID>/edit
```

Then just talk:

> *"is the pricing section convincing yet?"*
> → **CHANGED since 08:41: +6 / -1 lines** — you added the tiered table.
>   The tiers read clearly, but "custom" has no anchor price, so a reader can't
>   self-qualify. The paragraph above still promises "three plans" — now there are four.

## Why it isn't a watcher

The name is aspirational; the mechanism is deliberately the opposite of a watcher.
There is **no daemon, no polling, no background job**. Google Docs autosaves, so the
server already holds whatever you typed a second ago — the doc is fetched *at the moment
you prompt*, and only then. Nothing runs, and no tokens are spent, between your
questions.

## Session-scoped, not project-scoped

The active doc lives under `~/.claude/gdoc-watch/$CLAUDE_CODE_SESSION_ID/`, not in
`CLAUDE.md`. Watching a doc is a property of *this conversation*, not of the repository
you happen to be in. Two sessions can watch two different docs at once without
interfering, and the state disappears with the session.

## What changed since I last asked

Each fetch stores a plain-text snapshot and diffs the next fetch against it, so the
delta is scoped to *your attention*, not to wall-clock time or to Google's revision
boundaries.

Deliberately **not** built on the Drive `revisions` API — Google documents that
`revisions.list` "might be incomplete for files with a large revision history,
including frequently edited Google Docs," which is precisely a doc you are typing into.
Local snapshots are exact for this question.

## Commands

| Command | Does |
|---|---|
| `/gdoc-watch <url\|id>` | Set the session's doc, take a baseline |
| `/gdoc-watch changes` | What changed since the last look |
| `/gdoc-watch status` | Active doc + snapshot age |
| `/gdoc-watch unwatch` | Clear session state |

Once a doc is active you don't need the command — ask about the doc in plain language
and the skill refetches before answering.

The script is usable directly too:

```bash
SCRIPT=~/.claude/plugins/.../gdoc-watch/scripts/gdoc_state.sh
bash "$SCRIPT" watch <url>
bash "$SCRIPT" diff                # changes + re-baseline
bash "$SCRIPT" read --no-snapshot  # peek without disturbing the baseline
bash "$SCRIPT" read --meta         # include modifiedTime / lastModifyingUser
```

Exit codes: `0` ok · `1` usage · `2` missing dep · `3` no active doc · `4` API/auth error.

## Requirements

- [`gws`](https://github.com/googleworkspace/google-workspace-cli) on PATH —
  `npm install -g @googleworkspace/cli`, authenticated via `gws auth login`
- `jq`

If a call fails with **exit 4 / "authentication expired"**, the OAuth token has lapsed —
run the `gws-reauth` skill and retry.

## Scope

Read-only, by design. The doc is exported as `text/plain`, so comments, suggestions, and
formatting are not visible. To *edit* a doc, use the `sysdesign-gdocs` agent
(`gws docs batchUpdate`); to *create* one from markdown, use `md-to-gdoc`.
