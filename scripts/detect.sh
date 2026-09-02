#!/usr/bin/env bash
# ai-infra detect.sh: read-only project detection for /init and the scout.
#
# Prints KEY=VALUE lines: one block per detected ecosystem (starts with ECOSYSTEM=, DIR= names the
# subdir in a multi-ecosystem repo, empty at the root), then one shared trailing block, then DETECT_OK=1
# so a caller can tell a crash from an empty result. An empty value means not detected; the key is printed anyway.
#
# Every value is a candidate, never a fact: nothing here runs a project command. /init verifies each
# one by running it. The only executions are command -v, <tool> --version, git, grep, sed, awk, and
# python3 for package.json. A model guessing commands is how `cd seo_pipeline` shipped and stayed
# broken for months (2026-08-26); a script that reads the tree cannot invent a directory.
#
# set -u, never set -e: a missing tool must not abort detection. The empty value is the signal.
set -u
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=.
cd "$TOP" || exit 1

D=.          # directory being scanned
DIR=""       # its label in the output ("" at the root)
DESTRUCTIVE=""

kv() { printf '%s=%s\n' "$1" "$2"; }
# Command values in a subdir block are written the way they must be run: from that subdir.
cmd() {
  if [ -n "$DIR" ] && [ -n "$2" ]; then printf '%s=(cd %s && %s)\n' "$1" "$DIR" "$2"; else kv "$1" "$2"; fi
}
deny() { DESTRUCTIVE="$DESTRUCTIVE$1"$'\n'; }
rgrep() { grep -rqs --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=target --exclude-dir=vendor "$@"; }
emit_block() {
  kv ECOSYSTEM "$1"; kv DIR "$DIR"; kv PM "$2"
  cmd INSTALL "$3"; cmd TEST "$4"; cmd TEST_VERIFY "$5"; cmd LINT "$6"; cmd LINT_VERIFY "$7"
  cmd BUILD "$8"; cmd BUILD_VERIFY "$9"; cmd RUN "${10}"; cmd RUN_VERIFY "${11}"
  kv TEST_FRAMEWORK "${12}"; kv FRAMEWORK "${13}"; echo
}

# ---------- node ----------
NODE_PY='
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
s = d.get("scripts") or {}
deps = {}
for k in ("dependencies", "devDependencies"):
    deps.update(d.get(k) or {})
one = lambda v: (v or "").replace("\t", " ").replace("\n", " ")
print("PM\t" + (d.get("packageManager") or "").split("@")[0])
for k in ("test", "lint", "eslint", "build", "dev", "start", "typecheck"):
    print("S_" + k + "\t" + one(s.get(k)))
fw = [f for f in ("next", "nuxt", "express", "fastify", "vite") if f in deps]
if any(k == "remix" or k.startswith("@remix-run/") for k in deps):
    fw.append("remix")
print("FW\t" + ",".join(fw))
tfw = [f for f in ("vitest", "jest", "mocha") if f in deps]
if "playwright" in deps or "@playwright/test" in deps:
    tfw.append("playwright")
