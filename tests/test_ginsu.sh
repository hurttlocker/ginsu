#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GINSU="$REPO_ROOT/ginsu"
BASE="$(mktemp -d)"
TMP="$BASE/state with space"
CW="codex_$$"
HW="claude_$$"
HR="claude_read_$$"
HB="claude_bypass_$$"

cleanup() {
  if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "kept test state: $BASE" >&2
    return
  fi
  tmux kill-session -t "ginsu-$CW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$HW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$HR" 2>/dev/null || true
  tmux kill-session -t "ginsu-$HB" 2>/dev/null || true
  rm -rf "$BASE"
}
trap cleanup EXIT

mkdir -p "$TMP/bin" "$TMP/repo"
git -C "$TMP/repo" init -q

cat > "$TMP/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -u
mode=first; out=""; prompt="${!#}"
printf '%s\n' "$*" >> "$(dirname "$0")/codex.args"
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  [ "$arg" = resume ] && mode=resume
  if [ "$arg" = -o ]; then j=$((i+1)); out="${!j}"; fi
done
if [ "$prompt" = fail ]; then echo "fake codex failure" >&2; exit 23; fi
[ "$prompt" = slow ] && sleep 0.3
reply="codex:$mode:$prompt"
python3 - "$reply" "$out" "$mode" "$prompt" <<'PY'
import json, sys
reply, outfile, mode, prompt = sys.argv[1:]
if mode == "first":
    print(json.dumps({"type":"thread.started","thread_id":"codex-session"}))
if prompt == "softfail":
    print(json.dumps({"type":"item.completed","item":{"type":"error","message":"fake codex stream error"}}))
else:
    print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":reply}}))
print(json.dumps({"type":"turn.completed","usage":{"input_tokens":5,"cached_input_tokens":2,"output_tokens":3}}))
open(outfile, "w").write(reply)
PY
FAKE_CODEX

cat > "$TMP/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -u
mode=first; sid=""; prompt="${!#}"
printf '%s\n' "$*" >> "$(dirname "$0")/claude.args"
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [ "$arg" = --resume ]; then mode=resume; j=$((i+1)); sid="${!j}"; fi
  if [ "$arg" = --session-id ]; then j=$((i+1)); sid="${!j}"; fi
done
if [ "$prompt" = fail ]; then echo "fake claude failure" >&2; exit 24; fi
[ "$prompt" = slow ] && sleep 0.3
reply="claude:$mode:$prompt"
python3 - "$reply" "$sid" "$prompt" <<'PY'
import json, sys
reply, sid, prompt = sys.argv[1:]
print(json.dumps({"type":"system","subtype":"init","session_id":sid}))
print(json.dumps({"type":"assistant","session_id":sid,"message":{"id":"m1","content":[{"type":"text","text":reply}]}}))
print(json.dumps({"type":"result","subtype":"error" if prompt == "softfail" else "success","is_error":prompt == "softfail","session_id":sid,"result":reply,"usage":{"input_tokens":7,"cache_read_input_tokens":4,"output_tokens":3}}))
PY
FAKE_CLAUDE
chmod +x "$TMP/bin/codex" "$TMP/bin/claude"

COMMON=(
  GINSU_HOME="$TMP/home"
  GINSU_TERM=tmux
  GINSU_CODEX="$TMP/bin/codex"
  GINSU_CLAUDE="$TMP/bin/claude"
  GINSU_TIMEOUT=20
)

g() { env "${COMMON[@]}" "$GINSU" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }
assert_has() { grep -F -- "$2" "$1" >/dev/null || fail "$1 does not contain $2"; }

bash -n "$GINSU"
assert_eq "$(g --version)" "ginsu 2.0.0"

g spawn "$CW" "$TMP/repo" --engine codex >/dev/null
assert_eq "$(g send "$CW" first)" "codex:first:first"
assert_eq "$(g send "$CW" second)" "codex:resume:second"
assert_has "$TMP/bin/codex.args" "--sandbox workspace-write"

g send "$CW" slow > "$TMP/slow.out" & p1=$!
g send "$CW" fast > "$TMP/fast.out" & p2=$!
wait "$p1"; wait "$p2"
assert_eq "$(cat "$TMP/slow.out")" "codex:resume:slow"
assert_eq "$(cat "$TMP/fast.out")" "codex:resume:fast"

if g send "$CW" fail > "$TMP/fail.out" 2>&1; then fail "failed Codex turn returned success"; fi
assert_has "$TMP/fail.out" "codex turn failed (exit 23)"
if g send "$CW" softfail > "$TMP/fail.out" 2>&1; then fail "Codex stream error returned success"; fi
assert_has "$TMP/fail.out" "fake codex stream error"
assert_eq "$(g send "$CW" recovered)" "codex:resume:recovered"

g restart "$CW" >/dev/null
assert_eq "$(cat "$TMP/home/$CW/engine")" codex
assert_eq "$(g send "$CW" restarted)" "codex:first:restarted"
g stop "$CW" >/dev/null

g spawn "$HW" "$TMP/repo" --engine claude >/dev/null
assert_eq "$(g send "$HW" first)" "claude:first:first"
assert_eq "$(g send "$HW" second)" "claude:resume:second"
assert_has "$TMP/bin/claude.args" "--permission-mode acceptEdits"
assert_has "$TMP/bin/claude.args" "--session-id"
assert_has "$TMP/bin/claude.args" "--resume"

if g send "$HW" fail > "$TMP/fail.out" 2>&1; then fail "failed Claude turn returned success"; fi
assert_has "$TMP/fail.out" "claude turn failed (exit 24)"
if g send "$HW" softfail > "$TMP/fail.out" 2>&1; then fail "Claude result error returned success"; fi
assert_has "$TMP/fail.out" "claude:resume:softfail"

if env "${COMMON[@]}" GINSU_DEPTH=1 "$GINSU" spawn nested "$TMP/repo" --engine codex > "$TMP/nested.out" 2>&1; then
  fail "nested worker was allowed without explicit override"
fi
assert_has "$TMP/nested.out" "nested workers are disabled"

g stop "$HW" >/dev/null

env "${COMMON[@]}" GINSU_SANDBOX=read "$GINSU" spawn "$HR" "$TMP/repo" --engine claude >/dev/null
env "${COMMON[@]}" "$GINSU" send "$HR" readmode >/dev/null
assert_has "$TMP/bin/claude.args" "--permission-mode plan"
env "${COMMON[@]}" "$GINSU" stop "$HR" >/dev/null

env "${COMMON[@]}" GINSU_SANDBOX=bypass "$GINSU" spawn "$HB" "$TMP/repo" --engine claude >/dev/null
env "${COMMON[@]}" "$GINSU" send "$HB" bypassmode >/dev/null
assert_has "$TMP/bin/claude.args" "--dangerously-skip-permissions"
env "${COMMON[@]}" "$GINSU" stop "$HB" >/dev/null

echo "PASS: both engines, resume, queue tickets, failures, restart, security mappings, and nesting guard"
