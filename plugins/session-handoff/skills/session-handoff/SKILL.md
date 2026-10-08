---
name: session-handoff
description: Rewrite knowledge/plans/SESSION_HANDOFF.md so the next session can resume seamlessly from a fresh clone or a new directory. Use when the user says "update the handoff", "rewrite the handoff", "session handoff", "wrap up the session", "end of session", "hand off", "prepare the handoff", "write the handoff before I go", or when a session is ending and its state would otherwise be lost. Also use when starting work in a repo whose handoff is visibly stale — state that contradicts git, or next actions already done.
allowed-tools: Read Write Edit Bash Glob Grep
metadata:
  author: Elad Laor
  category: developer-tools
---

# Session Handoff

Rewrite `knowledge/plans/SESSION_HANDOFF.md` so that a session starting **in a
directory it has never seen before** can pick up without asking a single question.

## Where the file lives

Default to `knowledge/plans/SESSION_HANDOFF.md`. If the repo already keeps a handoff
somewhere else, use that path instead — do not create a second one:

```bash
ls knowledge/plans/SESSION_HANDOFF.md 2>/dev/null
find . -path ./.git -prune -o -iname "*HANDOFF*" -print 2>/dev/null
```

Two handoffs is worse than one: the next session reads whichever it finds first and
cannot tell which is current. Every path below means the one you resolved here.

## The one rule

**Rewrite. Never append.** This file describes the present, not the history. A handoff
that accumulates is a handoff nobody reads. If something is no longer true, it goes —
the changelog and git history are where the past lives.

## The test that matters

Before writing anything, fix the reader in mind:

> Someone cloned this repo 30 seconds ago. They have the repo, the CLI tools, and this
> file. Nothing else. No memory of any conversation.

Every sentence either helps that person act, or it is noise. The most common failure is
writing for the person who was already here — "as we decided", "the usual gateway", "the
cluster" — all of which are meaningless in a new directory.

## Step 1 — read what is there

```bash
cat knowledge/plans/SESSION_HANDOFF.md 2>/dev/null || echo "NO HANDOFF YET"
```

If it does not exist, create it with the section set below. If it does, treat every claim
in it as **unverified** until Step 2 confirms it. Stale handoffs are worse than none,
because they are trusted.

## Step 2 — gather ground truth, do not recall it

Never write state from memory of the conversation. Read it from the system:

```bash
git log --oneline -10
git status --short
git branch --show-current
gh pr list --state open 2>/dev/null
```

Then, per project, whatever proves the current state — the test suite, the build, the
deployed resource list, the service health endpoint. Record what you actually ran and
what it actually said. A number you verified beats a number you remember.

## Step 3 — the invisible-state audit

**This is the step that makes the file worth having, and the one most often skipped.**

A fresh clone does not contain everything the working directory contains. Anything
gitignored is invisible to the next session, and it will fail in confusing ways rather
than obvious ones. Walk the ignore list and name what a fresh clone will lack:

```bash
cat .gitignore
git status --ignored --short | head -30
```

Typical invisible state, and what the handoff must say about each:

| Invisible thing | What the next session needs told |
|---|---|
| `.env` files | Which keys, where to get them (the manager, not the value), which are per-user |
| CLI/tool state dirs (pins, contexts, workspace registrations) | That a fresh clone has none, and which commands must therefore run from the original checkout |
| `.venv/`, lockfile-derived dirs | The exact command that rebuilds them |
| Local databases, volumes, caches | Whether they must be seeded, and how |
| Cloud/remote resources | IDs, not names — names drift, IDs are identity |

**Never put a secret value in this file.** Name the key and where it lives.

## Step 4 — write these sections, in this order

Keep a clickable TOC at the top. Then:

1. **Summary** — three or four sentences. What this project is, what the current
   milestone is, and what is actually built versus specified. Someone must be able to
   stop after this section and know what they joined.
2. **First three actions** — numbered, concrete, each starting with a verb. Not themes:
   actions. Include the command where there is one, and the directory to run it from when
   that matters. If an action is blocked, say what unblocks it.
3. **Where everything is** — a table of path → what lives there. Include the
   authoritative documents, and mark which file is the reference point for each domain.
4. **State as of YYYY-MM-DD** — a table of fact → current value, from Step 2. Include
   versions, IDs, branch, what is deployed, what is running and costing money.
5. **Decisions already made** — each with its date and, critically, **its reason**. A
   decision without its reason gets re-litigated the moment it becomes inconvenient.
6. **Open decisions** — a table with what it blocks. If it blocks nothing, it is not a
   decision, it is a note.
7. **Traps that will bite** — the failures that cost time this session, each written as
   the symptom first, then the cause. The next session meets the symptom, not the cause.

End with a short **How to update this file** section pointing back at the one rule.

## Step 5 — check it against the test

Reread the finished file as the fresh-clone reader. Fix every instance of:

- **Unresolvable reference** — "the cluster", "the gateway", "the other repo". Name it.
- **Conversational residue** — "as discussed", "we decided earlier", "the thing you asked
  about". The reader was not there.
- **Unfalsifiable state** — "mostly working", "should be fine". Say what passes and what
  does not.
- **An action that cannot be started** — no command, no path, no owner.
- **Invisible state left unmentioned** — anything from Step 3 that did not make it in.

A useful final pass: grep your own file for first-person plural.

```bash
grep -ni "\bwe\b\|\bour\b\|\bus\b\|as discussed\|as agreed\|\bearlier\b" \
  knowledge/plans/SESSION_HANDOFF.md
```

**`-i` matters:** without it the check sails past a sentence that opens with "We", which
is exactly where first-person plural hides. Each hit is either harmless prose or a dangling
reference. Check each.

Also check the table of contents still matches the headings, since sections get added:

```bash
grep -o "^- \[.*\]" knowledge/plans/SESSION_HANDOFF.md
grep "^## " knowledge/plans/SESSION_HANDOFF.md
```

**Do not write a commit SHA into the State table as the repo's position.** It is stale the
moment the next commit lands, and a confidently wrong SHA is worse than none. Point at
`git log --oneline -5` instead. Pin IDs that genuinely do not move — workspace IDs, project
IDs — not branch positions.

## Step 6 — commit it

Commit the handoff with the session's work, not as an afterthought:

```bash
git add knowledge/plans/SESSION_HANDOFF.md
git commit -m "Update the session handoff"
```

If the session's work is unpushed, say so in the handoff **and** push it. Work that only
exists in a directory the next session will not open is work that does not exist.

## Error handling

- **No `knowledge/plans/` directory** — create it. Do not relocate the file to the repo
  root; project convention keeps internal docs under `knowledge/`.
- **Uncommitted work from another session** — do not sweep it into your commit. Note it
  in Open decisions, naming the files, and commit only the handoff.
- **The repo is mid-merge or mid-rebase** — record that in State, explicitly. A handoff
  written over a conflicted tree misleads badly.
- **Nothing changed this session** — still refresh the date and re-verify State. A file
  that silently rots is the problem this skill exists to prevent.
