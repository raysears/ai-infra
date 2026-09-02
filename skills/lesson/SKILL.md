---
name: lesson
description: "File an incident into AGENTS.md as a dated, costed surprise; promote or delete the oldest when the cap of 7 is hit."
disable-model-invocation: true
argument-hint: "what happened, and what it cost"
---

Turn one incident into one bullet under `## Things that surprise people` in AGENTS.md, or into a guard when the section is full. The pr-reviewer reads that section live at every spawn as its trap list, so a filed lesson is a review check the moment it lands and leaves the list the moment it becomes machinery. Nothing else writes that section or `## Guards`.

**Step 1: gather.**

`DATE=$(date +%F)` from the clock; never type a date (a believed date once produced a phantom fleet-wide outage report, 2026-08-21). From the argument and the conversation extract:

- the mechanism, one line, in the form a cold agent needs;
- why it is invisible: no error, no marker, success that looks right;
- the exact check or workaround: a command or a file;
- when it is deliberate and must not be "fixed", or `never`;
- the cost: time lost, data touched, a wrong report shipped.

Cost missing: ask once. Still missing: print `lesson: refused — a rule with no cost gets simplified away by the next agent.` and stop.

**Step 2: route.** Three exits before filing prose.

- (a) The incident is a wrong or broken command in AGENTS.md: fix the command, run it, stop. The command block is the fix.
- (b) It is a command that must never run: add `Bash(<exact spelling>*)` to the `deny` list in `.claude/settings.json`, append a Guards row, stop. Machinery beats prose from day one.
- (c) It fails the selection test (a competent agent landing cold would NOT confidently assume the opposite): say so, stop, no entry.

Otherwise continue.

**Step 3: cap.**

Count bullets beginning `- **` between `## Things that surprise people` and the next `## `. Fewer than 7: go to Step 4. Otherwise (7, or more after a hand edit) take the LAST bullet, the oldest, since the section is newest-first, and choose its exit, cheapest first, until 6 remain. Show the human the choice with a recommendation:

1. A deny pattern in `.claude/settings.json`.
2. A PreToolUse hook: a `hooks` entry in `.claude/settings.json` plus `.claude/hooks/<name>.sh` modelled on the plugin's `hooks/guard-main.sh` (exit 0 plus a JSON deny on stdout blocks; any error exits 0 and the tool runs). Only when a deny cannot read the state it needs: a branch name, a file's contents.
3. A test that greps a file's own source, in the project's test language, three lines: read the file, `assert not re.search(pattern, src)`, the scar in the docstring.
4. A structural doc test added to `tests/test_docs.py`.
5. Delete. Only when a test already enforces it or the mechanism no longer exists in the code.

Write the guard and run it once: a test goes RED against the broken form and GREEN restored (a test that stays green against broken code advertises a guarantee it does not provide); a deny is checked by reading the file back. Append a row to `## Guards`: `| <rule, incident date> | <guard: file and pattern> |`. Remove the bullet. The reviewer's trap list shrinks by itself: it reads the section live.

Two exits and one requirement, each hit on a dry run and undefined until then:

- Unguardable fact (no command to deny, no branch state, nothing to grep, mechanism still live; "ruff in dev deps is not a lint gate" fits no rung): keep it and try the next-oldest. If none promotes, print `lesson: cap hit; nothing promotable, hand the human <named fix>` and stop without filing.
- A guard that is RED against the live tree is a bug report, not a guard: the code is wrong today and /lesson never fixes code. Hand the human the fix, print `lesson: cap hit; guard blocked on a live bug: <fix>` and stop; file the guard, then the new item, after the fix commit.
- Rung 3 and 4: the guard runs under the documented TEST_CMD, and the RED/GREEN check runs through TEST_CMD, not the file alone. When TEST_CMD does not discover files (an `&&` chain of named files in `package.json` `scripts.test`, a tests index), edit that entry so the guard is in the chain: two rung-3 guards once sat under `tests/` that `npm test` never ran.

**Step 4: write.**

Prepend directly under the section's HTML comment, exact format:

```
- **<mechanism>.** <why invisible>. Check: `<command or file>`. Deliberate when: <condition|never>. _(bit <DATE>; cost: <cost>)_
```

One bullet. No sub-bullets. No line longer than the mechanism needs. Reference code as `module.py:function`, never line numbers: they rot.

**Step 5: report.**

Print the bullet, the Guards row if any, and the sentinel: `lesson filed (<n>/7)`, or `lesson promoted: <oldest mechanism> -> <guard>; filed (<n>/7)`. Then the `git add <named paths>` line for the human; never run it.

**What /lesson never does.**

- Commit, push or stage.
- Write anywhere but `AGENTS.md`, `.claude/settings.json`, `.claude/hooks/`, `tests/`, and the test entry (`package.json` `scripts.test`, a tests index) only to wire a rung-3 guard into TEST_CMD.
- Store an item without a date and a cost.
- Write a date it did not read from the clock.
- Touch the pr-reviewer agent: it reads the section live.
- Create a separate lessons or traps file. The 1000-row cap once lived in six agreeing places; a seventh guards against nothing.
