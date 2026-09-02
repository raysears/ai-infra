#!/bin/bash
# ai-infra SubagentStart emitter. Raw stdout is DROPPED for SubagentStart (verified 2026-09); the JSON form below is the only one that lands. Never fails: hooks.json appends `; exit 0`.
# The project's "Things that surprise people" rides along: the pr-reviewer's trap list arrives mechanically at every spawn instead of by a prose instruction to go and read it. Nothing extra when the file or section is absent.
cat >/dev/null
ROOT="${CLAUDE_PLUGIN_ROOT:?}"
{
  sed "s|{{PLUGIN_ROOT}}|$ROOT|g" "$ROOT/hooks/rules.md"
  awk '/^## /{p=/^## Things that surprise people/} p' "${CLAUDE_PROJECT_DIR:-.}/AGENTS.md" 2>/dev/null
} | python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":sys.stdin.read()}}))'
exit 0
