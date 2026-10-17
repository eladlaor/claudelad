# session-archive

Hides Claude Code sessions from the `/resume` picker without deleting them, and restores
them later.

## Why

The resume picker lists every transcript in `~/.claude/projects/<project-slug>/`, and there
is no built-in way to hide one. After a few weeks the list is too long to scan. Deleting
transcripts loses history; this plugin moves them to `~/.claude/archived-sessions/` instead,
where they stay intact and can be restored. A side effect: archived transcripts are outside
the path Claude Code's `cleanupPeriodDays` retention prunes, so they survive it.

## What it does

- **list**: shows each session's id, last-modified time, size, and its `/rename` name (or
  first prompt), so an opaque UUID is identifiable. Live sessions are marked `*`.
- **archive**: moves the chosen sessions, together with any sidecar directory. Accepts a
  session name (case-, space-, hyphen- and underscore-insensitive) or an id prefix, and
  refuses on ambiguity rather than guessing.
- **restore**: moves them back.
- **projects**: lists project slugs and their session counts.

### Never archives a live session

A moved transcript keeps receiving writes at its new path, so the session disappears from
its own picker. The script refuses if any of three independent checks says the session is
live: the Claude Code daemon roster, a recent write (default 180s, `LIVE_WINDOW_SECONDS`),
or a match on `SELF_SESSION_ID`. It fails closed: a false refusal costs a retry.

## Usage

Say "archive session", "clean up my session list", "declutter /resume", or
"restore session".

## Requirements

`bash`, plus standard `find`, `stat`, `date`, `sed`. Works on macOS and Linux.

## Install

```
/plugin install session-archive@claudelad
```
