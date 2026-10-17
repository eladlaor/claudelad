---
name: archive-session
description: Hide Claude Code sessions from the /resume picker without deleting them from disk, and restore them later. Use when the user says "archive session", "archive sessions", "hide session", "remove from resume list", "clean up my session list", "declutter /resume", "too many sessions in the list", "unarchive session", "restore session", or wants to prune the resume picker while keeping transcripts. Also protects old transcripts from Claude Code's automatic retention cleanup.
---

Archive Claude Code session transcripts out of the resume picker, keeping every byte on disk.

## How this works

The resume picker enumerates `~/.claude/projects/<project-slug>/*.jsonl` — one file per
session. There is NO built-in slash command to hide a session. Moving the transcript out of
that directory removes it from the picker; moving it back restores it. Nothing is deleted.

Archive destination: `~/.claude/archived-sessions/<project-slug>/`.

Side benefit: Claude Code auto-deletes old transcripts in `projects/` per its retention
setting (`cleanupPeriodDays`). Archived transcripts sit outside that path and survive.

All work is done by `${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh`. Run it — do not hand-roll `mv` commands.

## Instructions

Execute these steps. Do not just explain them.

### 1. Determine the project scope

Sessions are grouped by the directory the session was LAUNCHED from, slugified (`/` and `.`
both become `-`). The script defaults to the current working directory's slug.

- To act on a different project, set `PROJECT_SLUG=<slug>`.
- To see all projects and their session counts: `${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh projects`

### 2. List sessions so the user can choose

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh list
```

Output columns: live-marker, session id, last-modified, size, first user prompt. The first
prompt is what makes an opaque UUID identifiable — always show this list before archiving.

A leading `*` marks a LIVE session (written within the last 180s). Archiving it is refused.

### 3. Archive the chosen sessions

Accepts **either a session name or an id**, space-separated. Prefer the name — it is what the
user actually remembers.

- **By name** (set via `/rename`, stored as `customTitle` in the transcript): matching is
  case-insensitive and ignores spaces, hyphens and underscores, so `'missing key'`,
  `missing-key` and `Missing_Key` all find the same session. Quote names containing spaces.
- **By id**: a full UUID or any unambiguous prefix (8 chars is plenty).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh archive 'missing key'
${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh archive 011df376 'tidy pelican'
```

If a name matches several sessions, the script refuses and prints each candidate with its id
and full name. Re-run with a longer, more distinctive fragment (`'missing key tidy'`) or the
id. Never guess which one the user meant.

Pass the current session's id as `SELF_SESSION_ID` when it is known (for a background job it
is the basename of `$CLAUDE_JOB_DIR`), as a second guard on top of the mtime check:

```bash
SELF_SESSION_ID=1a0e7cd7 ${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh archive 011df376
```

### 4. Restoring

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh restore 011df376
```

The session reappears in the picker on the next `/resume`.

## Critical constraints

- **Never archive the live session.** Claude Code appends to its transcript between turns; a
  moved file keeps receiving writes at the new path and the session vanishes from its own
  picker. The script refuses this — do not work around it with a raw `mv`. If the user wants
  the current session archived, tell them to exit first and run the skill from a new session.
- **Do NOT weaken the live-session check.** It has three independent guards — daemon roster,
  file mtime, and `SELF_SESSION_ID` — and each exists because a weaker version archived a live
  session during testing. `lsof` fails because Claude Code closes the transcript between turns;
  mtime alone fails because a session can be running but idle for hours. The check fails
  closed, and a false refusal is cheap: exit the session and retry.
- **Never delete a transcript.** This skill only moves files. If the user asks to actually
  delete, confirm explicitly first and state that it is irreversible.
- **Move the sidecar directory too.** Some sessions have a directory named after the UUID next
  to the `.jsonl`. The script handles this; raw `mv` commands typically orphan it.

## Verifying

After archiving, confirm the count dropped and the file exists at the destination:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/sessions.sh list | wc -l
ls ~/.claude/archived-sessions/<project-slug>/
```

## Errors

| Message | Cause | Fix |
|---|---|---|
| `is LIVE — ...` | Session is running, or just written. The message states which. | Exit that session, then retry |
| `matched no session by id or name` | Wrong name/id, or wrong project | Run `list`, or set `PROJECT_SLUG` |
| `is ambiguous — matched N sessions` | Name fragment or id prefix hits several | Use a longer fragment, or the id from the printed list |
| `no session directory for project slug` | Not a project with sessions | Run `projects` to see valid slugs |
