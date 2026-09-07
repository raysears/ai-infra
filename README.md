# ai-infra

A Claude Code plugin that gives every project the same guardrails, and turns each incident you hit into a permanent one.

Rules reach every session. `/init` reads your project and writes an `AGENTS.md` whose commands it has actually run. `/lesson` files what bit you, the reviewer picks it up as a trap, and when the list fills the oldest entry has to become a deny rule, a hook or a test.

## Install

```
claude plugin marketplace add raysears/ai-infra
claude plugin install ai-infra@raysears
```

Then in any project: `/init`.

Update with `claude plugin marketplace update raysears && claude plugin update ai-infra@raysears`.

## What you get

| | |
|---|---|
| **Rules everywhere** | `SessionStart` and `SubagentStart` hooks emit `hooks/rules.md` into every session and every subagent, plus the project's own surprises list, so the reviewer's traps arrive without anyone remembering to pass them. |
| **Commit-on-main guard** | A `PreToolUse` hook denies `git commit` on the default branch. A settings deny cannot read branch state; a hook can. |
| **`/init`** | Detects language, package manager, test/lint/build commands and CI, then writes `AGENTS.md` (plus a `CLAUDE.md` symlink), `.claude/settings.json`, `scripts/new_worktree.sh` and git excludes. Every command is run once before it is written. |
| **`/lesson`** | The only writer of `AGENTS.md`'s *Things that surprise people* and *Guards*. |
| **`/handover`, `/grill-me`** | Session continuity, and an interview that stress-tests a plan before you build it. |
| **Agents** | `scout` maps an unfamiliar repo into `.claude/state/MAP.md`. `health-check` assesses a whole codebase and writes a verdict to `.claude/state/HEALTH.md`. `pr-reviewer` reviews a diff adversarially. None of the three fixes anything. |

## The loop

1. Something bites you. You run `/lesson` with what happened and what it cost.
2. It lands in `AGENTS.md` under *Things that surprise people*: dated, one bullet, fixed format. No cost sentence, no entry.
3. `pr-reviewer` reads that section live at every spawn, so a lesson becomes a review check the moment it is filed.
4. The section caps at seven. To add an eighth, the oldest must become machinery: a deny pattern, then a hook when a deny cannot read the state it needs, then a test that greps a file's own source, then a structural doc test. Anything that cannot be promoted is deleted.

Prose moves one way only: into a guard, or out of the file.

## Committing to the default branch

The guard refuses `git commit` on the default branch, because a commit on a local `main` once rode unreviewed into a merged PR (2026-08-07). Branch first, or use `scripts/new_worktree.sh`.

A repo with no PR flow opts out with a **committed** `.claude/allow-main`. Creating or staging it does nothing, which is deliberate: an opt-out should arrive through a diff somebody can see, not be granted by an agent in the same command it was blocked on. To bootstrap, commit the file on a branch and `git merge --ff-only`, since a fast-forward runs no `git commit`.

None of this stops a determined agent, because every hook is a file an agent can edit. It makes accidents expensive and deliberate choices visible. For the remote half, `scripts/protect-branch.sh` applies a GitHub ruleset requiring a pull request into the default branch. Free on public repos, Pro on private, and it cannot tell you from your agent since both authenticate as the same account.

## Working on the plugin

`claude --plugin-dir .` loads the working tree for one session, no install needed.

An install is a **copy** into `~/.claude/plugins/cache/`, and neither `install` nor `update` refreshes it at the same version. Bump `version` in `.claude-plugin/plugin.json`, or:

```bash
claude plugin uninstall ai-infra@raysears && claude plugin install ai-infra@raysears
```

A newly added agent or skill is discovered at session start, so it will not appear in a session
that was already running when you installed it. Restart to pick it up.

Because it is a copy, an edit made there changes what runs while this repo stays clean and git stays silent. Run `bash scripts/selfcheck.sh` before every push: it diffs the cache against the repo and catches the frontmatter, hook and format mistakes that otherwise fail silently.

One rule selfcheck cannot check for you: every rule you add carries its dated incident and what it cost, or the mechanism that makes it true. A rule with neither gets simplified away by the next agent.

## Credits

`grill-me`, `grilling`, `writing-for-agents` (with `SKILL-MECHANICS.md`) and the shape of `/handover` are vendored from [mattpocock/skills](https://github.com/mattpocock/skills) (1.2.3, commit 0ab1b63), MIT, Copyright (c) 2026 Matt Pocock. Full notice in `LICENSES/mattpocock-skills.MIT.txt`.

Not vendored: `research`, `tdd`, `diagnosing-bugs`, `prototype`, `domain-modeling`, `code-review`, `wayfinder`, `wizard`. `claude plugin install mattpocock-skills` adds them alongside. With both installed, the three vendored skills appear twice, under `ai-infra:` and `mattpocock-skills:`. Disable one, or live with the duplicate description lines.

## License

MIT, see `LICENSE`.
