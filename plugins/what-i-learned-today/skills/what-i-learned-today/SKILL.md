---
name: what-i-learned-today
description: >-
  Summarize what the user learned across all Claude Code sessions in a given day
  (default: today) as a 10 bullet "lessons learned" digest. Use when the user says
  "what did I learn today", "learned today", "daily learnings", "summarize my sessions
  today", or asks for a recap of today's Claude Code work focused on insights rather
  than activity. Optional arguments are a date (YYYY-MM-DD) or window like "7d", and a
  subject scope (subject=<topic> / --subject <topic> / "on <topic>") that focuses ONLY
  the quiz questions on that topic while the full digest is still persisted.
---

Produce a focused **"What I learned"** digest from the user's Claude Code session
transcripts for the requested day.

## Arguments

Up to two, in any order.

**1. Time window (optional):**
- No argument → today (calendar day, since 00:00 local).
- `YYYY-MM-DD` → that calendar day (00:00–23:59 local).
- `Nd` (e.g. `7d`) → last N calendar days, rolled into one digest.

**2. Subject scope (optional)** — `subject=<topic>`, `--subject <topic>`, or `on <topic>`:

A free-text topic that **scopes only the quiz questions** (Steps 5b and 6). Examples:
- `/what-i-learned-today subject=mongodb`
- `/what-i-learned-today 7d on RAG`
- `/what-i-learned-today 2026-06-10 --subject "git internals"`

**Critical scoping rule:** the subject affects **only quiz generation and quizzing**. The
digest (Steps 1–5) is **always produced and persisted in full, unfiltered** — every lesson
found in the sessions gets recorded regardless of subject. The subject narrows *which
lessons become quiz questions*, never which get recorded. With no subject, the quiz covers
all bullets.

If a positional argument is none of these forms, stop and ask whether they meant a time
window or a subject.

## Step 1: Locate the day's session files

Sessions live at `~/.claude/projects/<project-dir-with-slashes-as-dashes>/<uuid>.jsonl`.
Filter by file mtime.

**Today:**
```bash
find ~/.claude/projects -name '*.jsonl' -newermt "$(date +%Y-%m-%d) 00:00:00" 2>/dev/null
```

**Specific date:**
```bash
find ~/.claude/projects -name '*.jsonl' \
  -newermt "YYYY-MM-DD 00:00:00" \
  ! -newermt "YYYY-MM-DD 23:59:59" 2>/dev/null
```

**Last N days:**
```bash
find ~/.claude/projects -name '*.jsonl' -newermt "$(date -v-Nd +%Y-%m-%d 2>/dev/null || date -d 'N days ago' +%Y-%m-%d) 00:00:00" 2>/dev/null
```
(`date -v-Nd` is BSD/macOS; the fallback `date -d` is GNU/Linux.)

If zero matches, say "No Claude Code sessions found for <window>" and stop.

## Step 2: Group sessions by project

The parent directory name encodes the working directory. Group matched files by parent
directory so insights can be attributed to projects.

Show a one-line preview before reading: `Found N sessions across M projects: <project-1>
(k1), <project-2> (k2), ...` — this lets the user interrupt if the scope is wrong.

## Step 3: Extract user prompts and assistant text — NOT tool noise

Session JSONL is dominated by tool calls, file contents, and command output. **Never read
whole files into context.** Extract only user messages (what was asked or directed) and
assistant text blocks (explanations, conclusions, recommendations), skipping `tool_use`.

```bash
jq -r '
  select(.type=="user" or .type=="assistant")
  | select(.message.content != null)
  | if .type=="user" then
      # user content can be a string or an array of blocks; skip tool_result blocks
      if (.message.content | type)=="string" then
        "USER: " + .message.content
      else
        (.message.content[]
          | select(.type=="text" or .type==null)
          | "USER: " + (.text // .content // ""))
      end
    else
      # assistant content is an array of blocks; keep only text blocks
      (.message.content[]?
        | select(.type=="text")
        | "ASSISTANT: " + .text)
    end
' "$FILE" 2>/dev/null
```

Pipe to `head -c 200000` per file as a safety cap. Concatenate all extracts into one
corpus, tagging each block with its project name so attribution survives.

### Exclude this skill's own output (anti-recycling rule)

Earlier runs of this skill are themselves in the transcripts and will be re-harvested.
**Do not recycle them.** Drop any block that is self-referential output of *this* skill:

- Assistant blocks containing the digest heading `# What I learned — `, quiz markers like
  `**Q3/10:**`, `✅ Correct`, `🟡 Partially correct`, `❌ Missed it`, or the
  `Quiz: X correct, Y partial, Z missed` scoreboard.
