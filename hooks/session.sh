#!/bin/bash
# ai-infra SessionStart emitter. Raw stdout is injected as context (verified: plain text, exit 0). Never fails: hooks.json appends `; exit 0`.
cat >/dev/null                      # drain stdin JSON; unused here
ROOT="${CLAUDE_PLUGIN_ROOT:?}"
sed "s|{{PLUGIN_ROOT}}|$ROOT|g" "$ROOT/hooks/rules.md"
TOP=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -e "$TOP/AGENTS.md" ] || echo "This is a git repo with no AGENTS.md. Tell the human once: \`/init\` detects the project and generates one; you cannot run it."
exit 0
