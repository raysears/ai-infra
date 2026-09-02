"""
The commands, paths and guards AGENTS.md documents must hold against the tree.

AGENTS.md is auto-loaded every session (CLAUDE.md is a symlink to it), so a broken line there
is read by every agent and every new human. Two headline commands once began
`cd <a directory that never existed> &&` and stayed broken for months; nobody ran them,
which quietly discounted everything else in the file (2026-08-26). The same day, four widening
mutations to the permission lists (`git add -A*` no longer covering `--all`, a blanket runner
wildcard in allow) left 1508 tests green: nothing read the settings back.

Deliberately structural, never prose: this must not become a thing that fails because someone reworded a sentence.
Every check resolves a path, parses a fence, or reads a setting. The one execution is the test
runner's own collect-only form: the command that proves the toolchain answers, and runs no test.

Not included: coverage-not-count of a route table and its shrink-only ratchet. That is
project-specific introspection; add it via /lesson once this project has a route table.
"""

import json
import re
import shlex
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
AGENTS = ROOT / "AGENTS.md"
SETTINGS = ROOT / ".claude" / "settings.json"
GITIGNORE = ROOT / ".gitignore"
TEXT = AGENTS.read_text()
# HTML comments carry the format examples, not claims about the tree.
BODY = re.sub(r"<!--.*?-->", "", TEXT, flags=re.DOTALL)

_TEST_COLLECT_ARGV = {{TEST_COLLECT_ARGV}}
_RUNNER_PREFIX = "{{RUNNER_PREFIX}}"
_TOPLEVEL_SUB = "$(git rev-parse --show-toplevel)"
_PATH_SUFFIXES = (".py", ".sh", ".md", ".json", ".yml", ".yaml", ".txt", ".sql", ".html",
                  ".ts", ".js", ".go", ".rs", ".rb")
# Verbatim from the ai-infra settings template. `git add -A*` does not cover `--all`, and
# `git add .*` would block `git add .claude/...`: every spelling is its own entry on purpose.
_REQUIRED_DENIES = [
    "Bash(git add -A*)", "Bash(git add --all*)", "Bash(git add .)", "Bash(git add -u*)",
    "Bash(git add --update*)",
    "Bash(git push --force*)", "Bash(git push -f*)", "Bash(git push * --force*)",
    "Bash(git push * -f*)",
    "Bash(git checkout .*)", "Bash(git restore .*)",
]


def _fenced_bash_commands() -> list[str]:
    blocks = re.findall(r"^[ \t]*```bash\n(.*?)^[ \t]*```", BODY, re.MULTILINE | re.DOTALL)
    assert blocks, "no ```bash fences in AGENTS.md: the Commands block is gone"
    commands = []
    for block in blocks:
        for line in block.splitlines():
            line = re.sub(r"\s+#.*$", "", line).strip()
            if line and not line.startswith("#"):
                commands.append(line)
    return commands


def _tokens(command: str) -> list[str]:
    try:
        parts = shlex.split(command, posix=True)
    except ValueError as exc:
        raise AssertionError(f"AGENTS.md documents a command no shell can parse ({exc}): {command!r}") from None
    # `(cd sub && cmd)` is how multi-ecosystem commands are written; the parens are not part of the tokens.
    # `$(git rev-parse --show-toplevel)` keeps its parens or it never equals _TOPLEVEL_SUB.
    return [t if t.startswith("$(") else t.strip("()") for t in parts if t not in ("&&", "||", "&", "|", ";")]


def _is_slot_token(token: str) -> bool:
    return any(c in token for c in "<>*?{}$") or "..." in token  # `./...` is Go's package glob


def _prose_paths() -> list[str]:
    body = re.sub(r"^[ \t]*```.*?^[ \t]*```", "", BODY, flags=re.MULTILINE | re.DOTALL)
    found = []
    for span in re.findall(r"`([^`\n]+)`", body):
        token = span.strip().split()[0] if span.strip() else ""
        if not token or _is_slot_token(token) or "(" in token:
            continue
        # A bare `module.py` or `MAP.md` is prose shorthand; a path has a directory in it.
        if token.startswith(("./", "../")) or (token.endswith(_PATH_SUFFIXES) and "/" in token):
            found.append(token)
    return sorted(set(found))


def _settings() -> dict:
    return json.loads(SETTINGS.read_text())["permissions"]


def _surprise_bullets() -> list[str]:
    section = re.search(r"^## Things that surprise people\n(.*?)(?=^## |\Z)", BODY, re.MULTILINE | re.DOTALL)
    assert section, "AGENTS.md has no `## Things that surprise people` section: the reviewer's trap list is gone"
    return [" ".join(b.splitlines()) for b in re.findall(r"^- \*\*.*(?:\n(?![-#\n]).*)*", section.group(1), re.MULTILINE)]


def test_no_unfilled_slots():
    assert "{{" not in TEXT, "AGENTS.md still carries an unfilled slot"


@pytest.mark.parametrize("command", _fenced_bash_commands())
def test_documented_cd_targets_exist(command):
    """The bug this pins: `cd <dir> && ...` where the directory never existed (2026-08-26)."""
    tokens = _tokens(command)
    for i, token in enumerate(tokens[:-1]):
        if token != "cd" or tokens[i + 1] == _TOPLEVEL_SUB:
            continue
        target = tokens[i + 1]
        assert not _is_slot_token(target), f"`cd {target}` cannot be resolved against the tree: {command!r}"
        assert (ROOT / target).is_dir(), f"`cd {target}` names a directory that does not exist: {command!r}"


