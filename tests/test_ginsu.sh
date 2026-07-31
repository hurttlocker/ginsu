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
has_sandbox=0
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  [ "$arg" = resume ] && mode=resume
  [ "$arg" = --sandbox ] && has_sandbox=1
  if [ "$arg" = -o ]; then j=$((i+1)); out="${!j}"; fi
done
if [ "$mode" = resume ] && [ "$has_sandbox" = 1 ]; then echo "resume received unsupported --sandbox" >&2; exit 64; fi
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
  # Pin every behavior knob: the harness must not inherit the operator's
  # ambient GINSU_* config (a real bypass-user's env broke these tests once).
  GINSU_SANDBOX=write
  GINSU_EFFORT=high
  GINSU_MODEL=
  GINSU_ENGINE=codex
  GINSU_CLAUDE_PERMISSION_MODE=acceptEdits
)

g() { env "${COMMON[@]}" "$GINSU" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }
assert_has() { grep -F -- "$2" "$1" >/dev/null || fail "$1 does not contain $2"; }

bash -n "$GINSU"
assert_eq "$(g --version)" "ginsu 2.1.0"

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

# --- async send + idempotent wait ---
q="$(g send "$CW" async1 --no-wait)"
ticket="$(printf '%s' "$q" | sed -n 's/.*ticket \([0-9]*\).*/\1/p' | head -1)"
[ -n "$ticket" ] || fail "--no-wait did not print a ticket: $q"
assert_eq "$(g wait "$CW" "$ticket")" "codex:resume:async1"
assert_eq "$(g wait "$CW" "$ticket")" "codex:resume:async1"   # idempotent re-read
g send "$CW" async2 --no-wait >/dev/null
assert_eq "$(g wait "$CW")" "codex:resume:async2"             # defaults to newest ticket
q="$(g send "$CW" fail --no-wait)"
ticket="$(printf '%s' "$q" | sed -n 's/.*ticket \([0-9]*\).*/\1/p' | head -1)"
if g wait "$CW" "$ticket" > "$TMP/wait-fail.out" 2>&1; then fail "wait on a failed turn returned success"; fi
assert_has "$TMP/wait-fail.out" "codex turn failed (exit 23)"
if g wait "$CW" 99999 > "$TMP/wait-bad.out" 2>&1; then fail "wait accepted a future ticket"; fi
assert_has "$TMP/wait-bad.out" "no such ticket"

# --- status: defaults + queue visibility ---
g status "$CW" > "$TMP/status.out"
assert_has "$TMP/status.out" "RUNNING"
assert_has "$TMP/status.out" "effort=high"
assert_has "$TMP/status.out" "working=idle"
assert_has "$TMP/status.out" "queued=none"

# --- spawn --effort/--model persist as worker defaults ---
mkdir -p "$TMP/repo2"; git -C "$TMP/repo2" init -q
FW="flags_$$"
g spawn "$FW" "$TMP/repo2" --engine codex --effort xhigh --model fake-xl >/dev/null
assert_eq "$(cat "$TMP/home/$FW/effort")" "xhigh"
assert_eq "$(cat "$TMP/home/$FW/model")" "fake-xl"
assert_eq "$(g send "$FW" flagcheck)" "codex:first:flagcheck"
assert_has "$TMP/bin/codex.args" 'model_reasoning_effort="xhigh"'
assert_has "$TMP/bin/codex.args" "-m fake-xl"
g status "$FW" > "$TMP/status2.out"
assert_has "$TMP/status2.out" "model=fake-xl"
assert_has "$TMP/status2.out" "effort=xhigh"
g stop "$FW" >/dev/null
tmux kill-session -t "ginsu-$FW" 2>/dev/null || true

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
