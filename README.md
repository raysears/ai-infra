# ai-infra

A Claude Code plugin that injects eight scarred universal rules into every session and subagent, generates a per-project AGENTS.md + settings.json + worktree script from verified detection (/init), files each incident as a capped, dated surprise (/lesson) that the reviewer reads as its trap list and that must become a deny pattern, hook or test when the cap is hit.

## Install

Fresh machine:

```
claude plugin marketplace add raysears/ai-infra
claude plugin install ai-infra@raysears
```

Then in any project: `/init`.

Update: `claude plugin marketplace update raysears && claude plugin update ai-infra@raysears`.

## What you get

| Piece | What it is |
|---|---|
| Always-on rules | SessionStart + SubagentStart hooks emit the exact lines in `hooks/rules.md` into every session and every subagent. SubagentStart also appends the project's `## Things that surprise people` section from AGENTS.md, so the pr-reviewer's trap list arrives mechanically. |
| Commit-on-main guard | A PreToolUse hook denies `git commit` while the default branch is checked out. A settings deny cannot read branch state; this can. |
| Skills and agents | User-invoked: `/init`, `/lesson`, `/handover`, `/grill-me`. Model-reachable: `grilling`, `writing-for-agents`. Agents: `scout` (read-only onboarding, writes `.claude/state/MAP.md`), `pr-reviewer` (adversarial review, reads AGENTS.md surprises live as its traps). |
| What `/init` writes into a project | `AGENTS.md` + `CLAUDE.md` symlink, `.claude/settings.json`, `scripts/new_worktree.sh`, `.gitignore` lines, `.git/info/exclude` lines, optional `tests/test_docs.py` for pytest projects. Every command in AGENTS.md ran once before it was written. |

## The loop

Something bites an agent; the SessionStart rules tell it to say "run /lesson", and the human does. /lesson derives the date from the clock, refuses an entry without a cost sentence, applies the selection test (would a competent agent landing cold confidently assume the opposite?), and prepends the item to AGENTS.md "Things that surprise people" in a fixed one-bullet format. If the section already holds 7 items, /lesson first takes the oldest (bottom) item and either promotes it up the ladder (a deny pattern in the tracked .claude/settings.json; a PreToolUse hook only when a deny cannot read the state; a three-line test that greps a file's own source; a structural doc test) and appends a row to AGENTS.md "Guards", or deletes it because a test already enforces it or the mechanism is gone. The pr-reviewer agent reads "Things that surprise people" live at every spawn as its repo-specific traps (leads, never evidence), so a lesson becomes a review check the moment it is filed, and disappears from the trap list the moment it becomes machinery. Nothing else ever writes those two sections, so prose can only flow one way: into a guard or out of the file.

The promotion ladder, cheapest first:

1. A deny pattern in `.claude/settings.json`.
2. A PreToolUse hook, only when a deny cannot read the state it needs (branch name, file contents).
3. A test that greps a file's own source.
4. A structural doc test in `tests/test_docs.py`.

## Rules for editing this plugin

- Quote every skill `description` that contains `: `. Unquoted, the YAML fails to parse and the skill loads with ALL frontmatter silently dropped.
- Agent frontmatter is `name`, `description` and `tools` only. Other keys are unverified; nothing may depend on them.
- Every rule carries its dated incident and its cost, or the mechanism that makes it true. A rule with neither gets simplified away by the next agent.
- `hooks/rules.md` stays under 25 lines. To shorten it, delete a whole sentence; never trim words from one.
- Run `bash scripts/selfcheck.sh` before every push, and `claude --plugin-dir . plugin details ai-infra` to see the always-on token cost.

## Developing

`claude --plugin-dir /Users/raysears/Documents/dev/ai-infra` loads the working tree for one session.

An install is a COPY into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and neither `install` nor `update` refreshes it at the same version: `install` answers "already installed", `update` answers "already at the latest version". Two ways to get an edit into the running copy, both verified:

```bash
claude plugin uninstall ai-infra@raysears && claude plugin install ai-infra@raysears
```

or bump `version` in `.claude-plugin/plugin.json`, which is what `update` looks at. Prefer the version bump: it leaves a record of what changed and when.

Because the cache is a copy, an edit made there changes what runs while this repo stays clean and git stays silent. That happened on 2026-09-07. `scripts/selfcheck.sh` check 13 now diffs the cache against this repo and fails on any difference.

Smoke test:

```
claude -p --plugin-dir . --model haiku --allowedTools Bash --output-format json 'quote the first ai-infra rule' </dev/null
```

Never run `claude plugin init` for this repo: it scaffolds into `~/.claude/skills/<name>/` and auto-loads next session.

## Committing to the default branch

The `PreToolUse` hook refuses `git commit` while you are on the default branch, because a commit made on a local `main` once rode unreviewed into a merged PR (2026-08-07). Make a branch, or use `scripts/new_worktree.sh`.

A repo that deliberately has no PR flow (config, docs, scratch) opts out with a `.claude/allow-main` file at its root. The file must be **committed**: creating it, or staging it, does nothing. That is deliberate. An opt-out should arrive through a commit and a diff somebody can see, not be granted by an agent in the same command it was just blocked on.

To opt a fresh repo out, commit the file on a branch and fast-forward:

```bash
git checkout -b allow-main-optout
mkdir -p .claude && touch .claude/allow-main
git add .claude/allow-main && git commit -m "opt out of the default-branch commit guard"
git checkout main && git merge --ff-only allow-main-optout
```

A fast-forward merge runs no `git commit`, so the guard does not fire.

None of this stops a determined agent; every hook is a file an agent can edit. It raises the cost of doing it by accident, and it makes doing it deliberately visible. The remote half of the same job is `scripts/protect-branch.sh`, which applies a GitHub ruleset requiring a pull request into the default branch. Rulesets are free on public repos and need Pro on private ones, and they cannot tell you apart from your agent, since both authenticate as the same account.

## Credits

`grill-me`, `grilling`, `writing-for-agents` (with `SKILL-MECHANICS.md`) and the shape of `/handover` are vendored from https://github.com/mattpocock/skills (mattpocock-skills 1.2.3, commit 0ab1b63), MIT, Copyright (c) 2026 Matt Pocock. Full notice in `LICENSES/mattpocock-skills.MIT.txt`.

Not vendored: research, tdd, diagnosing-bugs, prototype, domain-modeling, code-review, wayfinder, wizard. `claude plugin install mattpocock-skills` adds them alongside.

If both plugins are installed, `grill-me`, `grilling` and `writing-for-agents` appear twice (`ai-infra:` and `mattpocock-skills:`). Disable one, or accept the duplicate description lines.

## License

MIT, see `LICENSE`.
