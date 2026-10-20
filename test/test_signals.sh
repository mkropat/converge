# Signals, operator stops, and the background client (CV-FAIL-1,
# CV-FAIL-9, CV-BG). These tests start converge as a background job of the
# test, so they wait on files the loop and the fake harness write, not on
# fixed sleeps.

LOOP_ARGS=(--no-coach --no-review)

# start_converge [args...]   Starts converge in the background. Sets PID
# and OUT, the file that holds its output. Each call gets its own file.
STARTS=0
start_converge() {
  OUT="$TEST_TMP/out.$((++STARTS))"
  "$CONVERGE" "$@" >"$OUT" 2>&1 </dev/null &
  PID=$!
}

# finish_converge   Waits for the converge of PID and OUT, with a guard.
# Sets STATUS and OUTPUT.
finish_converge() {
  local i
  for ((i = 0; i < 300; i++)); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$PID" 2>/dev/null && { kill -KILL "$PID"; fail "converge did not stop"; }
  wait "$PID"
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' "$OUT")
  printf '$ converge (background job)\n%s\n[exit %s]\n' "$OUTPUT" "$STATUS"
}

agent_started() { [[ -s $FAKE_HARNESS_DIR/calls/$1.pid ]]; }

test_sigterm_to_the_loop_stops_it_with_143() {
  scenario worker SLEEP=60
  start_converge --foreground "${LOOP_ARGS[@]}" docs/requirements.md
  wait_for 10 agent_started 1 || fail "the worker did not start"
  local loop agent
  loop=$(loop_pid) agent=$(agent_pid 1)
  kill -TERM "$loop"
  finish_converge
  assert_status 143
  assert_output_contains "stopped by SIGTERM"
  wait_for 5 is_dead "$agent" || fail "the agent survived SIGTERM"
  assert_eq "$(cat "$(state_dir)"/sessions/*.status)" 143 "recorded session status"
}

# The process that an operator or a supervisor starts is the converge
# wrapper itself, so SIGTERM reaches that process first.
#
test_sigterm_to_the_foreground_process_stops_the_agent() {
  scenario worker SLEEP=60
  start_converge --foreground "${LOOP_ARGS[@]}" docs/requirements.md
  wait_for 10 agent_started 1 || fail "the worker did not start"
  local agent
  agent=$(agent_pid 1)
  kill -TERM "$PID"
  finish_converge
  assert_status 143
  agent_stopped() { wait_for 5 is_dead "$agent"; }
  agent_stopped || fail "SIGTERM did not stop the foreground worker"
}

# The first stop request lets the running invocation finish, then stops
# with 130 (CV-FAIL-1). A background job ignores SIGINT, so the test sends
# USR1, the signal the client relays for a first Ctrl-C.
test_graceful_stop_lets_the_invocation_finish() {
  scenario worker SLEEP=2
  scenario worker MESSAGE=never
  start_converge --foreground "${LOOP_ARGS[@]}" docs/requirements.md
  wait_for 10 agent_started 1 || fail "the worker did not start"
  kill -USR1 "$(loop_pid)"
  finish_converge
  assert_status 130
  assert_calls 1
  assert_output_contains "stop requested; finishing the current invocation"
  assert_output_contains "worker finished"
  assert_output_contains "stopped on the request of the operator after 1 iteration"
  assert_output_contains "cost summary"
}

# A second stop request stops at once and kills the invocation.
test_second_stop_request_stops_at_once() {
  scenario worker SLEEP=60
  start_converge --foreground "${LOOP_ARGS[@]}" docs/requirements.md
  wait_for 10 agent_started 1 || fail "the worker did not start"
  local loop agent
  loop=$(loop_pid) agent=$(agent_pid 1)
  kill -USR1 "$loop"
  wait_for 5 grep -q "stop requested" "$OUT" || fail "the loop did not see the first request"
  kill -USR1 "$loop"
  finish_converge
  assert_status 130
  assert_output_contains "stopped after a repeated stop request"
  wait_for 5 is_dead "$agent" || fail "the agent survived the second stop request"
}

# Without --foreground, the client starts a background loop, shows its
# output, and exits with the loop's status (CV-BG-9).
test_background_loop_reports_its_status() {
  scenario worker MESSAGE=CONVERGED
  start_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  finish_converge
  assert_status 0
  assert_output_contains "converged after 1 iteration"
  # The loop has ended and released its lock.
  run_converge --foreground "${LOOP_ARGS[@]}" --consensus 0 docs/requirements.md
  assert_status 0
}

# A second client attaches to the running loop, warns that it ignores its
# own options, and reports the loop's result (CV-BG-2, CV-BG-6).
test_second_client_attaches() {
  scenario worker SLEEP=2
  scenario worker MESSAGE=CONVERGED
  start_converge "${LOOP_ARGS[@]}" --no-refactor --consensus 1 docs/requirements.md
  local first=$PID first_out=$OUT
  wait_for 10 agent_started 1 || fail "the worker did not start"
  start_converge --consensus 7
  finish_converge
  assert_status 0
  assert_output_contains "a loop already runs here; converge keeps the options of that loop"
  assert_output_contains "attached to the loop from"
  assert_output_contains "converged after 2 iterations"
  assert_calls 2
  PID=$first OUT=$first_out
  finish_converge
  assert_status 0
}

# SIGTERM to the client stops the loop and its agent, and the client
# reports the loop's 143.
test_sigterm_to_the_client_stops_the_background_loop() {
  scenario worker SLEEP=60
  start_converge "${LOOP_ARGS[@]}" docs/requirements.md
  wait_for 10 agent_started 1 || fail "the worker did not start"
  local agent
  agent=$(agent_pid 1)
  kill -TERM "$PID"
  finish_converge
  assert_status 143
  wait_for 5 is_dead "$agent" || fail "the agent survived SIGTERM to the client"
}
