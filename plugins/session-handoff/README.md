# session-handoff

Rewrites a repository's session handoff document so the next session — human or agent —
can resume **from a fresh clone** without asking anything.

## Why

Most handoff documents are written for the person who was already in the room. They say
"the cluster", "as we decided", "the usual gateway". A session starting in a new directory
can act on none of it.

The failure is sharper than vague prose, though. **The things that actually break a new
directory are the gitignored ones** — `.env` files, CLI state and workspace pins, virtual
environments, local databases. They are absent from a clone by definition, they are
invisible to `git status`, and they fail confusingly rather than obviously. A handoff that
never mentions them reads as complete and leaves the next session stuck.

This skill makes that audit a required step.

## What it does

1. Reads the existing handoff and treats every claim in it as unverified.
2. Gathers state from the system — `git log`, `git status`, open PRs, the test suite, the
   deployed resource list — rather than from memory of the conversation.
3. **Audits invisible state**: walks `.gitignore` and `git status --ignored`, and records
   what a fresh clone will lack, each with the command that restores it.
4. Rewrites a fixed section set: Summary, First three actions, Where everything is, State,
   Decisions already made (each with its reason), Open decisions (each with what it
   blocks), Traps that will bite (symptom first, then cause).
5. Verifies the result against the fresh-clone reader and greps for dangling references.
6. Commits it with the session's work.

## Usage

Say any of:

- "update the handoff" / "rewrite the handoff"
- "wrap up the session" / "end of session"
- "write the handoff before I go"

It also triggers when you start work in a repo whose handoff visibly contradicts git.

## Conventions it assumes

- The handoff lives at `knowledge/plans/SESSION_HANDOFF.md`. If your repo keeps one
  elsewhere, the skill uses that path rather than creating a second file.
- **Rewrite, never append.** The document describes the present; git history holds the
  past.
- **Secret values never go in the file.** Name the key and where it lives.

## Notes

The verification step greps case-insensitively for first-person plural. That matters more
than it sounds: without `-i` the check sails past a sentence opening with "We", which is
precisely where it hides.

It also refuses to pin a commit SHA as the repo's position — stale on the next merge, and
a confidently wrong SHA is worse than none. IDs that genuinely do not move (workspace,
project) are fine.

## License

MIT
