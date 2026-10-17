---
name: morning-recall
description: >-
  Open the user's day with a success experience: a short recall quiz on what they learned
  in the previous day or two, calibrated so they will mostly answer correctly and start the
  day feeling sharp. Reaffirmation first, retrieval difficulty second.
  Use when the user says "good morning", "morning quiz", "morning recall", "quiz me on
  yesterday", "warm me up", "what did I learn yesterday — test me", or starts the day
  asking to be tested. Optional arguments: a lookback window (1d / 2d / 3d / YYYY-MM-DD),
  a question count (n=6), and a subject scope (subject=<topic>). Distinct from
  what-i-learned-today, which produces a full 10-bullet digest of a single day; this
  skill produces no digest — only a calibrated quiz plus a spaced-repetition ledger.
---

Run a **morning recall session**: 5–7 open-recall questions drawn from the user's Claude
Code work over the previous day or two.

## The goal: open the day with a success experience

**This is the skill's primary purpose and it overrides every other consideration here.**
The user should finish this session feeling sharp and capable, having just proven to
themselves that yesterday's work stuck. Solidifying knowledge is the mechanism; confidence
at the start of the day is the outcome being optimized.

Two consequences, both non-negotiable:

- **Target ~5 of 6 correct.** Effort should be visible — an instant answer reaffirms
  nothing — but the effort must land. A question that produces a blank stare at 7am has
  failed at this skill's actual job, however pedagogically interesting it was.
- **When torn between two difficulty bands, always pick the easier one.** Classic
  retrieval-practice advice says to sit right at the edge of failure. That advice is
  deliberately overridden here: the edge of failure is the wrong place to start a day.

A session where the user gets everything right is a mild waste. A session where they get
half wrong is a **failure of this skill**, not of the user — and Step 6 says so out loud.

## Arguments

All optional, any order.

- **Window** — `1d`, `2d` (default), `3d`, or `YYYY-MM-DD` for a specific day.
  The window covers **whole calendar days before today**. Today's own sessions are
  excluded: material from an hour ago is not yet a memory worth testing. If the window
  yields nothing (weekend, day off), widen one day at a time up to 5 and say so.
- **Count** — `n=6` (default 6, clamp 3–8). Below 3 there is no session; above 8 it stops
  being a morning warm-up.
- **Subject** — `subject=<topic>` / `on <topic>` narrows the candidate pool to one area
  (e.g. `on MoE`, `subject=mongodb`). Judge relevance on meaning, not keyword match.

If an argument matches none of these forms, ask whether it was a window or a subject.

## Step 1: Gather the source material

**Prefer an existing digest.** If `~/what-i-learned-today/YYYY-MM/YYYY-MM-DD.md` exists for
any day in the window, read it — it is already distilled. Also read any sibling
`.quiz.json`: its `verdict` fields are direct evidence of what the user already knows.

**Otherwise harvest transcripts.** Sessions live at
`~/.claude/projects/<dir>/<uuid>.jsonl`. Select by mtime:

```bash
find ~/.claude/projects -name '*.jsonl' \
  -newermt "$(date -v-2d +%Y-%m-%d 2>/dev/null || date -d '2 days ago' +%Y-%m-%d) 00:00:00" \
  ! -newermt "$(date +%Y-%m-%d) 00:00:00" 2>/dev/null
```

(`date -v-2d` is BSD/macOS. On GNU coreutils use `date -d '2 days ago'`.)

**Never read a whole JSONL into context.** Extract only user messages and assistant text
blocks, dropping tool calls and tool results:

```bash
jq -r '
  select(.type=="user" or .type=="assistant")
  | select(.message.content != null)
  | if .type=="user" then
      if (.message.content | type)=="string" then "USER: " + .message.content
      else (.message.content[] | select(.type=="text" or .type==null) | "USER: " + (.text // .content // "")) end
    else
      (.message.content[]? | select(.type=="text") | "ASSISTANT: " + .text)
    end
' "$FILE" 2>/dev/null | head -c 200000
```

Tag each block with its project directory so questions can be attributed.

**Anti-recycling rule.** Previous runs of this skill and of `what-i-learned-today` are
themselves in the transcripts. Drop any block that is quiz scaffolding — `**Q3/6:**`,
`✅ Correct`, `🟡 Partially correct`, `❌ Missed it`, scoreboards, digest headings, and the
answering/grading turns around them. A lesson must originate from **doing the work**, not
from having been quizzed about it. When in doubt, drop it.

Carve-out: if the user asked a genuinely new conceptual question mid-quiz and learned
something that was not the bullet being tested, that learning counts.

Show one line before proceeding so the user can interrupt: `Scanning N sessions across M
projects from <window>...`

