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
OW="opencode_$$"
OR="opencode_read_$$"
OB="opencode_bypass_$$"
RW="release_$$"
DW="defaults_$$"
EW="defaults_env_$$"
FW2="defaults_flags_$$"
NW="defaults_none_$$"

cleanup() {
  if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "kept test state: $BASE" >&2
    return
  fi
  tmux kill-session -t "ginsu-$CW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$HW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$HR" 2>/dev/null || true
  tmux kill-session -t "ginsu-$HB" 2>/dev/null || true
  tmux kill-session -t "ginsu-$OW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$OR" 2>/dev/null || true
  tmux kill-session -t "ginsu-$OB" 2>/dev/null || true
  tmux kill-session -t "ginsu-$RW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$DW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$EW" 2>/dev/null || true
  tmux kill-session -t "ginsu-$FW2" 2>/dev/null || true
  tmux kill-session -t "ginsu-$NW" 2>/dev/null || true
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
# A turn that forks a grandchild and keeps going — the shape of a worker that outlives its wrapper.
# The grandchild ignores HUP: closing the pane/window must not be what kills it, only stop's tree-kill.
if [ "$prompt" = hang ]; then ( trap '' HUP; exec sleep 3617 ) & sleep 30; exit 0; fi
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
cat > "$TMP/bin/opencode" <<'FAKE_OPENCODE'
#!/usr/bin/env bash
set -u
mode=first; sid=""; prompt="${!#}"
printf '%s\n' "$*" >> "$(dirname "$0")/opencode.args"
printf '%s\n' "${OPENCODE_PERMISSION:-}" >> "$(dirname "$0")/opencode.permissions"
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [ "$arg" = --session ]; then mode=resume; j=$((i+1)); sid="${!j}"; fi
done
if [ "$prompt" = fail ]; then echo "fake opencode failure" >&2; exit 25; fi
[ "$prompt" = slow ] && sleep 0.3
[ -n "$sid" ] || sid=opencode-session
python3 - "$mode" "$sid" "$prompt" <<'PY'
import json, sys
mode, sid, prompt = sys.argv[1:]
reply = f"opencode:{mode}:{prompt}"
print(json.dumps({"type":"step_start","sessionID":sid,"part":{"type":"step-start"}}))
if prompt == "softfail":
    print(json.dumps({"type":"error","sessionID":sid,"error":{"message":"fake opencode stream error"}}))
else:
    print(json.dumps({"type":"text","sessionID":sid,"part":{"type":"text","text":reply}}))
print(json.dumps({"type":"step_finish","sessionID":sid,"part":{"type":"step-finish","tokens":{"input":7,"output":3}}}))
PY
FAKE_OPENCODE
chmod +x "$TMP/bin/codex" "$TMP/bin/claude" "$TMP/bin/opencode"

COMMON=(
  GINSU_HOME="$TMP/home"
  GINSU_TERM=tmux
  GINSU_CODEX="$TMP/bin/codex"
  GINSU_CLAUDE="$TMP/bin/claude"
  GINSU_OPENCODE="$TMP/bin/opencode"
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
assert_eq "$(g --version)" "ginsu 2.1.1"

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

# stop must take the whole tree and verify it: a grandchild that survived a "stopped" worker
# once finished its turn and committed to the repo after the operator was told it was dead.
g send "$CW" hang --no-wait >/dev/null
for _ in $(seq 1 50); do pgrep -f 'sleep 3617' >/dev/null && break; sleep 0.1; done
pgrep -f 'sleep 3617' >/dev/null || fail "hang fixture never forked its grandchild"
assert_eq "$(g stop "$CW")" "stopped $CW"
if pgrep -f 'sleep 3617' >/dev/null; then pkill -f 'sleep 3617'; fail "stop reported success but the worker's grandchild survived"; fi

# A worker stopped mid-turn once left its ticket marker behind, and release refused forever with
# "working on ticket N" even though nothing was running. stop clears the marker; release treats a
# marker on a dead worker as stale, still protects queued tickets, and --force discards them.
git -C "$TMP/repo" commit -q --allow-empty -m base
git -C "$TMP/repo" worktree add -q "$TMP/wt-release" -b release-case
g spawn "$RW" "$TMP/wt-release" --engine codex >/dev/null
g send "$RW" hang --no-wait >/dev/null
for _ in $(seq 1 50); do pgrep -f 'sleep 3617' >/dev/null && break; sleep 0.1; done
g send "$RW" queued-after --no-wait >/dev/null
assert_eq "$(g stop "$RW")" "stopped $RW"
if [ -f "$TMP/home/$RW/current" ]; then fail "stop left the current ticket marker behind"; fi
echo 9 > "$TMP/home/$RW/current"
if g release "$RW" > "$TMP/release.out" 2>&1; then fail "release discarded a queued ticket without --force"; fi
assert_has "$TMP/release.out" "marker is stale"
assert_has "$TMP/release.out" "queued ticket"
assert_eq "$(g release "$RW" --force 2>/dev/null)" "released $RW: removed worktree $TMP/wt-release (branch left in place)"
if [ -d "$TMP/wt-release" ]; then fail "release --force left the worktree in place"; fi

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

g spawn "$OW" "$TMP/repo" --engine opencode --model openrouter/stealth/space-bunny-alpha >/dev/null
assert_eq "$(g send "$OW" first)" "opencode:first:first"
assert_eq "$(g send "$OW" second)" "opencode:resume:second"
assert_has "$TMP/bin/opencode.args" "run --format json --dir $TMP/repo --model openrouter/stealth/space-bunny-alpha"
assert_has "$TMP/bin/opencode.args" "--session opencode-session"
assert_has "$TMP/bin/opencode.args" "--agent build"
assert_eq "$(cat "$TMP/home/$OW/effort")" default
if g send "$OW" fail > "$TMP/fail.out" 2>&1; then fail "failed OpenCode turn returned success"; fi
assert_has "$TMP/fail.out" "opencode turn failed (exit 25)"
if g send "$OW" softfail > "$TMP/fail.out" 2>&1; then fail "OpenCode stream error returned success"; fi
assert_has "$TMP/fail.out" "fake opencode stream error"
assert_eq "$(g send "$OW" recovered --effort high)" "opencode:resume:recovered"
assert_has "$TMP/bin/opencode.args" "--variant high"
g restart "$OW" >/dev/null
assert_eq "$(cat "$TMP/home/$OW/engine")" opencode
assert_eq "$(g send "$OW" restarted)" "opencode:first:restarted"
g stop "$OW" >/dev/null

env "${COMMON[@]}" GINSU_SANDBOX=read "$GINSU" spawn "$OR" "$TMP/repo" --engine opencode >/dev/null
assert_eq "$(g send "$OR" readmode)" "opencode:first:readmode"
assert_has "$TMP/bin/opencode.args" "--agent plan"
assert_has "$TMP/bin/opencode.permissions" '"edit":"deny"'
g stop "$OR" >/dev/null

env "${COMMON[@]}" GINSU_SANDBOX=bypass "$GINSU" spawn "$OB" "$TMP/repo" --engine opencode >/dev/null
assert_eq "$(g send "$OB" bypassmode)" "opencode:first:bypassmode"
assert_has "$TMP/bin/opencode.args" "--agent build --auto"
g stop "$OB" >/dev/null

# A personal defaults file applies to CLI launches without changing the
# built-in defaults or overriding explicit environment/flag selections.
mkdir -p "$TMP/config/ginsu"
cat > "$TMP/config/ginsu/defaults" <<EOF
GINSU_ENGINE=claude
GINSU_CLAUDE_MODEL=personal-model
GINSU_CLAUDE=$TMP/bin/claude
GINSU_EFFORT=low
EOF
CONFIG_ENV=(
  PATH="$PATH"
  HOME="$HOME"
  XDG_CONFIG_HOME="$TMP/config"
  GINSU_HOME="$TMP/home"
  GINSU_TERM=tmux
  GINSU_SANDBOX=read
  GINSU_TIMEOUT=20
  GINSU_CODEX="$TMP/bin/codex"
  GINSU_OPENCODE="$TMP/bin/opencode"
)
env -i "${CONFIG_ENV[@]}" "$GINSU" spawn "$DW" "$TMP/repo" >/dev/null
assert_eq "$(cat "$TMP/home/$DW/engine")" claude
assert_eq "$(cat "$TMP/home/$DW/model")" personal-model
assert_eq "$(cat "$TMP/home/$DW/cli")" "$TMP/bin/claude"
assert_eq "$(cat "$TMP/home/$DW/effort")" low
assert_eq "$(g send "$DW" configured)" "claude:first:configured"
g stop "$DW" >/dev/null

env -i "${CONFIG_ENV[@]}" GINSU_ENGINE=opencode GINSU_OPENCODE_MODEL=env-model "$GINSU" spawn "$EW" "$TMP/repo" >/dev/null
assert_eq "$(cat "$TMP/home/$EW/engine")" opencode
assert_eq "$(cat "$TMP/home/$EW/model")" env-model
g stop "$EW" >/dev/null

env -i "${CONFIG_ENV[@]}" "$GINSU" spawn "$FW2" "$TMP/repo" --engine codex --model flag-model --effort xhigh >/dev/null
assert_eq "$(cat "$TMP/home/$FW2/engine")" codex
assert_eq "$(cat "$TMP/home/$FW2/model")" flag-model
assert_eq "$(cat "$TMP/home/$FW2/effort")" xhigh
g stop "$FW2" >/dev/null

env -i "${CONFIG_ENV[@]}" XDG_CONFIG_HOME="$TMP/no-config" "$GINSU" spawn "$NW" "$TMP/repo" >/dev/null
assert_eq "$(cat "$TMP/home/$NW/engine")" codex
g stop "$NW" >/dev/null

printf 'GINSU_ENGINE=$(touch "%s/pwned")\n' "$TMP" > "$TMP/config/ginsu/defaults"
if env -i "${CONFIG_ENV[@]}" "$GINSU" spawn "$DW" "$TMP/repo" > "$TMP/unsafe.out" 2>&1; then
  fail "config command substitution was accepted"
fi
[ ! -e "$TMP/pwned" ] || fail "config file executed shell code"

echo "PASS: three engines, personal defaults, resume, queue tickets, failures, restart, verified stop, stale-marker release, security mappings, and nesting guard"
