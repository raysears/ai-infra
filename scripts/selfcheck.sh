#!/usr/bin/env bash
# ai-infra selfcheck: run before every push. No network, no model, under ten seconds.
#
# Why it exists: a hook that exits non-zero fails open silently, and a skill whose description
# holds an unquoted ': ' loads with ALL frontmatter dropped. Neither shows an error; both make the
# plugin do nothing. This is the plugin's own version of the rule /init enforces on projects:
# run it before you ship it.
set -euo pipefail
cd "$(dirname "$0")/.."
ok() { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 1. The manifest and the marketplace parse under the strict validator.
claude plugin validate --strict . >"$TMP/v1" 2>&1 || fail "claude plugin validate --strict . : $(cat "$TMP/v1")"
claude plugin validate --strict .claude-plugin/plugin.json >"$TMP/v2" 2>&1 || fail "claude plugin validate --strict .claude-plugin/plugin.json : $(cat "$TMP/v2")"
ok "plugin validate (marketplace.json, plugin.json)"

# 2. Frontmatter: quoted descriptions, agent keys, skill names.
fm() { awk 'NR==1 && $0 != "---" { exit 1 } NR>1 && $0 == "---" { exit } NR>1 { print }' "$1"; }
for f in skills/*/SKILL.md agents/*.md; do
  [ -e "$f" ] || fail "no file matches $f"
  block=$(fm "$f") || fail "$f: no frontmatter block"
  desc=$(printf '%s\n' "$block" | sed -nE 's/^description:[[:space:]]*//p' | head -1)
  [ -n "$desc" ] || fail "$f: no description"
  case "$desc" in
    *": "*) case "$desc" in \"*|\'*) ;; *) fail "$f: description contains ': ' and is unquoted (YAML fails, ALL frontmatter is dropped)";; esac;;
  esac
done
for f in skills/*/SKILL.md; do
  folder=$(basename "$(dirname "$f")")
  name=$(fm "$f" | sed -nE 's/^name:[[:space:]]*//p' | head -1)
  [ "$name" = "$folder" ] || fail "$f: name '$name' does not match folder '$folder'"
done
for f in agents/*.md; do
  for k in $(fm "$f" | sed -nE 's/^([A-Za-z_-]+):.*/\1/p'); do
    case "$k" in name|description|tools) ;; *) fail "$f: frontmatter key '$k' (agents take only name, description, tools)";; esac
  done
done
ok "frontmatter"

# 3. Rules file shape and hooks.json.
n=$(wc -l <hooks/rules.md | tr -d ' ')
[ "$n" -le 25 ] || fail "hooks/rules.md is $n lines; cap is 25, delete a whole sentence"
c=$({ grep -o '{{PLUGIN_ROOT}}' hooks/rules.md || true; } | wc -l | tr -d ' ')
[ "$c" -eq 1 ] || fail "hooks/rules.md carries {{PLUGIN_ROOT}} $c times; exactly one (the notify line)"
python3 -m json.tool hooks/hooks.json >/dev/null || fail "hooks/hooks.json does not parse"
ok "rules.md ($n lines) and hooks.json"

