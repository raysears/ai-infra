#!/bin/bash
# ai-infra PreToolUse(Bash) guard: refuse `git commit` while the checked-out branch is the default branch.
# Bought by 2026-08-07: a commit made on a local main rode, unreviewed, into a merged PR.
# Fails OPEN by design (any error -> exit 0, tool runs): a guard that hangs or crashes gets deleted, which is how a blanket wildcard allow once came to exist. Never prompts.
IN=$(cat)
CMD=$(printf '%s' "$IN" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null) || exit 0
# Word-boundary match: `grep 'git commit' file` on main is not a commit.
printf '%s' "$CMD" | grep -qE '(^|[;&| ])git[[:space:]]+commit' || exit 0
CWD=$(printf '%s' "$IN" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null) || exit 0
# ponytail: honour a leading `cd <dir> &&`; anything fancier than that is out of scope for a speed bump.
LEAD=$(printf '%s' "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+"?([^"&;|[:space:]]+)"?[[:space:]]*&&.*/\1/p')
[ -n "$LEAD" ] && CWD=$(cd "$CWD" 2>/dev/null && cd "$LEAD" 2>/dev/null && pwd)
# Per-repo opt-out: a repo that deliberately has no PR flow (config, docs, scratch) skips
# this guard with a .claude/allow-main file at its root.
# The file must be COMMITTED, not merely present or staged: `touch` and `git add` both do
# nothing. An opt-out therefore arrives through a commit and a diff somebody can see, rather
# than one an agent grants itself mid-task in the same command it was blocked on.
# Bootstrap: commit the file on a branch, then `git checkout main && git merge --ff-only
# <branch>`. A fast-forward runs no `git commit`, so this guard does not fire.
ROOT=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$ROOT" ] && [ -f "$ROOT/.claude/allow-main" ] \
   && git -C "$ROOT" cat-file -e HEAD:.claude/allow-main 2>/dev/null; then
  exit 0
fi
BR=$(git -C "${CWD:-.}" branch --show-current 2>/dev/null) || exit 0
DEF=$(git -C "${CWD:-.}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -n "$BR" ] && { [ "$BR" = "${DEF:-main}" ] || [ "$BR" = main ] || [ "$BR" = master ]; }; then
  python3 -c 'import json,sys; b=sys.argv[1]; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":f"ai-infra: you are on `{b}`. Never commit on the default branch (an unreviewed commit rode into a merged PR on 2026-08-07). Make a branch first: git checkout -b <topic> origin/{b}, or use scripts/new_worktree.sh <topic>."}}))' "$BR"
fi
exit 0
