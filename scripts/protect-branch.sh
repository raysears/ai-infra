#!/usr/bin/env bash
# Apply a branch-protection ruleset to a GitHub repo's default branch.
#
# Why a script and not a file in the repo: GitHub does not read protection settings from your
# tree. There is no .github/rulesets.yml. Protection lives server side, so the only way to
# version-control it is to version-control the call that creates it. Run this once per repo.
#
# What it buys, honestly: it stops a direct push to the default branch, including one you make
# by accident. It does NOT distinguish you from an agent. Both authenticate as the same GitHub
# account, so this is a guard against the wrong push, not an agent-specific control. The
# ai-infra PreToolUse hook covers the local half; this covers the remote half.
#
# Free plan: rulesets work on PUBLIC repos. Private repos need Pro or above, and this script
# says so rather than failing with a bare 403.
set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
    || { echo "usage: $0 [owner/repo]   (or run inside a repo with a GitHub remote)" >&2; exit 1; }
fi

command -v gh >/dev/null || { echo "gh CLI not found: https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated: run 'gh auth login'" >&2; exit 1; }

read -r VISIBILITY BRANCH < <(gh repo view "$REPO" --json visibility,defaultBranchRef \
  -q '[.visibility, .defaultBranchRef.name] | @tsv')

echo "repo:    $REPO"
echo "branch:  $BRANCH"
echo "public:  $VISIBILITY"

if [ "$VISIBILITY" != "PUBLIC" ]; then
  cat >&2 <<EOF

This repo is $VISIBILITY. Branch protection rulesets require GitHub Pro or above on
private repos; the Free plan covers public repos only. Either make the repo public,
or rely on the local ai-infra commit guard plus review discipline.
EOF
  exit 1
fi

# required_approving_review_count is 0 on purpose: GitHub refuses to let you approve your own
# pull request, so any number above zero makes a solo repo unmergeable. Zero still forces the
# change through a PR, which is the part that matters.
gh api -X POST "repos/$REPO/rulesets" --input - <<'JSON'
{
  "name": "protect-default-branch",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    }
  ]
}
JSON

echo
echo "Ruleset applied. Verify:  gh api repos/$REPO/rulesets -q '.[].name'"
echo "Direct pushes to $BRANCH are now refused; open a pull request instead."
