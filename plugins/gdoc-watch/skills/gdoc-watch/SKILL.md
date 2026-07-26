---
name: gdoc-watch
description: >
  Keep a Google Doc in view for the current Claude Code session so you can ask
  questions about it while you edit, and get told what changed since you last asked.
  Reads the live doc on every prompt (pull-on-demand — no polling, no background
  watcher). Use when the user says "watch this doc", "gdoc watch", "keep an eye on
  this google doc", "what changed in the doc", "review my doc as I write", "advise me
  on this doc", or pastes a Google Docs URL and wants ongoing feedback while editing.
allowed-tools: Bash Read AskUserQuestion
argument-hint: "<google-doc-url-or-id> | status | changes | unwatch"
metadata:
  author: Elad Laor
  version: "1.0"
  category: productivity
  tags: google-docs gdoc watch advisor diff session gws
---

# Google Doc Watch

Makes a Google Doc visible to this session so the user can edit it in the browser and
ask you about it in the terminal. State is **per Claude Code session** (keyed on
`$CLAUDE_CODE_SESSION_ID`) — deliberately not in `CLAUDE.md`, because watching a doc is
a property of the conversation, not the project.

The user's request is: $ARGUMENTS

## How it works

Google Docs autosaves, so the server always holds what the user just typed. Every time
you need the doc you **fetch it fresh** with the helper script. There is no daemon, no
polling, and no background job — the read happens at prompt time, only when needed.

`SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/gdoc_state.sh"`

| Command | Purpose |
|---|---|
| `bash "$SCRIPT" watch <url-or-id>` | Set the session's active doc, take a baseline, print content |
| `bash "$SCRIPT" read` | Fetch current text and refresh the snapshot |
| `bash "$SCRIPT" read --no-snapshot` | Fetch without disturbing the baseline (peek) |
| `bash "$SCRIPT" diff` | Show what changed since the last look, then re-baseline |
| `bash "$SCRIPT" status` | Active doc, doc id, snapshot age |
| `bash "$SCRIPT" unwatch` | Clear this session's state |

Exit codes: `0` ok · `1` usage · `2` missing dependency · `3` no active doc · `4` API/auth error.

## Routing the request

**Argument is a Google Docs URL or a bare file ID** → run `watch`. Confirm with the doc
title and a one-line characterization of what's in it. Do not summarize the whole doc
unless asked.

**Argument is `status` / `changes` / `unwatch`** → run the matching subcommand.
`changes` maps to `diff`.

**No argument, and a doc is already active** → this is a question about the doc. Run
`diff` (it returns both the changes *and* re-baselines). Answer using the current text.

**No argument and no active doc** → ask for the doc URL. Do not guess.

## Answering questions about the doc

This is the main path. The user is editing in the browser and asking you things in the
terminal.

1. **Always fetch before answering.** Never answer from an earlier turn's copy — the
   user has almost certainly typed since then. Run `diff` (preferred: it gives you the
   delta and the fresh state in one call) or `read`.
2. **Lead with the change when there is one.** If `diff` reports changes, open with what
   moved — "you added two paragraphs under Pricing" — then answer the question. This is
   the reason the plugin exists; don't bury it.
3. **Say when nothing changed.** `NO CHANGES since last look` is useful information.
   State it in one clause and move on to the question.
4. **Be an advisor, not a summarizer.** The user can read their own doc. Give the
   judgment they asked for: what's weak, what's missing, what contradicts what. Point at
   specific text — quote the phrase you mean.
5. **Do not edit the doc.** This skill is read-only by design. If the user wants changes
   applied, hand off to the `projman-gdoc-edit` agent (edits existing docs via
   `gws docs batchUpdate`) and say that's what you're doing.

## Failure handling

- **Exit 4 with "authentication expired"** → `gws` OAuth has lapsed. Tell the user to
  run the `gws-reauth` skill, then retry. Do not attempt to re-auth inline.
- **Exit 3** → no active doc; ask for the URL.
- **Exit 2** → `gws` or `jq` missing. `gws` installs with
  `npm install -g @googleworkspace/cli`.
- **A 404 on a valid-looking ID** → the authenticated Google account probably lacks
  access to that doc. Say so plainly rather than retrying.

Never fall back to stale or partial content on an error — report the failure.

## Notes

- Diffs are computed from **local snapshots**, not the Drive revisions API. Google
  documents that `revisions.list` "might be incomplete for files with a large revision
  history, including frequently edited Google Docs" — which is exactly this use case.
  Snapshots are exact for "since I last asked".
- The doc is exported as `text/plain`, so formatting, comments, and suggestions are not
  visible. For structure-aware work (headings, styles) use
  `gws docs documents get --params '{"documentId":"<ID>"}'` and strip the leading
  `Using keyring backend: keyring` line before parsing.
- Multiple sessions can watch different docs simultaneously without interfering; state
  is namespaced per session id.
