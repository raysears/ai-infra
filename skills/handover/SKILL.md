---
name: handover
description: "Write .claude/state/HANDOFF.md so a fresh session can continue this work."
disable-model-invocation: true
argument-hint: "What will the next session be used for?"
---
<!-- Adapted from handoff in https://github.com/mattpocock/skills (mattpocock-skills 1.2.3, commit 0ab1b63), MIT, Copyright (c) 2026 Matt Pocock. Full notice: LICENSES/mattpocock-skills.MIT.txt -->

Write one live handoff so the next session starts from facts, not from re-reading a transcript. The SessionStart rules tell every agent to read `.claude/state/HANDOFF.md` before exploring; this is its only writer.

**Step 1: location.**

`TOP=$(git rev-parse --show-toplevel)`; `mkdir -p "$TOP/.claude/state"`. If `.claude/state` is not a line in `$TOP/.git/info/exclude` (a missing file counts as empty), append it; no trailing slash, since the worktree script makes it a symlink and a `dir/` pattern matches directories only. Never `.gitignore`: a client reviews that diff; an exclude is invisible and local.

**Step 2: write** `$TOP/.claude/state/HANDOFF.md`, overwriting. One live handoff; history is in git and the transcript. Lines 1-5 exactly:

```
# Handoff

**Status:** live
**Last updated:** <date +%F from the clock>
**Owner:** <session purpose from the argument, or 'unspecified'>
```

Then these sections:
- **Next session is for**: the argument, tailored to what this session leaves behind.
- **Where things stand**: done and not done, each pointing at a path, commit, PR or issue. Never restate what those artifacts already say; point at them.
- **Watch out for**: one line, the thing you cannot reconstruct from `git log` after three weeks away.
- **Suggested skills**: names the next agent should call via the Skill tool; user-invoked ones as "tell the human to run /x".
- **Open decisions**.

**Step 3: redact** API keys, passwords, tokens, personal data. Completion criterion: every claim in the file points at an artifact or is marked as this session's belief.

Print `handoff written: .claude/state/HANDOFF.md`.

**Never:** commit, stage or push; write a handoff into the tracked tree; leave a secret in it; generate a PROGRESS.md or TODO.md alongside (a status file an agent updates more often than it commits goes stale and misleads).
