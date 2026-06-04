# what-i-learned-today

Turn a day's worth of Claude Code sessions into a focused **"What I learned"** digest — 10 high-signal lessons, saved to disk, followed by an interactive recall quiz.

## Why This Plugin?

Most days you learn real things working with Claude Code — a CLI flag you didn't know, a debugging conclusion, an architectural call and the reasoning behind it — and then lose them in the noise of long transcripts. This skill mines your session JSONL files for the day, filters out tool noise and routine status updates, and distills only the durable insights into a 10-bullet digest tagged by project.

It then saves the digest under `~/what-i-learned-today/YYYY-MM/` and runs a one-question-at-a-time open-recall quiz over those lessons — active retrieval practice, not just a passive recap.

## Install

```
/plugin install what-i-learned-today@claudelad
```

## Usage

```
/what-i-learned-today:what-i-learned-today [date|window]
```

| Argument | Meaning |
|----------|---------|
| _(none)_ | Today (since 00:00 local) |
| `YYYY-MM-DD` | That specific calendar day |
| `Nd` (e.g. `7d`) | Last N calendar days, rolled into one digest |

### Examples

| Command | What it does |
|---------|-------------|
| `/what-i-learned-today:what-i-learned-today` | Today's 10 lessons + quiz |
| `/what-i-learned-today:what-i-learned-today 2026-06-01` | Digest for June 1st |
| `/what-i-learned-today:what-i-learned-today 7d` | Rolled-up digest for the last 7 days |

Say "no quiz" / "just the digest" in your invocation to skip the recall quiz.

## How It Works

1. Finds the day's session JSONL files under `~/.claude/projects` by file mtime.
2. Groups them by project and previews the scope.
3. Extracts only user prompts and assistant text via `jq` — never tool calls, file dumps, or command output — and **drops this skill's own prior digests and quiz interactions** so previous learnings aren't recycled into a loop.
4. Synthesizes exactly 10 lessons (technique, gotcha, decision, finding), each tagged with its project.
5. Saves the digest to `~/what-i-learned-today/YYYY-MM/YYYY-MM-DD.md`.
6. Runs an interactive open-recall quiz, one question per turn, grading each answer against the digest.

## Anti-Recycling

Because using this skill puts a digest and quiz into today's transcript, a naive re-run would re-harvest yesterday's lessons as if they were new. The skill explicitly excludes its own output (digest headings, quiz markers, scoreboards, and the Q&A they generate) from the corpus — a lesson only counts if it came from doing first-order work, not from being quizzed on it.

## Output Location

```
~/what-i-learned-today/
├── 2026-05/
│   └── 2026-05-25.md
└── 2026-06/
    └── 2026-06-01.md
```

Re-running for the same date overwrites that day's file (the later run has more context).

## Uninstall

```
/plugin uninstall what-i-learned-today@claudelad
```
