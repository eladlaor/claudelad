---
name: explain-term
description: Explain a concept across five fixed dimensions — analogy, technical mechanism, real-world use-case, contradiction (the wrong mental model to preempt), and etymology with pronunciation. Use when the user types /explain-term, or says "explain the term", "five dimensions", "give me the 5-dimension explanation", "glossary entry for X", "add X to the glossary", "break down the term X", or asks for a concept explained the way their glossary files are written. Optional --persist flag writes the result into the knowledge base. Do NOT use for ordinary inline questions where the user just wants a quick answer.
argument-hint: "[--persist] <term>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebSearch, WebFetch
metadata:
  version: "1.0.0"
  category: Domain Intelligence
---

# Explain Term — Five-Dimension Concept Breakdown

Produce one explanation of `<term>` across five fixed dimensions, in a consistent
glossary style. Always print it in chat. With `--persist`, also write it to the knowledge
base.

## Step 1 — Parse the invocation

Input shape: `/explain-term [--persist] <term>`

- Everything after the optional flag is the term. Terms may contain spaces (`agent sandbox`,
  `mixture of experts`). Do not require quotes.
- `--persist` may appear before or after the term. Accept `--persist`, `-p`, and `persist`.
- No term given → ask for one. Do not guess.

## Step 2 — Verify before asserting

Check how volatile the term is before writing a word of it.

| Term type | Required action |
|---|---|
| Stable concept (`idempotency`, `B-tree`, `HTTP boundary`) | Answer from knowledge. No search. |
| Product, vendor, API, version, price, limit | **Search the live source first.** Never assert an API detail, version number, price, or quota from memory. |
| Anything from the current repo | Read the actual code/config first. Quote file:line. |

Record what you verified. Anything you could not verify gets stated as unverified **in the
body**, not silently dropped.

## Step 3 — Write the five dimensions

These five are fixed and always present, in this order. Phrase every heading as a question
a real person would ask — teaching material reads better as answers to real questions. Answer the question in the first sentence, then expand.

1. **Analogy** — `## What is it like?` One concrete, everyday comparison. Name where the
   analogy breaks down; an analogy without its limit is a future misconception.
2. **Technical mechanism** — `## How does it actually work?` Plain language first. Introduce
   a technical term ONLY if the explanation collapses without it. No name-dropping.
3. **Real-world use-case** — `## When would I actually reach for this?` At least one
   concrete scenario, ideally one from the user's own stack. Say when NOT to use it.
4. **Contradiction** — `## What do people get wrong about it?` The single most valuable
   section. Name the wrong mental model explicitly, then correct it. If the term is commonly
   confused with a neighbour, contrast them directly.
5. **Etymology** — `## Where does the name come from?` Origin of the name and how engineers
   say it aloud. If the name has no real story, say so in one line rather than inventing one.

### Additional sections (house style)

If the user already keeps glossary files, read one first and match its structure. Otherwise
use these:

- `## Summary` — first section after the TOC. 2–4 sentences of actionable content.
- `## Say it out loud (~30s)` — the spoken version, for teaching it to someone else.
- `## Traps` — only when there are concrete operational gotchas beyond the contradiction.
  Omit otherwise; do not pad.
- `## Self-quiz` — 5–8 questions, each answer inside a `<details><summary>` block.
- `## Sources` — only when Step 2 required live verification. Link what you actually fetched.

### Second-language register — optional

Only if the user has asked for it (in the invocation or in their CLAUDE.md), add one line to
`## Say it out loud` showing how engineers who speak their language actually say the term:

- Latin-letter transliteration, so it reads in any terminal.
- Reflect real register: technical nouns usually stay English and the local language
  conjugates around them. Do not translate terms nobody translates.
- If the term is too new to have a settled idiom, say the phrasing drifts team to team
  rather than inventing a standard.

Otherwise omit it silently.

## Step 4 — Persist (only with `--persist`)

Without the flag, stop after printing to chat.

### Choosing the destination

Decide project-scoped vs user-scoped yourself using this rule:

| Condition | Destination |
|---|---|
| Term is specific to the current repo, its product, or its vendor | `<repo-root>/knowledge/glossary/<NAME>.md` |
| Term is general industry knowledge | `~/.claude/knowledge/glossary/<NAME>.md` |
| Not inside a git repo | user-scoped |
| Genuinely ambiguous | ask once, then proceed |

Examples: `AER`, `tool sandbox`, `agent.yaml` → project-scoped in that project.
`idempotency`, `mixture of experts`, `HTTP boundary` → user-scoped.

### File naming and writing

- Filename: `UPPERCASE_SNAKE_CASE.md` derived from the term (`agent sandbox` →
  `AGENT_SANDBOX.md`). Strip punctuation; keep it readable.
- First line: `# <Term>`. Then a **clickable TOC** linking every `##` heading. Then
  `## Summary`.
- `mkdir -p` the target directory if missing. Say explicitly in chat that you created it.
- **If the file already exists: Read it first.** Never overwrite blind. Merge by updating
  the stale sections with `Edit`, preserving anything the file has that this run did not
  produce. Add a dated note when a fact changed.
- Never create glossary files in a repo root — `knowledge/` only.

## Step 5 — Report

In chat, state: the term, the destination path (or "not persisted"), whether the file was
created or updated, and anything you flagged as unverified. One short paragraph.

## Quality bar

- Lead with the answer; never build up to it.
- Cut any term, spec, part number, or vendor name that does not change the conclusion.
- If a dimension genuinely does not apply, write one line saying why. Do not pad it.
- Correct the user's terminology explicitly if the term they typed is imprecise or
  non-standard — state the correct term, say why, then proceed using it.
