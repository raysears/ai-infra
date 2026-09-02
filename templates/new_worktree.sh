#!/usr/bin/env bash
# Give an agent (or yourself) an isolated working directory for one branch.
#
# Several agents and a human share this repo. One shared checkout means one checked-out branch and one index: a `git checkout` in another session moves you onto a different branch mid-task, and `git add` sweeps up their work. Three incidents on 2026-08-07 came from exactly that. A worktree is the fix: one clone, one history, its own directory, branch and index.
#
# What a worktree does NOT isolate: {{SHARED_STATE}} are shared by every session, so two agents can still collide on data when their files cannot. Coordinate before running anything that writes there.
#
#   ./scripts/new_worktree.sh fix-thing   -> ../worktrees/fix-thing on branch fix-thing, from origin/{{DEFAULT_BRANCH}}
# Remove worktrees when their PR merges: git worktree remove ../worktrees/<name>
set -euo pipefail
BRANCH="${1:?usage: new_worktree.sh <branch-name> [base]}"
BASE="${2:-{{DEFAULT_BRANCH}}}"
REPO="$(git rev-parse --show-toplevel)"
DEST="$(dirname "$REPO")/worktrees/$BRANCH"
if [ -e "$DEST" ]; then
  echo "$DEST already exists -- pick another name or remove it:" >&2
  echo "  git worktree remove $DEST" >&2
  exit 1
fi
# Always branch from an up-to-date REMOTE base, never from whatever happens to be checked out.
# No fallback to a local branch: a silent fallback is the 2026-08-07 behaviour coming back on any clone without a reachable origin.
if ! git -C "$REPO" fetch --quiet origin "$BASE"; then
  echo "cannot fetch origin/$BASE: no reachable remote (git remote -v). Refusing to branch from a local ref. Fix the remote and retry." >&2
  exit 1
fi
git -C "$REPO" worktree add "$DEST" -b "$BRANCH" "origin/$BASE"
# Private, untracked state shared across worktrees on purpose (each line below was chosen by /init; the env link means this worktree holds whatever the root .env points at):
mkdir -p "$DEST/.claude"
[ -d "$REPO/.claude/state" ] && ln -s "$REPO/.claude/state" "$DEST/.claude/state"
{{PRIVATE_LINKS}}
(cd "$DEST" && {{INSTALL_CMD}})
cat <<EOF
worktree ready: $DEST   (branch $BRANCH, from origin/$BASE)
  cd $DEST
  {{TEST_CMD}}

When the PR is merged:
  git worktree remove $DEST
EOF