If the widened window still yields nothing, say `No sessions found for <window> — nothing
to recall this morning.` and stop.

## Step 2: Build the candidate pool

Extract every **knowledge claim** the user was exposed to: a mechanism, a gotcha, a
decision and its reasoning, a flag or API quirk, a performance finding, a mental model.
Not activities ("refactored the parser"), not status ("tests passed").

For each candidate, record two things that drive calibration:

1. **Engagement evidence** — what did the user actually *do* with this claim? Quote or
   paraphrase the turn that shows it.
2. **Prior verdict** — has this item been asked before? Check the ledger (Step 3) and any
   `.quiz.json` sidecars.

## Step 3: Calibrate difficulty — biased toward success

Score every candidate into a band. **The band comes from engagement evidence, not from how
complicated the topic sounds.**

| Band | Signal | Use |
|---|---|---|
| **1 — too easy** | The user introduced the idea themselves, or used the term fluently and unprompted across several turns. Nothing to reaffirm. | **Exclude** |
| **2 — easy** | A single fact they saw and confirmed once, with no reasoning attached. | Warm-up only: at most Q1, or as a step-down after two misses |
| **3 — target** | They reached the understanding *with help*: asked a clarifying question, got corrected, said "ah, ok", or restated it in their own words after a gap was closed. Reconstructing it requires effort but is achievable. | **the bulk of the set** |
| **4 — stretch** | Requires transferring the lesson to a new situation, or recalling a specific number, flag, or threshold seen once. | **At most 1**, placed late — never as the last question |
| **5 — too hard** | Appeared only in assistant monologue or tool output with no acknowledgement; or the user was demonstrably confused and it was never resolved. | **Exclude** |

**Prior-verdict adjustments** (ledger and sidecars):

- Previously **missed** → include and drop one band (scaffold it). A miss re-asked at the
  same difficulty just produces a second miss.
- Previously **partial** → prime band-3 material. Prefer these.
- Previously **correct once** → include only if due per the review schedule (Step 6).
- Previously **correct twice or more** → exclude unless the ledger says it is due.

**Phrasing controls difficulty as much as selection does.** Same fact, three pitches:

- Too easy: *"What does MoE stand for?"* — a label, not knowledge.
- Target: *"Why doesn't a MoE model's total parameter count tell you its inference speed?"*
- Too hard: *"Give the exact active-parameter count of the model we discussed."*

Always demand the **mechanism or the why**, phrased so the user must explain it aloud in
their own words — this is interview prep, so force articulation. Never multiple-choice.

**Ordering serves the success experience.** Open with a band-2 or easy band-3 they will
almost certainly get — the first answer sets the tone for the whole session. Place the
stretch question mid-to-late, never last. **Close on a band-3 they will land.** The final
exchange is what the user carries into their day, so it must be a win.

**Never ask a band-5 question "just to see".** Curiosity about the edge of their knowledge
is not a reason to spend the one morning they have.

If the pool holds fewer than 3 usable candidates, say so honestly — `Only N questions worth
asking from <window>; most of it was routine execution.` — and ask that many.

## Step 4: Persist the question set

Write `~/what-i-learned-today/recall/YYYY-MM-DD.morning.json` (the date is **today**, the
morning the quiz is run). `mkdir -p` first.

```json
{
  "run_date": "2026-09-28",
  "window": "2026-09-26..2026-09-27",
  "subject": null,
  "generated_at_iso": "...",
  "total": 6,
  "questions": [
    {
      "n": 1,
      "item_id": "moe-total-vs-active",
      "lesson": "<the claim, one sentence, for re-grading context>",
      "band": 3,
      "evidence": "<the engagement signal that set the band>",
      "question": "<asked verbatim>",
      "model_answer": "<1-3 tight sentences>",
      "project": "areas-of-expertise",
      "verdict": null,
      "answered_at": null
    }
  ]
}
```

`item_id` is a stable kebab-case slug for the underlying claim — it is what the ledger
tracks across mornings, so reuse an existing id when the claim recurs rather than minting a
new one.

Do **not** print the questions or model answers here. Write silently; note only the path.

**Resuming:** if today's file already exists with unanswered questions, skip Steps 1–3
entirely and continue from the first `verdict: null`, keeping the original numbering.

## Step 5: Run the quiz

Open with one short line — the window, the count, and nothing else. No digest, no preamble
about what the user did yesterday: **naming the lesson before asking is the answer.**

Per question:

