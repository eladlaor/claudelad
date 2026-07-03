# session-reconciler

Attributes an uncommitted working tree back to the multiple Claude Code sessions that
produced it, when those sessions ran **in parallel on one shared checkout** (no
worktrees, no branches). Answers: *"a pile of changes accumulated on `main` from N
concurrent sessions — who did what, where did they collide, and how do I commit it as
coherent per-feature units?"*

Git captures no authorship for uncommitted work, and same-file edits across sessions
are last-writer-wins (the losing session's change is silently overwritten). But the
per-session JSONL transcripts under `~/.claude/projects/<slug>/` record every
`Edit`/`Write`/`MultiEdit` with its file path and content — so attribution is
recoverable. This plugin automates that recovery.

## Cost model: mechanical first, LLM last

- **Tier 0 (free, always):** `scripts/extract.sh` derives everything mechanical with
  `jq` — files touched per session, edit counts, line deltas, first user prompt, time
  window. `scripts/collisions.sh` computes the collision matrix by pure set math.
- **Tier 1 (cheap, `report` mode):** one small-model call per *editing* session for a
  ≤2-sentence intent line, fed only distilled Tier-0 data — never the raw transcript.
  Model: `SESSION_RECONCILER_MODEL` env var, default `claude-3-5-haiku-latest`.
- **Tier 2 (expensive, `deep` mode only):** a full semantic transcript read per session
  via subagents, including reconstructing what each side of a collision intended.

## Usage

```
/session-reconciler:reconcile [collisions|report|deep [session-id ...]] [path] [--since <ISO8601|all>] [--out <path>]
```

- `collisions` — collision matrix + per-session file lists. **Zero LLM tokens.**
- `report` (default) — full attribution table, collision matrix, suggested commit
  grouping. One cheap LLM call per editing session.
- `deep` — adds per-session transcript deep-reads and per-collision "what each side
  intended" diffs. Explicit opt-in.

By default only sessions modified **after the repo's last commit** are analyzed
(earlier work is already committed history); override with `--since`.

## Output

1. **Session attribution table** — per session: id, time window, intent, files, +/- lines.
2. **Collision matrix** — files edited by more than one session, with per-session
   deltas. These are the last-writer-wins risk zones: disk shows only the surviving
   content; the losing intent lives only in its transcript.
3. **Suggested commit grouping** — per-session `git add … && git commit …` checklist
   for the **user** to run. The plugin never executes git write operations.
4. Out-of-tree and scratch edits reported separately, never folded into repo commits.

## Requirements

- `jq`
- `claude` CLI on PATH (only for `report`/`deep` modes)

## Scripts

Both scripts are standalone and reusable:

```bash
scripts/extract.sh /path/to/project --since all          # JSON array of session summaries
scripts/extract.sh /path/to/project | scripts/collisions.sh   # collision matrix
```

## Tests

```bash
tests/run_tests.sh
```

Fixture-based tests cover the correctness-critical extraction rules (notably the
`MultiEdit` `edits[]` under-count bug that motivated the strict spec), scratch and
out-of-tree exclusion, time scoping, summarizer-session skipping, malformed-line
resilience, and collision detection.
