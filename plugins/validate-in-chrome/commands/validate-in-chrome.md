---
description: Validate the feature just implemented in this session by driving the user's real Chrome (claude-in-chrome) inside an isolated subagent. Spec is synthesized from session context.
argument-hint: "[optional extra hints, e.g. URL to start at, credentials note]"
---

You are about to delegate browser-based validation of work just completed in THIS session to an isolated subagent named `chrome-validator`. The subagent will see only the spec you write below — it will NOT see this conversation, the diff, or the code. That isolation is intentional: it forces honest, behavior-only verification.

## Step 1: Synthesize a behavioral acceptance-criteria spec

Look back over what was implemented in this session. Build a spec that satisfies ALL of these rules:

1. **Behavioral and user-observable only.** Each AC describes what a human using the app sees, clicks, types, or receives. Forbidden: references to function names, file paths, internal state, code structure, or implementation details. If you find yourself writing "verify that X is called" or "the component re-renders" — rewrite it as what the user would actually observe.
2. **Concrete and deterministic.** Each AC must have an unambiguous pass/fail outcome. "Looks good" is not an AC. "After clicking Submit, a green toast containing the text 'Saved' appears within 3 seconds" is an AC.
3. **Self-contained.** The subagent has no access to your context. Include: the URL(s) to navigate to, any credentials hint the user mentioned, any preconditions (e.g. "a user must be logged in"), and the exact UI strings / selectors / visible affordances to look for.
4. **Scoped to what was just changed.** Do not invent ACs for unrelated parts of the app. If the session touched the login flow, validate the login flow — not the dashboard.
5. **Small.** 3–8 ACs is the sweet spot. If you have more, you are probably testing too much; pick the highest-signal ones.

If you genuinely cannot derive a spec from session context (e.g. the session was pure backend work with no UI), STOP and tell the user so — do not invoke the subagent.

If the user provided extra hints as arguments ($ARGUMENTS), incorporate them (typically a starting URL or auth note).

## Step 2: Delegate to the chrome-validator subagent

Use the Agent tool with `subagent_type: "chrome-validator"`. The subagent already knows its procedure and output format — do not re-specify them. Pass ONLY the spec, formatted like this:

```
# Validation spec

## Context for the verifier
- Starting URL: <url>
- Preconditions: <e.g. "User is already logged in via SSO; do not attempt to log in again." or "None.">
- Notes: <anything else the verifier needs, e.g. "the dev server is at localhost:3000">

## Acceptance criteria
1. <AC 1, behavioral, deterministic>
2. <AC 2>
3. <AC 3>
...
```

## Step 3: Report back

When the subagent returns, relay its summary verbatim to the user, then add one short sentence with your own recommendation (e.g. "All ACs passed — the change looks good to commit." or "AC 3 failed — investigate the toast timing in <relevant file>."). Do not re-run the validation yourself.

$ARGUMENTS
