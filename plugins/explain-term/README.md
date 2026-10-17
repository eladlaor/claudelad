# explain-term

Explains a concept across five fixed dimensions, written so you can teach it to someone
else afterwards.

## Why

An ordinary answer explains what a term means. What actually makes it stick is the analogy
and where it breaks, the wrong mental model people usually hold, and enough of the story
behind the name to say it aloud confidently. This skill always produces all five, in the
same order, with each heading phrased as the question a real person would ask.

## The five dimensions

1. **What is it like?** One everyday analogy, and where it breaks down.
2. **How does it actually work?** Plain language first; jargon only if unavoidable.
3. **When would I actually reach for this?** A concrete scenario, and when not to.
4. **What do people get wrong about it?** The misconception to preempt.
5. **Where does the name come from?** Etymology and pronunciation.

Plus a summary, a ~30-second spoken version, traps (if any), a self-quiz, and sources.

Volatile terms (products, APIs, versions, prices, limits) are checked against live sources
before anything is asserted, and anything unverified is flagged in the body.

## Usage

```
/explain-term mixture of experts
/explain-term --persist idempotency
```

With `--persist`, the entry is written as `UPPERCASE_NAME.md` to the current repo's
`knowledge/glossary/` (repo-specific terms) or `~/.claude/knowledge/glossary/` (general
ones). Existing files are read and merged, never overwritten.

## Install

```
/plugin install explain-term@claudelad
```