- User/assistant turns that are answering or grading a recall quiz rather than doing project work.
- Any prompt that invoked this skill and the surrounding Q&A it generated.

The corpus must contain only **first-order work** — actual building, debugging, deciding —
never the meta-layer of reviewing what you previously learned. A lesson must originate from
doing the work, not from being quizzed about it. When in doubt, drop the block.

**Carve-out — genuinely new learning during a quiz still counts.** The exclusion targets
quiz *mechanics*, not *new* understanding that surfaces in a quiz-adjacent exchange. If the
user asks a real conceptual question mid-quiz and learns something that was **not** in that
day's digest and **not** the bullet being tested, keep it. Test: would this lesson be new
and true even if no quiz had ever run? If yes, keep it. Only drop the
question/answer/grade scaffolding.

## Step 4: Synthesize the digest

Produce **exactly 10 bullets** titled `# What I learned — <date or window>`.

Each bullet:
- Starts with the concrete insight (technique, gotcha, fact, mental model), not the task.
  Bad: "Worked on RAG eval." Good: "Hybrid search beats dense-only when queries contain
  exact identifiers (SKUs, ticket IDs) — confirmed in the langrag eval run."
- Adds a short "why it matters" clause if non-obvious.
- Ends with a project tag when attributable: `[langrag]`, `[cinemacity]`. Use `[multiple]`
  if the lesson recurred across projects.

**What counts as a lesson:**
- Keep: new tools/CLIs/flags, debugging conclusions, architectural decisions and their
  reasoning, gotchas hit and fixed, performance findings, library/API quirks,
  prompt-engineering observations, security/permission learnings, workflow improvements.
- Drop: routine status updates, "I created file X", "the test passed", recapping the
  user's own statements, generic platitudes ("planning is important").
- Drop: anything caught by the anti-recycling rule in Step 3. If a lesson only appears
  today because you were quizzed on it, it was not learned today.

If fewer than 10 genuine lessons exist, output what you have plus a final line:
`(only N substantial lessons surfaced — most of the day was routine execution).` Do not pad.

If more than 10 surface, pick the highest signal — prefer durable knowledge over one-off
facts, and lessons the user reacted to (corrections, "ah ok", direction changes) over
assistant monologue.

## Step 5: Persist the digest

**Always save** to `~/what-i-learned-today/`, organized by month:

```
~/what-i-learned-today/
├── 2026-05/
│   ├── 2026-05-24.md
│   └── 2026-05-25.md
└── 2026-06/
    └── 2026-06-01.md
```

- Filename `YYYY-MM-DD.md` matching the target date. For a multi-day window,
  `YYYY-MM-DD_to_YYYY-MM-DD.md` under the **end-date's** month directory.
- `mkdir -p ~/what-i-learned-today/YYYY-MM/` before writing.
- If the file exists for the same date, **overwrite** — the second run has more context. Do
  not append or version-suffix. Mention the overwrite to the user.
- Content is the same markdown you printed: heading, bullets, and any "only N" footer.

Print the absolute path of the saved file on its own line.

### Step 5b: Generate and persist the quiz questions (sidecar JSON)

Derive one open-recall question per digest bullet, in order, and persist them **now** — so
a later session or fresh context window resumes the quiz with the *same* wording instead of
re-deriving it.

**Subject scoping (when a subject was given):** select only the bullets whose content falls
in the subject area and generate questions from that subset, renumbered 1..K in digest
order. Judge relevance on actual content, not literal keyword match (e.g. `subject=mongodb`
includes an aggregation-pipeline gotcha even without the word "mongodb"). The digest `.md`
stays full and unfiltered — only the `.quiz.json` narrows. If **no** bullet matches, do not
write an empty quiz: tell the user, skip Step 6, go to Step 7.

- Sidecar path: same directory and basename as the digest, extension `.quiz.json`.
- One object per selected bullet:
  ```json
  {
    "n": 1,
    "lesson": "<the digest bullet text, verbatim, for re-grading context>",
    "question": "<the open-recall question, phrased per the Step 6 rules>",
    "model_answer": "<a tight 1-3 sentence correct answer distilled from the bullet>",
    "verdict": null,
    "answered_at": null
  }
  ```
- `verdict` is `null` (not yet asked), `"correct"`, `"partial"`, or `"missed"`. Step 6 fills it in.
- Top-level shape:
  ```json
  {
    "digest_file": "<absolute path to the .md>",
    "window": "<the date or YYYY-MM-DD_to_YYYY-MM-DD>",
    "subject": "<the subject scope, or null if the quiz covers all bullets>",
    "generated_at_iso": "<ISO-8601 timestamp>",
    "total": <N>,
    "questions": [ ... ]
  }
  ```
  With a subject, `total` is the count of *selected* bullets (K); each question's `lesson`
  is still the verbatim bullet so re-grading context survives.