@pytest.mark.parametrize("command", _fenced_bash_commands())
def test_documented_command_paths_exist(command):
    for token in _tokens(command):
        if _is_slot_token(token):
            continue
        if token.startswith(("./", "../", "/")) or token.endswith(_PATH_SUFFIXES):
            assert (ROOT / token).exists(), f"command names `{token}`, which does not exist (2026-08-26): {command!r}"


def test_there_are_prose_paths_to_check():
    """A broken extractor must fail here, not pass on nothing."""
    # The template alone yields two (`./scripts/new_worktree.sh`, `.claude/settings.json`).
    assert len(_prose_paths()) >= 2, f"prose path extractor found only {_prose_paths()}"


@pytest.mark.parametrize("token", _prose_paths())
def test_backticked_repo_path_exists(token):
    assert (ROOT / token).exists(), f"AGENTS.md names `{token}` in prose and it does not exist (2026-08-26)"


def test_relative_links_resolve():
    slugs = {re.sub(r"[^\w\s-]", "", h.lower()).strip().replace(" ", "-") for h in re.findall(r"^#+\s+(.*)$", BODY, re.MULTILINE)}
    for target in re.findall(r"\]\(([^)\s]+)\)", BODY):
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        path, _, anchor = target.partition("#")
        if path:
            assert (ROOT / path).exists(), f"link to `{path}` does not resolve"
        elif anchor:
            assert anchor in slugs, f"anchor `#{anchor}` matches no heading in AGENTS.md"


def test_no_hardcoded_test_count():
    assert not re.search(r"\b\d{2,4}\s+tests?\b", BODY), "a test count in AGENTS.md is stale within a day"


def test_test_command_actually_collects():
    """The documented test entry point must answer; collect-only runs no test."""
    proc = subprocess.run(_TEST_COLLECT_ARGV, cwd=ROOT, capture_output=True, text=True, timeout=300)
    assert proc.returncode == 0, f"`{' '.join(_TEST_COLLECT_ARGV)}` rc={proc.returncode}\n{proc.stdout[-2000:]}\n{proc.stderr[-2000:]}"
    match = re.search(r"\b(\d+) tests? collected", proc.stdout)
    assert match, f"`{' '.join(_TEST_COLLECT_ARGV)}` reported no collection:\n{proc.stdout[-2000:]}"
    if match.group(1) == "0":
        me = Path(__file__).resolve()
        others = [p for p in ROOT.rglob("test_*.py") if p.resolve() != me and ".venv" not in p.parts]
        assert not others, f"collected 0 tests while test files exist: {others[:5]}"


def test_destructive_commands_stay_denied():
    """Four widening mutations of this list were invisible to 1508 tests (2026-08-26)."""
    missing = [d for d in _REQUIRED_DENIES if d not in _settings()["deny"]]
    assert not missing, f"deny list lost {missing}"


def test_no_blanket_runner_wildcard_in_allow():
    """A blanket runner allow existed because unsupervised runs hang on prompts (2026-08-25); the fix is named allows."""
    forbidden = {f"Bash({_RUNNER_PREFIX} *)", f"Bash({_RUNNER_PREFIX}*)", f"Bash({_RUNNER_PREFIX}:*)"}
    present = forbidden & set(_settings()["allow"])
    assert not present, f"blanket runner wildcard in allow: {present}"


def test_sanctioned_actions_stay_allowed():
    """A run that prompts is a run that hangs."""
    missing = [a for a in ("Bash(gh pr comment:*)", "Bash(./scripts/new_worktree.sh:*)") if a not in _settings()["allow"]]
    assert not missing, f"allow list lost {missing}"


def test_gitignore_keeps_the_agent_entries_tracked():
    """Tracked ignore lines keep `git add .claude/...` safe on every clone; the reverse lost that (2026-08-26)."""
    lines = GITIGNORE.read_text().splitlines()
    missing = [l for l in (".claude/worktrees/", ".claude/settings.local.json") if l not in lines]
    assert not missing, f".gitignore lost {missing}"


def test_surprises_section_within_cap():
    """Cap 7: past it the oldest item becomes a guard or leaves. A trailer without a date and cost gets simplified away."""
    bullets = _surprise_bullets()
    assert len(bullets) <= 7, f"{len(bullets)} surprises on file; /lesson must promote or delete before adding"
    trailer = re.compile(r"_\((bit \d{4}-\d{2}-\d{2}; cost: .+|recorded \d{4}-\d{2}-\d{2}.*)\)_$")
    bad = [b for b in bullets if not trailer.search(b)]
    assert not bad, f"surprise without a `_(bit YYYY-MM-DD; cost: ...)_` trailer: {bad}"


def test_no_progress_file():
    """A status file an agent updates more often than it commits sat 19 days stale (2026-08-25); they live in .claude/state/."""
    present = [n for n in ("PROGRESS.md", "TODO.md", "HANDOFF.md") if (ROOT / n).exists()]
    assert not present, f"status file in the tracked tree: {present}"
