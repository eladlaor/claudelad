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

A productive day with Claude Code teaches you real things — a CLI flag, a debugging conclusion, an architectural call — that then vanish into long transcripts. This plugin mines the day's session files, filters out tool noise and routine status updates, and distills only the durable insights into a 10-bullet "what I learned" digest tagged by project. It saves the digest to disk and runs an interactive open-recall quiz over those lessons, one question at a time. It excludes its own prior digests and quizzes from the corpus, so reviewing yesterday's lessons never recycles into today's.

[Documentation](plugins/what-i-learned-today/README.md) · `/plugin install what-i-learned-today@claudelad`

