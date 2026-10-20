# lib.sh: setup and assertion helpers for the converge tests. test/run
# sources this file, then one test file, in a fresh bash process for each
# test function, so no state leaks from one test to the next.

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$TEST_ROOT/.." && pwd)
CONVERGE="$REPO_ROOT/bin/converge"
CBUGS="$REPO_ROOT/bin/cbugs"

# Exit statuses that test/run reads. A plain failure is any other nonzero.
SKIP_STATUS=77
XFAIL_STATUS=78

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# skip <reason>   Ends the test as skipped.
skip() {
  printf 'SKIP: %s\n' "$*" >&2
  exit "$SKIP_STATUS"
}

# known_failure <reason> <command...>   Runs a check that exposes a known
# bug. The test reports "known failure" while the check fails, and fails
# when the check starts to pass, so a fix cannot go unnoticed.
known_failure() {
  local reason=$1; shift
  if ("$@"); then
    fail "known failure now passes; remove the marker: $reason"
  fi
  printf 'XFAIL: %s\n' "$reason" >&2
  exit "$XFAIL_STATUS"
}

# setup_test   Makes a private world for one test: HOME, XDG_STATE_HOME,
# TMPDIR, a throwaway git repository with a requirements document, and the
# fake harness first on PATH. Nothing touches the real user state.
setup_test() {
  TEST_TMP=$(mktemp -d "${TEST_TMPDIR_ROOT:-${TMPDIR:-/tmp}}/converge-test.XXXXXX")
  # The caller's environment must not choose profiles, notifications, or
  # sessions for the loop under test.
  unset "${!CONVERGE_@}" "${!REVIEW_PANEL_@}"
  export HOME="$TEST_TMP/home"
  export XDG_STATE_HOME="$TEST_TMP/state"
  export TMPDIR="$TEST_TMP/tmp"
  export FAKE_HARNESS_DIR="$TEST_TMP/harness"
  export CONVERGE_COLS=80
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  export GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$TMPDIR" "$FAKE_HARNESS_DIR/queue" \
    "$TEST_TMP/bin"
  local h
  for h in claude opencode codex; do
    ln -s "$TEST_ROOT/fake-harness" "$TEST_TMP/bin/$h"
  done
  export PATH="$TEST_TMP/bin:$PATH"

  WORK="$TEST_TMP/repo"
  mkdir -p "$WORK/docs"
  printf '# Requirements\n\n- **T-1**: The project must exist.\n' >"$WORK/docs/requirements.md"
  git -C "$WORK" init -q -b main
  git -C "$WORK" add docs/requirements.md
  git -C "$WORK" commit -q -m "Add requirements"
  cd "$WORK" || fail "cannot enter $WORK"
  SCENARIO_SEQ=0
}

teardown_test() {
  cd / || true
  # A failed test can leave a loop behind. Its processes hold files in
  # TEST_TMP, so stop them before the directory goes away.
  pkill -TERM -f "$TEST_TMP" 2>/dev/null || true
  [[ -n ${KEEP_TEST_TMP:-} ]] || rm -rf "$TEST_TMP"
}

# scenario <role|any> [VAR=value]...   Queues one fake-harness invocation.
# See test/fake-harness for the variables.
scenario() {
  local role=$1 kv file; shift
  mkdir -p "$FAKE_HARNESS_DIR/queue/$role"
  printf -v file '%s/queue/%s/%04d' "$FAKE_HARNESS_DIR" "$role" $((++SCENARIO_SEQ))
  : >"$file.tmp"
  for kv in "$@"; do
    printf '%s=%q\n' "${kv%%=*}" "${kv#*=}" >>"$file.tmp"
  done
  # The stub claims files by name, so the file appears whole or not at all.
  mv "$file.tmp" "$file"
}

# scenario_script <role> <bash text>   Queues a scenario with free-form bash,
# for an agent that must write a file, such as discovery or the coach.
scenario_script() {
  local role=$1 file
  mkdir -p "$FAKE_HARNESS_DIR/queue/$role"
  printf -v file '%s/queue/%s/%04d' "$FAKE_HARNESS_DIR" "$role" $((++SCENARIO_SEQ))
  printf '%s\n' "$2" >"$file.tmp"
  mv "$file.tmp" "$file"
}

# run_converge [args...]   Runs converge in the foreground in $WORK. Sets
# STATUS and OUTPUT (stdout and stderr together, color codes removed). A
# guard timeout keeps a broken loop from hanging the suite.
run_converge() {
  local raw
  raw=$(timeout "${CONVERGE_TEST_TIMEOUT:-60}" "$CONVERGE" "$@" 2>&1 </dev/null)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$raw")
  printf '%s\n' "$OUTPUT" >"$TEST_TMP/last-output.txt"
}

# state_dir   Prints the state directory of $WORK.
state_dir() {
  "$CONVERGE" --state-dir
}

# calls   Prints the fake-harness call log, one line per invocation.
calls() {
  cat "$FAKE_HARNESS_DIR/calls.log" 2>/dev/null
}

# call_count [pattern]   Counts the calls whose log line matches a pattern.
call_count() {
  local pattern=${1:-.}
  calls | grep -cE -- "$pattern" || true
}

# call_field <n> <field>   Prints one field of call n, such as model.
call_field() {
  calls | awk -v n="$1" -v f="$2" '$1 == n {
    for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == f) print substr($i, length(f) + 2) }
  }'
}

# call_prompt <n>   Prints the prompt that call n received.
call_prompt() {
  cat "$FAKE_HARNESS_DIR/calls/$1.prompt"
}

assert_status() {
  [[ $STATUS == "$1" ]] ||
    fail "expected exit status $1, got $STATUS; output:"$'\n'"$OUTPUT"
}

assert_eq() {
  [[ $1 == "$2" ]] || fail "${3:-values differ}: expected '$2', got '$1'"
}

assert_output_contains() {
  [[ $OUTPUT == *"$1"* ]] ||
    fail "output lacks '$1'; output:"$'\n'"$OUTPUT"
}

assert_output_lacks() {
  [[ $OUTPUT != *"$1"* ]] ||
    fail "output holds '$1'; output:"$'\n'"$OUTPUT"
}

assert_file_contains() {
  grep -qF -- "$2" "$1" 2>/dev/null ||
    fail "file $1 lacks '$2'; content:"$'\n'"$(cat "$1" 2>/dev/null)"
}

# assert_calls <expected> [pattern]   Checks the number of harness calls.
assert_calls() {
  local got
  got=$(call_count "${2:-.}")
  [[ $got == "$1" ]] ||
    fail "expected $1 harness calls matching '${2:-.}', got $got; calls:"$'\n'"$(calls)"$'\n'"output:"$'\n'"$OUTPUT"
}