print("TFW\t" + ",".join(tfw))
# A script body can hide a force-push or a drop behind a harmless name: `preview` was `git push ... --force-with-lease` (2026-09-02).
bad = re.compile(r"git push.*(--force|-f\b)|\bdrop\b")
print("DS\t" + ",".join(k for k, v in s.items() if k in ("db:reset", "db:push") or re.match(r"(migrate|deploy|seed)", k) or bad.search(one(v))))
print("PMIG\t" + ("1" if any("prisma migrate deploy" in one(v) for v in s.values()) else ""))
print("PPUSH\t" + ("1" if any("prisma db push" in one(v) for v in s.values()) else ""))
'
detect_node() {
  local pm="" s_test="" s_lint="" s_eslint="" s_build="" s_dev="" s_start="" s_typecheck="" fw="" tfw="" ds="" pmig="" ppush=""
  local k v INSTALL="" TEST="" LINT="" BUILD="" RUN="" RUNV="" name
  while IFS=$'\t' read -r k v; do
    case "$k" in
      PM) pm=$v;; S_test) s_test=$v;; S_lint) s_lint=$v;; S_eslint) s_eslint=$v;; S_build) s_build=$v;;
      S_dev) s_dev=$v;; S_start) s_start=$v;; S_typecheck) s_typecheck=$v;; FW) fw=$v;; TFW) tfw=$v;;
      DS) ds=$v;; PMIG) pmig=$v;; PPUSH) ppush=$v;;
    esac
  done < <(python3 -c "$NODE_PY" "$D/package.json" 2>/dev/null)
  if [ -z "$pm" ]; then
    if [ -e "$D/bun.lockb" ] || [ -e "$D/bun.lock" ]; then pm=bun
    elif [ -e "$D/pnpm-lock.yaml" ]; then pm=pnpm
    elif [ -e "$D/yarn.lock" ]; then pm=yarn
    else pm=npm; fi
  fi
  case "$pm" in
    # ponytail: `npm ci` refuses to run without a lockfile, so a lockless repo gets `npm install`.
    npm) if [ -e "$D/package-lock.json" ]; then INSTALL="npm ci"; else INSTALL="npm install"; fi;;
    pnpm) INSTALL="pnpm install --frozen-lockfile";;
    yarn) INSTALL="yarn install --frozen-lockfile";;
    bun) INSTALL="bun install --frozen-lockfile";;
  esac
  # A script that is literally npm's default stub (`echo "Error: no test specified"`) is no test.
  case "$s_test" in "") ;; *"no test specified"*) ;; *) if [ "$pm" = bun ]; then TEST="bun run test"; else TEST="$pm test"; fi;; esac
  if [ -n "$s_lint" ]; then LINT="$pm run lint"; elif [ -n "$s_eslint" ]; then LINT="$pm run eslint"; fi
  [ -n "$s_typecheck" ] && LINT="${LINT:+$LINT && }$pm run typecheck"
  [ -n "$s_build" ] && BUILD="$pm run build"
  if [ -n "$s_dev" ]; then
    RUN="$pm run dev"; RUNV="node -e \"process.exit(require('./package.json').scripts.dev?0:1)\" && command -v $pm"
  elif [ -n "$s_start" ]; then
    RUN="$pm run start"; RUNV="node -e \"process.exit(require('./package.json').scripts.start?0:1)\" && command -v $pm"
  fi
  for name in $(printf '%s' "$ds" | tr , ' '); do deny "Bash($pm run $name*)"; done
  [ -n "$pmig" ] && deny "Bash(npx prisma migrate deploy*)"
  [ -n "$ppush" ] && deny "Bash(npx prisma db push*)"
  emit_block node "$pm" "$INSTALL" "$TEST" "$TEST" "$LINT" "$LINT" "$BUILD" "$BUILD" "$RUN" "$RUNV" "$tfw" "$fw"
}

# ---------- python ----------
detect_python() {
  local pp="$D/pyproject.toml" req="$D/requirements.txt" pm="" runner="" py=python ruff=ruff uvicorn=uvicorn flask=flask
  local INSTALL="" TEST="" TESTV="" LINT="" RUN="" RUNV="" tfw="" fw="" mod=""
  if [ -e "$D/uv.lock" ] || grep -qs '^\[tool\.uv' "$pp"; then pm=uv; runner="uv run "
  elif [ -e "$D/poetry.lock" ] || grep -qs '^\[tool\.poetry' "$pp"; then pm=poetry; runner="poetry run "
  else
    pm=pip
    if [ -d "$D/.venv" ]; then py=.venv/bin/python; ruff=.venv/bin/ruff; uvicorn=.venv/bin/uvicorn; flask=.venv/bin/flask; fi
  fi
  case "$pm" in
    uv) INSTALL="uv sync --frozen";;
    poetry) INSTALL="poetry install";;
    pip) if [ -e "$req" ]; then INSTALL="$py -m pip install -r requirements.txt"; else INSTALL="$py -m pip install -e ."; fi;;
  esac
  if [ "$pm" != pip ] || [ -d "$D/tests" ] || [ -e "$D/pytest.ini" ] || grep -qs '^\[tool\.pytest' "$pp"; then
    tfw=pytest
    if [ "$pm" = pip ]; then TEST="$py -m pytest"; else TEST="${runner}pytest"; fi
    TESTV="$TEST --collect-only -q"
  else
    tfw=unittest; TEST="$py -m unittest discover"; TESTV="$py -m unittest discover -h"
  fi
  local ruff_conf="" ruff_dep=""
  { grep -qs '^\[tool\.ruff' "$pp" || [ -e "$D/ruff.toml" ] || [ -e "$D/.ruff.toml" ]; } && ruff_conf=1
  grep -qsE '(^|["'"'"' ])ruff([]"'"'"'>=<~ ,]|$)' "$pp" "$req" && ruff_dep=1
  if [ "$pm" = pip ]; then
    if [ -n "$ruff_conf" ] && { [ -x "$D/.venv/bin/ruff" ] || command -v ruff >/dev/null 2>&1; }; then LINT="$ruff check ."; fi
  elif [ -n "$ruff_dep" ] || [ -n "$ruff_conf" ]; then LINT="${runner}ruff check ."; fi
  if grep -qs fastapi "$pp" "$req" && grep -qs uvicorn "$pp" "$req"; then
    if grep -qsE '^app *= *' "$D/main.py"; then mod=main; elif grep -qsE '^app *= *' "$D/app.py"; then mod=app; fi
    fw=fastapi
    [ -n "$mod" ] && RUN="${runner}${uvicorn} $mod:app --reload" && RUNV="${runner}${py} -c \"import $mod; $mod.app\""
  elif [ -e "$D/manage.py" ]; then
    fw=django; RUN="${runner}${py} manage.py runserver"; RUNV="${runner}${py} manage.py check"
    deny "Bash(* manage.py migrate*)"; deny "Bash(* manage.py flush*)"
  elif grep -qsiE '(^|["'"'"' ])flask([]"'"'"'>=<~ ,]|$)' "$pp" "$req"; then
    fw=flask; RUN="${runner}${flask} run"; RUNV="${runner}${flask} --version"
  fi
  if grep -rqs -- '--apply' "$D/scripts" "$D/bin" 2>/dev/null; then
    case "$pm" in
      uv) deny "Bash(uv run * --apply*)";;
      poetry) deny "Bash(poetry run * --apply*)";;
      pip) deny "Bash(python * --apply*)"; [ "$py" != python ] && deny "Bash($py * --apply*)";;
    esac
  fi
  rgrep --include='*.py' --include='*.sh' --include='*.cfg' --include='*.ini' --include=Makefile 'alembic upgrade' "$D" && deny "Bash(${runner}alembic upgrade*)"
  emit_block python "$pm" "$INSTALL" "$TEST" "$TESTV" "$LINT" "$LINT" "" "" "$RUN" "$RUNV" "$tfw" "$fw"
}