- **Overwrite rules mirror the digest.** On a fresh full run, or when the request specifies
  a **different subject** than the persisted one, overwrite with fresh questions and reset
  all verdicts to `null`. When only *resuming* with the same (or no) subject, do NOT
  regenerate — reuse the existing file and preserve prior verdicts.
- Do not print the questions or model answers here — that spoils the quiz. Write silently
  and note the sidecar path (e.g. `Quiz persisted: <path>`).

## Step 6: Run an inline recall quiz

After the digest is printed and saved, run an **interactive, one-question-at-a-time,
open-recall quiz**. This active retrieval is the whole point of the digest. Do **not** skip
it unless the user opted out.

**Use the persisted questions — do not re-derive them.** Read the `.quiz.json` from Step
5b, ask its `question` fields verbatim, grade against `model_answer` / `lesson`, and write
each `verdict` back as you go. This is what makes the quiz resumable across context
windows: wording and numbering come from disk, not fresh generation.

**Resuming (new session / new context window).** The skill may be invoked purely to
continue a previous quiz — "quiz me from the saved file", "resume the quiz", "continue from
Q3", "quiz me on lessons 3–15":

- Locate the existing `.quiz.json` for the window. If it exists and the user wants to
  resume, **skip Steps 1–5b entirely** — do not re-harvest transcripts or regenerate. Just
  load the sidecar.
- Starting question: the one they named, else the **first with `verdict: null`**. Say where
  you're resuming from in one line.
- Keep original numbering (`**Q3/15:**`, not renumbered to `Q1`).
- If they name a subject on resume that **matches** the sidecar's `subject`, resume. If it
  **differs**, treat it as a regeneration per Step 5b.
- If no `.quiz.json` exists for that window, say so and offer a fresh run.

**Format — strict, non-negotiable:**

- **One question per turn.** Ask, then **stop and wait**. Never print the next question or
  reveal the current answer before the user responds — batching defeats the recall effect.
- **Open-recall, not multiple-choice.** Phrase so the user must *explain in their own
  words* ("Why does durability in MongoDB come from the journal and not the data files?").
  Force articulation — this is interview prep.
- **One question per substantial lesson**, in digest order. 10 bullets → 10 questions; an
  "only N" footer → N questions. Cap at 10 even for multi-day windows.

**Per-question loop:**

1. Print `**Q3/10:** <question>` — nothing else. (The total reflects the sidecar's `total`,
   so a 15-lesson window shows `Q3/15`.)
2. **Wait** for the answer.
3. Grade against the bullet / `model_answer`. Respond in this order:
   - A verdict: **✅ Correct**, **🟡 Partially correct**, or **❌ Missed it**.
   - One or two sentences on what they nailed and what they missed — apply the same
     terminology-correction rigor as the rest of the session.
   - The **model answer**: 1–3 tight sentences distilled from the bullet.
4. **Persist the verdict.** Update that question's object in the sidecar (`verdict` +
   `answered_at` ISO timestamp) and write the file back, so a later session knows exactly
   what remains and what was missed.
5. Ask the next question. Repeat until done.

**At the end**, print a one-line scoreboard: `Quiz: X correct, Y partial, Z missed out of
N.` Then offer to re-quiz only the missed/partial ones (read from the sidecar's verdicts).

**Opt-out / control:**
- "no quiz" / "skip the quiz" / "just the digest" → skip to Step 7.
- Mid-quiz "stop" / "skip" / "enough" → end immediately, print the partial scoreboard, go
  to Step 7. Don't force completion.
- "I don't know" → **❌ Missed it**, give the model answer, move on. No penalty framing.

**Tone:** encouraging coach, not interrogator. Precise about corrections, never punitive.

## Step 7: Offer follow-ups

One short line offering: re-quizzing the missed/partial questions; a deeper dive on a
single bullet; a different time window (`/what-i-learned-today 7d`); opening the saved
file; or **resuming the quiz later in a fresh session** — the questions are persisted, so
they can continue from the first unanswered one without regenerating the digest.

## Notes and constraints

- **Never `cat` a whole JSONL into context.** Always `jq` + per-file filtering.
- File mtime is "last modified", so a session started yesterday and continued today is
  included in "today" — that's correct.
- Session paths sometimes duplicate session IDs across `projects/<dir>/<uuid>.jsonl` and
  `projects/<dir>/<uuid>/`. Dedupe by file path before counting.
- Date math uses whatever `date` returns on their machine — do not hardcode a timezone.
- Be honest about coverage. If `jq` extraction fails on some files (corrupt JSONL, ongoing
  writes), report the skipped count at the end.
