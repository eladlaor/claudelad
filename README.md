# claudelad

## Table of Contents

- [Install](#install)
- [Plugins](#plugins)
  - [date-context](#date-context)
  - [session-finder](#session-finder)
  - [md-to-gdoc](#md-to-gdoc)
  - [notebooklm-upload](#notebooklm-upload)
  - [timewatch-fill](#timewatch-fill)
  - [validate-in-chrome](#validate-in-chrome)
  - [what-i-learned-today](#what-i-learned-today)
  - [worktree-manager](#worktree-manager)
  - [audio-transcribe](#audio-transcribe)
  - [gdoc-watch](#gdoc-watch)
  - [session-handoff](#session-handoff)
  - [session-reconciler](#session-reconciler)
  - [clip](#clip)
  - [session-archive](#session-archive)
  - [permissions-master](#permissions-master)
  - [explain-term](#explain-term)

A Claude Code plugin marketplace. Hooks, skills, and automations that extend what Claude Code can do out of the box.

Plugins covering productivity, document creation, browser automation, and workflow automation. All MIT-licensed, minimal dependencies, and designed to work right after install.

## Install

Add the marketplace (one-time):

```
/plugin marketplace add eladlaor/claudelad
```

Then install any plugin:

```
/plugin install <plugin-name>@claudelad
```

## Plugins

### date-context

<img src="illustrations/today_is_today.jpg" width="500">

Claude Code knows today's date but not the day of week, current time, or timezone. Without those, it can't reason about deadlines, tell you if something is due tomorrow, or generate accurate timestamps in your timezone. This zero-config hook injects the full temporal context on every session start.

**Example:** `Today is Saturday, March 28, 2026. Current time: 14:30 (IST +03:00).`

[Documentation](plugins/date-context/README.md) · `/plugin install date-context@claudelad`

### session-finder

<img src="illustrations/session_finder.jpg" width="600">

Claude Code has no built-in way to search or recall past sessions. If you worked on something last week, you're stuck scrolling through `claude --resume` hoping to recognize it by name. session-finder builds a structured index on every session exit, with LLM-generated summaries, files touched, git branch, and timestamps. You search by natural language description and get a resume command back.

[Documentation](plugins/session-finder/README.md) · `/plugin install session-finder@claudelad`

### md-to-gdoc

<img src="illustrations/md-to-gdoc.png" width="600">

Writing in markdown is fast. Formatting a Google Doc manually is slow. Copy-pasting loses heading structure, breaks tables, and produces a mess. This plugin converts markdown to fully formatted Google Docs via the Docs API, with proper headings, tables, lists, cover pages, and custom format profiles you can extract from any existing Google Doc.

[Documentation](plugins/md-to-gdoc/README.md) · `/plugin install md-to-gdoc@claudelad`

### notebooklm-upload

<img src="illustrations/notebooklm-upload.png" width="600">

You have notes, PDFs, recordings, and docs scattered across directories. Getting them into NotebookLM means uploading one file at a time through a browser. This plugin batch-uploads entire local directories to a NotebookLM notebook in one command — with file type filtering, dry-run preview, and automatic validation.

**Example:** `upload ~/research --notebook "Q1 Review" --include pdf,md,mp3`

[Documentation](plugins/notebooklm-upload/README.md) · `/plugin install notebooklm-upload@claudelad`

### timewatch-fill

Filling TimeWatch attendance is repetitive monthly busywork. This plugin drives your real Chrome session (via the claude-in-chrome MCP) to fill a single day, a week, or every unfilled workday in the current month — with configurable times, task, and location.

[Documentation](plugins/timewatch-fill/README.md) · `/plugin install timewatch-fill@claudelad`

### validate-in-chrome

After Claude implements a UI change, you usually have to manually click around to verify it actually works. This plugin adds a `/validate-in-chrome` slash command that synthesizes a behavioral acceptance-criteria spec from what was just implemented, then hands it to an isolated subagent that drives your real Chrome session (not ephemeral Chromium) through each criterion and returns a terse pass/fail table. The subagent never sees the diff or the code — verification stays honest.

[Documentation](plugins/validate-in-chrome/README.md) · `/plugin install validate-in-chrome@claudelad`

### what-i-learned-today

A productive day with Claude Code teaches you real things — a CLI flag, a debugging conclusion, an architectural call — that then vanish into long transcripts. This plugin mines the day's session files, filters out tool noise and routine status updates, and distills only the durable insights into a 10-bullet "what I learned" digest tagged by project. It saves the digest to disk and runs an interactive open-recall quiz over those lessons, one question at a time. It excludes its own prior digests and quizzes from the corpus, so reviewing yesterday's lessons never recycles into today's. It also ships **morning-recall**: a short quiz on the previous days, calibrated so you mostly get it right, with a spaced-repetition ledger that brings misses back.

[Documentation](plugins/what-i-learned-today/README.md) · `/plugin install what-i-learned-today@claudelad`

### worktree-manager

Claude Code's built-in worktrees are session-scoped and disappear when the session ends. If your workflow runs parallel branches — you on one feature, Claude on another, across multiple sessions — you need worktrees that persist, live as navigable sibling directories, and merge back cleanly. This plugin creates and manages persistent worktrees, auto-detects worktree context via a `SessionStart` hook (injecting branch, main-repo path, and sibling worktrees), and merges branches back with dependency-ordered, conflict-aware resolution and verification.

[Documentation](plugins/worktree-manager/README.md) · `/plugin install worktree-manager@claudelad`

### audio-transcribe

Turn a recording of a conversation or talk into a speaker-labeled transcript, fully locally. faster-whisper handles the speech recognition (Hebrew and 90+ languages) and pyannote labels who spoke when. No audio leaves your machine.

[Documentation](plugins/audio-transcribe/README.md) · `/plugin install audio-transcribe@claudelad`

### gdoc-watch

Keep a Google Doc in view while you edit it: ask Claude questions about it and get told what changed since you last asked. It pulls the doc on each prompt via `gws`, with no background polling.

[Documentation](plugins/gdoc-watch/README.md) · `/plugin install gdoc-watch@claudelad`

### session-handoff

Most handoff documents are written for someone who was already in the room. This skill rewrites a repo's handoff so the next session can resume from a fresh clone, and makes the gitignored state (`.env` files, CLI pins, virtualenvs), which is what actually breaks a new directory, a required section.

[Documentation](plugins/session-handoff/README.md) · `/plugin install session-handoff@claudelad`

### session-reconciler

Several parallel Claude Code sessions wrote to one working tree and now nobody knows which change came from where. This plugin reads the session transcripts and attributes each uncommitted change to the session that made it, flags files more than one session wrote, and suggests a per-feature commit grouping. It never runs git.

[Documentation](plugins/session-reconciler/README.md) · `/plugin install session-reconciler@claudelad`

### clip

Copying out of a terminal chat drags along fences, borders, and trailing newlines, and asking Claude to print a secret puts it in the transcript. `/clip` pipes the exact value onto your clipboard (`pbcopy`, `wl-copy`, `xclip`, or OSC 52 over SSH), reads secrets from `.env` or 1Password inside the pipe so they are never printed, and verifies the copy by shape, never by content.

[Documentation](plugins/clip/README.md) · `/plugin install clip@claudelad`

### session-archive

The `/resume` picker lists every transcript and has no way to hide one. This plugin moves sessions out to `~/.claude/archived-sessions/` (by name or id) and restores them on request. Nothing is deleted, archived transcripts survive automatic retention cleanup, and it refuses to move a session that is still live.

[Documentation](plugins/session-archive/README.md) · `/plugin install session-archive@claudelad`

### permissions-master

Permission rules fail quietly: a wrong path anchor or a `Bash` pattern that doesn't match how the command is really invoked just doesn't apply. This skill audits your allow/deny/ask rules across settings files, configures new ones from a stated goal, and troubleshoots why a rule isn't taking effect.

[Documentation](plugins/permissions-master/README.md) · `/plugin install permissions-master@claudelad`

### explain-term

Explain any concept across five fixed dimensions, each heading phrased as a real question: an analogy and where it breaks, the mechanism in plain language, when to use it, the wrong mental model to preempt, and where the name comes from. Volatile terms are checked against live sources first, and `--persist` saves the entry as a glossary file.

[Documentation](plugins/explain-term/README.md) · `/plugin install explain-term@claudelad`