# ---------- rust ----------
detect_rust() {
  local LINT="cargo fmt --check" RUN="" RUNV=""
  cargo clippy --version >/dev/null 2>&1 && LINT="cargo clippy --all-targets && cargo fmt --check"
  if [ -e "$D/src/main.rs" ] || grep -qs '^\[\[bin\]\]' "$D/Cargo.toml"; then
    RUN="cargo run"; RUNV="cargo metadata --no-deps --format-version 1 >/dev/null"
  fi
  rgrep --include='*.rs' --include='*.sh' --include='*.toml' --include=Makefile --include=justfile 'sqlx migrate run' "$D" && deny "Bash(sqlx migrate run*)"
  rgrep --include='*.rs' --include='*.sh' --include='*.toml' --include=Makefile --include=justfile 'diesel migration run' "$D" && deny "Bash(diesel migration run*)"
  emit_block rust cargo "cargo fetch" "cargo test" "cargo test --no-run" "$LINT" "$LINT" "cargo build" "cargo build" "$RUN" "$RUNV" "cargo-test" ""
}

# ---------- go ----------
detect_go() {
  local LINT="go vet ./..." RUN="" RUNV="" pkg="" first
  if ls "$D"/.golangci.yml "$D"/.golangci.yaml >/dev/null 2>&1 && command -v golangci-lint >/dev/null 2>&1; then LINT="$LINT && golangci-lint run"; fi
  if [ -e "$D/main.go" ]; then pkg=.
  else
    first=$(ls -d "$D"/cmd/*/ 2>/dev/null | head -1)
    [ -n "$first" ] && pkg="./cmd/$(basename "$first")"
  fi
  [ -n "$pkg" ] && RUN="go run $pkg" && RUNV="go build -o /dev/null $pkg"
  rgrep --include=Makefile --include='*.sh' --include=justfile 'migrate -path' "$D" && deny "Bash(migrate -path * up*)"
  rgrep --include=Makefile --include='*.sh' --include=justfile 'goose up' "$D" && deny "Bash(goose up*)"
  emit_block go go "go mod download" "go test ./..." "go test -count=1 -run '^\$' ./..." "$LINT" "$LINT" "go build ./..." "go build ./..." "$RUN" "$RUNV" "go-test" ""
}

# ---------- ruby ----------
detect_ruby() {
  local TEST="" TESTV="" LINT="" RUN="" RUNV="" tfw="" fw=""
  if [ -d "$D/spec" ] || [ -e "$D/.rspec" ]; then tfw=rspec; TEST="bundle exec rspec"; TESTV="bundle exec rspec --dry-run"
  elif [ -d "$D/test" ]; then tfw=minitest; TEST="bundle exec rake test"; TESTV="bundle exec rake -T | grep -q '^rake test'"; fi
  [ -e "$D/.rubocop.yml" ] && LINT="bundle exec rubocop"
  if [ -e "$D/bin/rails" ]; then
    fw=rails; RUN="bin/rails server"; RUNV="test -x bin/rails"
    # db:migrate:status is the read-only exception /init may allow; a deny outranks an allow, so it is not emitted here.
    deny "Bash(bin/rails db:*)"
  fi
  emit_block ruby bundler "bundle install" "$TEST" "$TESTV" "$LINT" "$LINT" "" "" "$RUN" "$RUNV" "$tfw" "$fw"
}

scan_dir() {
  D=$1; DIR=$2
  [ -e "$D/package.json" ] && detect_node
  { [ -e "$D/pyproject.toml" ] || [ -e "$D/requirements.txt" ] || [ -e "$D/setup.py" ] || [ -e "$D/setup.cfg" ]; } && detect_python
  [ -e "$D/Cargo.toml" ] && detect_rust
  [ -e "$D/go.mod" ] && detect_go
  [ -e "$D/Gemfile" ] && detect_ruby
  return 0
}
scan_dir . ""
for sub in apps/* packages/* backend frontend; do
  [ -d "$sub" ] || continue
  scan_dir "$sub" "$sub"
done
D=.; DIR=""

# ---------- trailing block ----------
# make / just: the project's own entry point wins over the derived spelling; /init allows both.
MAKE_TARGETS=""; MAKE_TEST=""; MAKE_TEST_VERIFY=""; MAKE_LINT=""; MAKE_LINT_VERIFY=""; MAKE_BUILD=""; MAKE_BUILD_VERIFY=""
if [ -e Makefile ]; then
  t=$(grep -oE '^(test|lint|build):' Makefile | tr -d : | sort -u | paste -sd, -)
  [ -n "$t" ] && MAKE_TARGETS="$t (Makefile)"
  grep -qE '^test:' Makefile && MAKE_TEST="make test" && MAKE_TEST_VERIFY="make -n test"
  grep -qE '^lint:' Makefile && MAKE_LINT="make lint" && MAKE_LINT_VERIFY="make -n lint"
  grep -qE '^build:' Makefile && MAKE_BUILD="make build" && MAKE_BUILD_VERIFY="make -n build"
  for t in $(grep -oE '^[A-Za-z0-9_-]+:' Makefile | tr -d : | grep -E 'deploy|release|migrate|reset|apply'); do deny "Bash(make $t*)"; done
fi
if [ -e justfile ]; then
  t=$(grep -oE '^(test|lint|build)(:| )' justfile | sed 's/[: ]$//' | sort -u | paste -sd, -)
  [ -n "$t" ] && MAKE_TARGETS="${MAKE_TARGETS:+$MAKE_TARGETS,}$t (justfile)"
  [ -z "$MAKE_TEST" ] && grep -qE '^test(:| )' justfile && MAKE_TEST="just test" && MAKE_TEST_VERIFY="just -n test"
  [ -z "$MAKE_LINT" ] && grep -qE '^lint(:| )' justfile && MAKE_LINT="just lint" && MAKE_LINT_VERIFY="just -n lint"
  [ -z "$MAKE_BUILD" ] && grep -qE '^build(:| )' justfile && MAKE_BUILD="just build" && MAKE_BUILD_VERIFY="just -n build"
  for t in $(grep -oE '^[A-Za-z0-9_-]+(:| )' justfile | sed 's/[: ]$//' | grep -E 'deploy|release|migrate|reset|apply'); do deny "Bash(just $t*)"; done
fi
kv MAKE_TARGETS "$MAKE_TARGETS"
kv MAKE_TEST "$MAKE_TEST"; kv MAKE_TEST_VERIFY "$MAKE_TEST_VERIFY"
kv MAKE_LINT "$MAKE_LINT"; kv MAKE_LINT_VERIFY "$MAKE_LINT_VERIFY"
kv MAKE_BUILD "$MAKE_BUILD"; kv MAKE_BUILD_VERIFY "$MAKE_BUILD_VERIFY"

# GitHub Actions: the first `run:` line per token. A `run: |` block scalar yields its first command line.
# ponytail: substring match, install lines skipped (`pip install pytest` is not a test command); /init runs whatever lands here.
CI_TEST=""; CI_LINT=""; CI_BUILD=""; CI_FILE=""; GH_DEPLOY=""
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -e "$wf" ] || continue
  runs=$(awk '
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*/ { sub(/^[[:space:]]*-?[[:space:]]*run:[[:space:]]*/, "")
      if ($0 ~ /^[|>][-+]?[[:space:]]*$/) { want = 1; next }
      print; next }
    want && NF { sub(/^[[:space:]]+/, ""); print; want = 0 }' "$wf" | grep -viE 'install' || true)
  if [ -z "$CI_TEST" ]; then CI_TEST=$(printf '%s\n' "$runs" | grep -m1 -i 'test' || true); [ -n "$CI_TEST" ] && CI_FILE=${CI_FILE:-$wf}; fi
  if [ -z "$CI_LINT" ]; then CI_LINT=$(printf '%s\n' "$runs" | grep -m1 -i 'lint' || true); [ -n "$CI_LINT" ] && CI_FILE=${CI_FILE:-$wf}; fi
  if [ -z "$CI_BUILD" ]; then CI_BUILD=$(printf '%s\n' "$runs" | grep -m1 -i 'build' || true); [ -n "$CI_BUILD" ] && CI_FILE=${CI_FILE:-$wf}; fi
  if printf '%s' "$(basename "$wf")" | grep -qiE 'deploy|release|publish' || grep -qiE '^name:.*(deploy|release|publish)' "$wf"; then GH_DEPLOY=1; fi
done
kv CI_TEST "$CI_TEST"; kv CI_LINT "$CI_LINT"; kv CI_BUILD "$CI_BUILD"; kv CI_FILE "$CI_FILE"

DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
kv DEFAULT_BRANCH "${DEFAULT_BRANCH:-main}"

ENV_FILE=""; [ -e .env ] && ENV_FILE=.env
kv ENV_FILE "$ENV_FILE"
# Names only, never values: this output lands in a transcript and in AGENTS.md.
ENV_NAMES=$(cat .env.example .env.sample .env 2>/dev/null | sed -nE 's/^([A-Z][A-Z0-9_]*)=.*/\1/p' | sort -u)
kv ENV_VARS "$(printf '%s\n' "$ENV_NAMES" | paste -sd, - | sed 's/^,//')"

SHARED=""
add_shared() { SHARED="${SHARED:+$SHARED,}$1"; }
has_var() { printf '%s\n' "$ENV_NAMES" | grep -qE "$1"; }
has_var '^(DATABASE_URL|POSTGRES_)' && add_shared postgres
has_var '^SUPABASE_' && add_shared supabase
has_var '^REDIS_URL' && add_shared redis
has_var '^MONGO' && add_shared mongo
has_var '^AWS_' && add_shared s3
has_var '^STRIPE' && add_shared stripe
has_var '^TWILIO' && add_shared twilio
has_var '^SMTP' && add_shared smtp
has_var '^RESEND' && add_shared resend
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  [ -e "$f" ] || continue
  svcs=$(awk '/^services:/ { inside = 1; next } inside && /^[^[:space:]#]/ { inside = 0 } inside && /^  [A-Za-z0-9_-]+:/ { sub(/^  /, ""); sub(/:.*/, ""); print }' "$f" | paste -sd/ -)
  [ -n "$svcs" ] && add_shared "docker-compose:$svcs"
  break
done
kv SHARED "$SHARED"

DEPLOY=""
add_deploy() { DEPLOY="${DEPLOY:+$DEPLOY,}$1"; }
{ [ -e railway.json ] || [ -e railway.toml ]; } && add_deploy railway && deny "Bash(railway up*)"
[ -e fly.toml ] && add_deploy fly && deny "Bash(fly deploy*)"
[ -e vercel.json ] && add_deploy vercel && deny "Bash(vercel --prod*)"
[ -e Procfile ] && add_deploy heroku
[ -e Dockerfile ] && add_deploy docker
[ -n "$GH_DEPLOY" ] && add_deploy gh-actions-deploy
ls ./*.tf >/dev/null 2>&1 && deny "Bash(terraform apply*)"
kv DEPLOY "$DEPLOY"

# One DESTRUCTIVE= line per deny pattern (the newline-separated form that stays KEY=VALUE per line).
if [ -n "$DESTRUCTIVE" ]; then
  printf '%s' "$DESTRUCTIVE" | sort -u | while IFS= read -r p; do kv DESTRUCTIVE "$p"; done
else
  kv DESTRUCTIVE ""
fi

PRIVATE=""
[ -e .env ] && PRIVATE=.env
for f in *.pem *.key credentials*.json; do
  [ -e "$f" ] || continue
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && continue   # tracked is not private
  PRIVATE="${PRIVATE:+$PRIVATE,}$f"
done
kv PRIVATE_FILES "$PRIVATE"
kv DETECT_OK 1
exit 0
