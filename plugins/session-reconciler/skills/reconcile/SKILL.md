# Reconcile Sessions

Attribute an uncommitted working tree back to the parallel Claude Code sessions that
produced it, detect same-file collisions (last-writer-wins risk zones), and propose a
per-session commit grouping. Mechanical-first: everything except the one-line intent
comes from `jq` over the transcripts at zero token cost.

## Instructions

The user's request is: $ARGUMENTS

### Parse the arguments

- **Mode** — one of:
  - `collisions` — Tier 0 only. Print the collision matrix and per-session file lists.
    **Zero LLM calls.**
  - `report` (default when no mode given) — Tier 0 + one cheap LLM intent line per
    editing session. The full attribution report.
  - `deep [session-id ...]` — `report` plus a full semantic transcript read via one
    subagent per named session (or all editing sessions if none named). Expensive;
    only when explicitly requested.
- **Project path** — a path argument if given, else the current working directory.
- **`--since <ISO8601|all>`** — optional time-scope override (default: since the repo's
  last commit).
- **`--out <path>`** — optional report destination.

### Steps

1. **Run the extractor (Tier 0, free).**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/extract.sh <project-path> [--since <value>]
   ```

   It resolves the transcript directory (`~/.claude/projects/<slug>/`, where the slug
   is the absolute project path with `/`, `.`, and `_` replaced by `-`) and emits a
   JSON array of per-session summaries. If it fails because no transcript directory
   exists, relay its error verbatim and stop. Save the output to a temp file in the
   scratchpad directory — you will reuse it.

2. **Compute the collision matrix (Tier 0, free).**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/collisions.sh <extract-output-file>
   ```

3. **Branch on mode.**

   - **`collisions`**: present the collision matrix and each session's file list
     (sections 2 and 1 below, minus the intent column), then stop. Do NOT make any
     LLM call or spawn any subagent in this mode.

   - **`report`**: for **each session with `edited: true` only**, produce a ≤2-sentence
     intent line with **one cheap LLM call per session**, fed ONLY the distilled Tier-0
     data (`first_user_prompt` + the file path list) — never the raw transcript:

     ```bash
     env -u CLAUDECODE claude -p \
       --no-session-persistence \
       --model "${SESSION_RECONCILER_MODEL:-claude-3-5-haiku-latest}" \
       --max-turns 1 \
       "In at most 2 short sentences, state what this Claude Code session was trying to accomplish. First user prompt: <first_user_prompt>. Files it edited: <file list>. Output ONLY the intent, no preamble."
     ```

     No-edit sessions get no LLM call — list them with intent "(no edits)".

   - **`deep`**: everything `report` does, plus spawn **one subagent per requested
     session** (Agent tool, general-purpose) with the transcript path from the extract
     output. Each subagent reads its transcript and returns: the session's intent, and
     for every collision file that session touched, the session's final intended
     content for that file (reconstructed from its LAST `Edit`/`Write`/`MultiEdit` on
     it). Then, per collision, diff the sessions' intended contents against each other
     and against the on-disk file, and report what the last writer may have clobbered.

4. **Assemble the report** (markdown):

   **Section 1 — Session attribution table.** One row per session: short id, time
   window (`started_at`–`ended_at`), intent, files-touched count, total added/removed
   lines. Include no-edit sessions (marked "no edits") so the full session set is
   visible, but exclude them from everything below.

   **Section 2 — Collision matrix.** One row per contested file: path, contributing
   session ids with each session's per-file `edits`/`added`/`removed`. State plainly:
   *collision files show only the surviving content on disk; the losing session's
   intended change may have been silently overwritten and is recoverable only from its
   transcript (run `deep` mode).*

   **Section 3 — Out-of-tree and scratch edits.** If any session has `out_of_tree`
   entries or a nonzero `scratch_edits`, list them separately. Never fold these into
   the repo attribution or the commit grouping.

   **Section 4 — Suggested commit grouping.** Cluster non-collision files by owning
   session into one proposed commit per session; put ALL collision files in a
   "resolve first" bucket at the top. Emit as a checklist of ready-to-paste lines:

   ```
   - [ ] RESOLVE FIRST (contested): <collision file list — review before committing>
   - [ ] git add <session A's files> && git commit -m "<suggested message from A's intent>"
   - [ ] git add <session B's files> && git commit -m "<suggested message from B's intent>"
   ```

   These are for the USER to run. **Never execute `git add`, `git commit`, `git push`,
   or any other git write operation yourself — not in any mode, not via a subagent.**

5. **Deliver.** If `--out <path>` was given, write the report there. Otherwise present
   it inline and offer to save it under `knowledge/plans/` in the target project. The
   run must otherwise be read-only: no file mutations besides the optional report and
   scratchpad temp files.

## Example

User runs: `/session-reconciler:reconcile collisions`

The skill runs `extract.sh` on the cwd scoped to sessions since the last commit, runs
`collisions.sh`, and prints the contested files with contributing sessions — spending
zero LLM tokens.