# 4. SessionStart emitter: raw stdout, substituted, exit 0.
mkdir -p "$TMP/proj"
out=$(echo '{"hook_event_name":"SessionStart","source":"startup"}' | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PROJECT_DIR="$TMP/proj" bash hooks/session.sh) || fail "session.sh exited non-zero"
case "$out" in *origin/*) ;; *) fail "session.sh output lacks the rules (no 'origin/')";; esac
case "$out" in *'{{'*) fail "session.sh left a {{PLUGIN_ROOT}} unsubstituted";; esac
ok "session.sh"

# 5. SubagentStart emitter: the JSON form is the only one that lands.
out=$(echo '{}' | CLAUDE_PLUGIN_ROOT="$PWD" bash hooks/subagent.sh) || fail "subagent.sh exited non-zero"
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="SubagentStart" and d["additionalContext"].strip()' \
  || fail "subagent.sh output is not the hookSpecificOutput JSON form with a non-empty additionalContext"
case "$out" in *"## Things that surprise people"*) fail "subagent.sh emitted a surprises section with no AGENTS.md present";; esac
printf '# X\n\n## Things that surprise people\n\n- **trap one.** _(bit 2026-01-01; cost: x)_\n\n## Guards\n\n| a | b |\n' >"$TMP/proj/AGENTS.md"
out=$(echo '{}' | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PROJECT_DIR="$TMP/proj" bash hooks/subagent.sh) || fail "subagent.sh exited non-zero with an AGENTS.md"
printf '%s' "$out" | python3 -c 'import json,sys; c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]; assert "origin/" in c and "trap one" in c and "## Guards" not in c, c' \
  || fail "subagent.sh did not append the live surprises section (and only that section) after the rules"
rm -f "$TMP/proj/AGENTS.md"
ok "subagent.sh"

# 6. Commit guard: deny on main, silent on a topic branch, silent on other commands, fails open on garbage.
R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" -c user.email=selfcheck@ai-infra -c user.name=selfcheck commit -q --allow-empty -m init
guard() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$R" | bash hooks/guard-main.sh; }
out=$(guard "git commit -m x") || fail "guard-main.sh exited non-zero on main"
case "$out" in *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) ;; *) fail "guard-main.sh did not deny a commit on main: '$out'";; esac
git -C "$R" checkout -q -b topic
out=$(guard "git commit -m x") || fail "guard-main.sh exited non-zero on topic"
[ -z "$out" ] || fail "guard-main.sh spoke on a topic branch: '$out'"
out=$(guard "git status") || fail "guard-main.sh exited non-zero on git status"
[ -z "$out" ] || fail "guard-main.sh spoke on git status: '$out'"
out=$(printf 'notjson' | bash hooks/guard-main.sh) || fail "guard-main.sh exited non-zero on malformed stdin (must fail open)"
[ -z "$out" ] || fail "guard-main.sh spoke on malformed stdin: '$out'"
ok "guard-main.sh"

# 7. Scripts and templates parse.
for s in templates/new_worktree.sh scripts/detect.sh scripts/notify.sh; do bash -n "$s" || fail "$s: bash -n"; done
sed -e 's/{{TEST_COLLECT_ARGV}}/["python","-m","pytest","--collect-only","-q"]/' -e 's/{{RUNNER_PREFIX}}/python -m/' templates/test_docs.py >"$TMP/test_docs.py"
python3 -m py_compile "$TMP/test_docs.py" || fail "templates/test_docs.py does not compile once its slots are filled"
ok "bash -n and py_compile"

# 8. Detection on the plugin itself: no ecosystem, trailing block, DETECT_OK.
out=$(bash scripts/detect.sh) || fail "detect.sh exited non-zero"
case "$out" in *DETECT_OK=1*) ;; *) fail "detect.sh did not print DETECT_OK=1";; esac
case "$out" in *ECOSYSTEM=*) fail "detect.sh found an ecosystem in the plugin repo; it has none";; esac
ok "detect.sh"

# 9. Notify is a no-op without a topic.
NTFY_TOPIC= bash scripts/notify.sh a b || fail "notify.sh exited non-zero with NTFY_TOPIC unset"
ok "notify.sh"

# 10. Vendored files carry their attribution; the MIT notice ships.
for f in skills/grill-me/SKILL.md skills/grilling/SKILL.md skills/writing-for-agents/SKILL.md skills/writing-for-agents/SKILL-MECHANICS.md; do
  grep -q 'Vendored from' "$f" || fail "$f: missing 'Vendored from' attribution"
done
grep -q 'Adapted from' skills/handover/SKILL.md || fail "skills/handover/SKILL.md: missing 'Adapted from' attribution"
grep -q 'Matt Pocock' LICENSES/mattpocock-skills.MIT.txt || fail "LICENSES/mattpocock-skills.MIT.txt: not the upstream MIT notice"
ok "vendored attribution"

# 11. The deny list ships in two files that must agree byte for byte: the settings template and the doc test's _REQUIRED_DENIES.
python3 - <<'PY' || fail "templates/settings.json deny list and templates/test_docs.py _REQUIRED_DENIES differ"
import ast, json, re
denies = {d for d in json.load(open("templates/settings.json"))["permissions"]["deny"] if not d.startswith("__")}
src = open("templates/test_docs.py").read()
required = set(ast.literal_eval(re.search(r"_REQUIRED_DENIES = (\[.*?\])", src, re.S).group(1)))
assert denies == required, f"settings-only {denies - required}, test-only {required - denies}"
PY
ok "deny list agrees (settings.json, test_docs.py)"

# 12. The bullet trailer /lesson writes and the env item /init writes must match the regex test_docs checks.
python3 - <<'PY' || fail "a bullet in the documented format fails templates/test_docs.py's trailer regex"
import re
trailer = re.compile(re.search(r'trailer = re\.compile\(r"(.*?)"\)', open("templates/test_docs.py").read()).group(1))
lesson = open("skills/lesson/SKILL.md").read()
fmt = re.search(r"^- \*\*<mechanism>.*$", lesson, re.M).group(0).replace("<DATE>", "2026-01-01").replace("<cost>", "two hours")
env = re.search(r"^- \*\*The local `\{\{ENV_FILE\}\}`.*$", open("templates/AGENTS.md").read(), re.M).group(0).replace("{{DATE}}", "2026-01-01")
init = "- **x.** y. Check: `z`. Deliberate when: never. _(recorded 2026-01-01 by /init; cost if wrong: a)_"
for b in (fmt, env, init):
    assert trailer.search(b), b
PY
ok "bullet trailer agrees (lesson, AGENTS.md template, test_docs.py)"

# 13. Cache drift: an installed plugin is a COPY, so an edit to the cache changes what actually
# runs while the repo stays clean and git stays silent. That happened once (2026-09-07: another
# agent added the allow-main opt-out to the cache, not here, where the next reinstall would have
# deleted it). Compare the repo against the cache of the version this repo declares; any other
# version is a stale install, not drift.
VER=$(python3 -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["version"])')
MKT=$(python3 -c 'import json;print(json.load(open(".claude-plugin/marketplace.json"))["name"])')
CACHE="$HOME/.claude/plugins/cache/$MKT/$(python3 -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["name"])')/$VER"
if [ -d "$CACHE" ]; then
  diff -rq "$CACHE" . -x .git -x .in_use >"$TMP/drift" 2>&1 \
    || fail "the installed copy at $VER differs from this repo, so what runs is not what is committed.
Re-sync: claude plugin uninstall ai-infra@$MKT && claude plugin install ai-infra@$MKT
$(cat "$TMP/drift")"
  ok "cache matches repo ($VER)"
else
  ok "cache drift (not installed at $VER; nothing to compare)"
fi

echo "selfcheck: all green"
