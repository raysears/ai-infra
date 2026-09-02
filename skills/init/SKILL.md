---
name: init
description: "Detect this project and generate AGENTS.md, .claude/settings.json and scripts/new_worktree.sh, every command verified by running it."
disable-model-invocation: true
argument-hint: "optional: 'update' to refresh an existing AGENTS.md"
---

Generate a project's agent context from what the tree actually contains. A command lands in AGENTS.md only after it has exited 0 in this session: two documented commands were broken for months and nobody noticed, which discounted everything else in the file (2026-08-26). Detection proposes; running decides.

**Step 0: preflight.**

- `git rev-parse --show-toplevel` must succeed. Otherwise print `init: not a git repo — run git init first` and stop.
- `DATE=$(date +%F)`. Every date written comes from this variable; a typed date once produced a phantom outage report (2026-08-21).
- `AGENTS.md` exists and the argument is not `update`: stop with `init: AGENTS.md exists. Run /init update to re-verify commands and add missing sections; nothing you wrote is touched.`
- `CLAUDE.md` exists as a regular file (`test -f CLAUDE.md && ! test -L CLAUDE.md`): stop and say the human must merge it into AGENTS.md first. /init writes the symlink; it never overwrites hand-written context.

**Step 1: detect.**

From the toplevel run `bash "$CLAUDE_PLUGIN_ROOT/scripts/detect.sh"`. If `$CLAUDE_PLUGIN_ROOT` is unset in the Bash tool, locate the plugin: `ls -d ~/.claude/plugins/cache/raysears/ai-infra/*/ | tail -1`. Output is KEY=VALUE blocks, one per ecosystem plus a trailing shared block, ending `DETECT_OK=1`; a missing sentinel means detection crashed: stop and show the output. Every value is a candidate, not a fact: detection reads files and runs nothing.

**Step 2: scout.**

Spawn the `scout` agent from this plugin with the Agent tool and hand it the detect.sh output. If the Agent tool does not offer it, do the scout's job inline by following `agents/scout.md`. It returns a `SCOUT_FACTS` block: one paragraph of what the project is; where code, tests, docs and the entry point live; shared state (database, deploy target, credentials file) with an evidence path each; up to 3 surprise candidates, each with its evidence path; and it writes `.claude/state/MAP.md`. The scout is read-only: it never runs tests, installs, or executes project code, and you never ask it to.

Hand it two more leads when they exist: the `Repo-specific traps` block of a project-local `.claude/agents/pr-reviewer.md`, and the hand-written bullets of an existing AGENTS.md `## Things that surprise people`. Each is a surprise candidate the scout confirms against code; on one repo the reviewer's best trap (migrations applied by hand, out of sync with deploy) never reached the generated section because nothing read it. A project-local `pr-reviewer.md` also shadows the plugin's agent of the same name, so a session sees two reviewers with different trap sources: report it in Step 6 and recommend deleting it once its traps are on file.

**Step 3: ask the human, one round.**

Grilling format: numbered questions, a recommended answer each, all in one message. Ask nothing detect.sh or the scout could have answered.