1. Print `**Q3/6:** <question>` — nothing else.
2. **Stop and wait.** Never batch questions, never reveal the answer before they respond.
3. Grade **the understanding, not the phrasing.**
   - Verdict: **✅ Correct** / **🟡 Partially correct** / **❌ Missed it**
   - **Credit the mechanism.** If they explained how the thing works but reached for the
     wrong label, that is **✅ Correct** with a terminology note — not a downgrade. Naming
     is a separate skill from understanding, and docking them for it manufactures a failure
     where there wasn't one. Reserve 🟡 for a genuinely incomplete mechanism and ❌ for a
     wrong or absent one.
   - **Terminology correction is still mandatory** — it just doesn't change the verdict.
     State the correct term and why, then move on. Correct the vocabulary, credit the
     knowledge.
   - Lead with what they got right, then what was missing. One or two sentences.
   - The **model answer**, 1–3 sentences.
4. Write the verdict and `answered_at` back to the JSON immediately, then ask the next one.

**Adaptive pacing — recover the success experience fast:**

- **One** ❌ or 🟡 → drop a band immediately for the next question. Do not wait for a second
  miss to confirm the pattern; by then the morning is already soured. Recalibrating early
  costs nothing, and a miss followed by a win reads as recovery rather than decline.
- Two misses in a row → the pool was mis-scored. Drop to band 2, attach a one-clause
  scaffold (*"think about where the router sits"*), and shorten the set — ending early on a
  correct answer beats grinding out six.
- First three all ✅ and answered instantly → step up **one** band, not two. A too-soft
  session still achieves the primary goal; a suddenly-too-hard one destroys it.
- "I don't know" → **❌ Missed it**, give the model answer, move straight on. No penalty
  framing, no "you should remember this", no disappointment.
- "stop" / "enough" / "skip" → end immediately, print the partial scoreboard, go to Step 6.

**Tone:** a coach opening the day, not an examiner. Brief, warm, precise about corrections,
never punitive. Keep the whole session under ten minutes of reading.

## Step 6: Scoreboard, ledger, and schedule

**Close on the win.** Print one line: `Morning recall: X correct, Y partial, Z missed out of
N.` Then **one sentence naming what they clearly own** — the strongest answer of the
session, specifically, not generic praise. That sentence is the actual deliverable of this
skill; the score line is bookkeeping.

Add at most one sentence naming a theme worth re-reading today, and only if a miss was
substantive. Never list the misses. No lecture, no "areas for improvement" section.

**If the session went badly (half or more missed), say the calibration was wrong** — in
those words. The questions were pitched too hard for a morning warm-up; that is this
skill's error and the ledger will correct it tomorrow. Do not let the user conclude they
have forgotten yesterday's work.

Then update `~/what-i-learned-today/recall/ledger.json` — the cross-morning memory that
makes calibration improve over time. One entry per `item_id`:

```json
{
  "item_id": "moe-total-vs-active",
  "lesson": "<one sentence>",
  "first_seen": "2026-09-26",
  "history": [{ "date": "2026-09-28", "verdict": "correct", "band": 3 }],
  "streak": 1,
  "next_due": "2026-10-02"
}
```

`next_due` from the latest verdict, expanding on success:

| Verdict | Next due |
|---|---|
| ❌ missed | tomorrow |
| 🟡 partial | +2 days |
| ✅ correct, streak 1 | +4 days |
| ✅ correct, streak 2 | +10 days |
| ✅ correct, streak 3+ | +30 days, then retire |

A due item from the ledger may be mixed into a later morning even if it falls outside the
lookback window — cap such carry-ins at **2 per session** so the quiz stays anchored in
recent work. A previously-correct carry-in is a reliable win; leading with one is a
legitimate way to open on success.

**Use the ledger to fix your own calibration.** The stored `band` next to each verdict is a
record of what you predicted. A ❌ on a band-3 question means the engagement evidence was
over-read — next morning, score comparable evidence one band harder and ask it one band
easier. A session of straight ✅ at band 2 means the opposite. Over a few mornings this is
what makes the difficulty land where it should.

## Step 7: Offer one follow-up

A single short line: re-ask the missed ones now, go deeper on one item, or run
`/what-i-learned-today` for the full digest of a specific day. One line — do not turn the
morning into a meeting.

## Notes and constraints

- **Never `cat` a whole JSONL.** Always `jq` + per-file filtering + a size cap.
- Dedupe session files by path — session ids can appear both as
  `projects/<dir>/<uuid>.jsonl` and under `projects/<dir>/<uuid>/`.
- Use whatever `date` returns on the machine; do not hardcode a timezone. Use `date -v-Nd`
  on macOS and `date -d 'N days ago'` on Linux.
- Report honestly if some files failed to parse: `(skipped N unreadable sessions)`.
- If the ledger or a run file is corrupt, say so and start a fresh one — never silently
  overwrite accumulated history.