- Q1, only if detect.sh reported `ENV_FILE`: what does the local env file point at (production, staging, nothing), and should worktrees share it by symlink? Recommend the target the scout's evidence supports; recommend the symlink unless the target is production.
- Q2: confirm or correct the shared-state list (`SHARED`, `DEPLOY`, the scout's findings).
- Q3: which surprise candidates pass the selection test: a competent agent landing cold would confidently assume the opposite. Recommend per candidate.
- Q4, pytest projects only: generate `tests/test_docs.py` so the docs guard themselves. Recommend yes.
- Q5, only if `PROGRESS.md`, `TODO.md` or `HANDOFF.md` exists at the root: move it to `.claude/state/` or delete it. Recommend the move: a frozen `Status: Superseded` file is still a status file to a cold agent, and `tests/test_docs.py` fails while it stays, so keeping it makes Q4 a no.

Completion criterion: every question answered, or its recommended default accepted in so many words.

**Step 4: verify every command by running it.**

For each of INSTALL, TEST, LINT, BUILD run the `*_VERIFY` form as `CI=1 timeout 600 <cmd> </dev/null`. `timeout` is coreutils and absent on a stock Mac; the live form there is `CI=1 perl -e 'alarm 600; exec @ARGV' bash -c '<cmd>' </dev/null`, and the `bash -c` is what lets a compound spelling such as `npm run lint && npm run typecheck` run (`exec @ARGV` alone hands `&&` to npm as an argument). Verified means exit 0. Then:

- TEST_VERIFY failing with "no tests collected" or "no tests found": still write TEST, followed by `# no tests yet`.
- Any other failure: show the last 20 lines. If a `CI_*` spelling exists, verify that instead and prefer it. If nothing verifies, omit the command and say so in the report.
- A derived spelling and a CI or make/just spelling both verify: write the project's own entry point; keep every verified spelling for the allow list.
- RUN is never executed: servers do not exit. Write RUN only if RUN_VERIFY (an import or check form) passes, else omit.
- A block carrying `DIR=<subdir>`: verify from that directory and write the command as `(cd <subdir> && <cmd>)`.

Completion criterion: every command about to be written has an exit-0 run in this session's transcript, or is RUN and marked `(not executed at generation)`.

**Step 5: write files. Named paths only; never `git add`.**

1. `AGENTS.md` from `$CLAUDE_PLUGIN_ROOT/templates/AGENTS.md`, every `{{SLOT}}` filled (slot list at the top of the template). Drop any line or table row whose slot is empty; `tests/test_docs.py` fails on a leftover `{{`. SURPRISES: the env item first (only when an env file exists; it keeps the template's own trailer), then the confirmed scout candidates, newest first, never more than 7, each in the /lesson bullet format with the trailer `_(recorded <DATE> by /init; cost if wrong: <cost>)_`: a candidate has not bitten, so it carries no `bit` date. Before writing prose: `Call the Skill tool with "ai-infra:writing-for-agents"` and prune no-ops. In `update` mode: re-verify commands and replace only the Commands block; add any missing section (Things that surprise people, Git discipline, Review, Docs, Guards) verbatim from the template; touch nothing else without asking. Two things to ask about, recommended answer yes to both: (a) a ```bash fence outside the Commands block (a `## Tests` or `## Start the Server` section) documents the same command in a second spelling once the block lands: fold it into the generated block and delete the old fence. (b) a hand-written surprise bullet with no `_(bit ...)_` or `_(recorded ...)_` trailer fails `tests/test_docs.py` and forces the first /lesson to promote before it can file: reformat each into the fixed format with `_(recorded <DATE> by /init update; cost: unknown, next /lesson supplies it)_`, after the human confirms the bullet still holds.
2. `ln -sfn AGENTS.md CLAUDE.md`, only if CLAUDE.md is absent or already a symlink.
3. `.claude/settings.json` from `$CLAUDE_PLUGIN_ROOT/templates/settings.json`: the deny list verbatim plus every DESTRUCTIVE pattern from detect.sh; allow = the template allows plus `Bash(<cmd>:*)` for every verified TEST, LINT, BUILD and INSTALL spelling, including the CI spelling and the spelling the worktree script prints (`Bash(uv run pytest*)` once failed to match the `python -m pytest` form a script printed and recreated the hang). If the file exists: union both lists, remove nothing. Report any wildcard allow for the detected runner (`Bash(<pm> *)`, `Bash(<pm>*)`, `Bash(<pm>:*)`) and ask before removing it: that blanket allow existed because unsupervised runs hang on prompts (2026-08-25). Never write `settings.local.json`.
4. `.gitignore`: append `.claude/worktrees/` and `.claude/settings.local.json` if absent. Tracked, so every clone keeps `git add .claude/...` safe; the reverse lost that property on 2026-08-26.
5. `.git/info/exclude`: append `.claude/state` if absent. No trailing slash: a `dir/` pattern matches directories only, and `scripts/new_worktree.sh` makes `.claude/state` a symlink in every worktree, which a slashed pattern leaves untracked and `git worktree remove` then refuses. Private working state (MAP.md, HANDOFF.md): a client reviews the .gitignore diff, an exclude is invisible and local.
6. `scripts/new_worktree.sh` from `$CLAUDE_PLUGIN_ROOT/templates/new_worktree.sh` with `{{DEFAULT_BRANCH}}`, `{{INSTALL_CMD}}`, `{{TEST_CMD}}`, `{{SHARED_STATE}}`, `{{PRIVATE_LINKS}}` filled. PRIVATE_LINKS: the `.env` symlink line only if the human said yes in Q1; the `.claude/state` link is already in the template. No verified INSTALL: remove the install line. If the file already exists: show `diff` of it against the filled template and ask before replacing; recommend the plugin's version, which refuses to branch from a local ref. A repo-owned line (an `.env` symlink, a `--quiet` install) survives only if the human says keep; one repo's own script was overwritten without asking. Then `chmod +x`, `bash -n`, and run `./scripts/new_worktree.sh ai-infra-selfcheck-$(basename "$PWD")` once (the name carries the repo: `../worktrees/` is shared by every sibling repo, and two projects running /init side by side collided on a bare name). Confirm it printed `worktree ready`, then `git worktree remove ../worktrees/<that name>` and `git branch -D <that name>`. The remove refusing over untracked files means the install step wrote something the repo does not ignore: report the path, then remove with `--force`. If origin is unreachable the script fails loudly by design: say so and keep the file.
7. pytest projects, Q4 yes: `tests/test_docs.py` from `$CLAUDE_PLUGIN_ROOT/templates/test_docs.py` with `{{TEST_COLLECT_ARGV}}` and `{{RUNNER_PREFIX}}` filled. Run `<TEST_CMD> tests/test_docs.py` once; keep it only when green, and fill `{{DOC_TEST_ROW}}` in the AGENTS.md Guards table.

**Step 6: report.**

One line per path written. Then the exact `git add <named paths>` line for the human; never run it. If `.claude/agents/pr-reviewer.md` exists, say it shadows the plugin's reviewer and recommend `git rm` once its traps are in AGENTS.md. Final line, always: `init complete: <n> commands verified, <m> files written, <k> surprises filed.`

**What /init never does.**

- Run `git add`, `git commit` or `git push`.
- Execute a RUN command.
- Write `settings.local.json`.
- Replace a file the project already owns without showing the diff.
- Generate PROGRESS.md, TODO.md, an agent-docs/ tree, or any file an agent updates more often than it commits: one sat 19 days stale while the repo shipped daily (2026-08-25).
- Write a command it did not run.
- Embed the plugin's cache path in any file: it changes with every plugin version.
- Ask a question without a recommended default. /init is human-invoked, so questions are fine; a question with no default hangs an unattended run.
