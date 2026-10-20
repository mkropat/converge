# Done votes, blocked votes, and the iteration limit (CV-CONV-26 through
# CV-CONV-29). The coach and the reviewer are off, so only workers run.

# These tests cover worker vote counts. Refactor has its own behavior tests.
LOOP_ARGS=(--foreground --no-coach --no-review --no-refactor)

test_consensus_of_consecutive_votes_converges() {
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=$'All requirements hold.\n  CONVERGED  '
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 3 docs/requirements.md
  assert_status 0
  assert_calls 3
  assert_output_contains "converged vote 3 of 3"
  assert_output_contains "converged after 3 iterations"
}

test_non_vote_resets_the_done_count() {
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE="I fixed a bug."
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 2 docs/requirements.md
  assert_status 0
  assert_calls 4
  assert_output_contains "no worker vote; work remains"
}

# Only the token alone on a line votes (CV-CONV-3).
test_token_inside_a_sentence_is_no_vote() {
  scenario worker MESSAGE="I think the work is CONVERGED now."
  scenario worker MESSAGE="CONVERGED."
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_calls 2
  assert_output_lacks "converged vote 1 of 1"
}

# A message with both tokens gives no vote of either kind (CV-CONV-28).
test_both_tokens_give_no_vote() {
  scenario worker MESSAGE=$'CONVERGED\nBLOCKED'
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --blocked 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "worker final message contains both vote tokens; no vote"
}

# A failed worker cannot vote, even when its message holds the token
# (CV-HARN-22), and it resets the done count (CV-CONV-26).
test_failed_worker_cannot_vote_and_resets_the_count() {
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=CONVERGED EXIT=1
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 2 docs/requirements.md
  assert_status 0
  assert_calls 4
  assert_output_contains "worker exited with status 1"
}

test_blocked_votes_stop_with_status_3() {
  scenario worker MESSAGE=$'Spec bug #4 stops the export.\nBLOCKED'
  scenario worker MESSAGE=$'Spec bug #5 stops the import.\nBLOCKED'
  run_converge "${LOOP_ARGS[@]}" --blocked 2 docs/requirements.md
  assert_status 3
  assert_calls 2
  assert_output_contains "blocked vote 2 of 2"
  assert_output_contains "stopped blocked after 2 consecutive blocked votes"
  assert_output_contains "Last blocked worker message:"
  assert_output_contains "Spec bug #5 stops the import."
  # The closing report names the last message, not an earlier one.
  [[ ${OUTPUT#*Last blocked worker message:} != *"Spec bug #4"* ]] ||
    fail "the closing report shows an earlier blocked message"
}

test_blocked_count_resets_on_non_vote_and_done_vote() {
  scenario worker MESSAGE=BLOCKED
  scenario worker MESSAGE="did some work"
  scenario worker MESSAGE=BLOCKED
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=BLOCKED
  scenario worker MESSAGE=BLOCKED
  run_converge "${LOOP_ARGS[@]}" --blocked 2 --consensus 2 docs/requirements.md
  assert_status 3
  assert_calls 6
}

# A blocked vote resets the done count (CV-CONV-29).
test_blocked_vote_resets_the_done_count() {
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=BLOCKED
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --blocked 2 --consensus 2 docs/requirements.md
  assert_status 0
  assert_calls 4
}

test_iteration_limit_stops_with_status_1() {
  scenario worker MESSAGE="work remains"
  scenario worker MESSAGE="work remains"
  run_converge "${LOOP_ARGS[@]}" --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_calls 2
  assert_output_contains "reached the limit of 2 iterations without convergence"
  assert_output_contains "stopped after 2 iterations"
}

# A vote on the last permitted iteration still converges: the convergence
# check comes before the limit check.
test_vote_on_the_last_iteration_converges() {
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 1 docs/requirements.md
  assert_status 0
}

# Workers see the role, the iteration, and the run directory (CV-ENV).
test_worker_environment_and_prompt() {
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_field 1 role)" worker "role"
  assert_eq "$(call_field 1 iteration)" 1 "iteration"
  call_prompt 1 | grep -qF "work on them only: docs/requirements.md" ||
    fail "the worker prompt does not name the scope"
  call_prompt 1 | grep -qF "The operator resolves a spec bug." ||
    fail "the worker prompt does not name the operator as the spec bug resolver"
  call_prompt 1 | grep -qF "Do not vote CONVERGED while an open code bug" ||
    fail "the worker prompt forbids the blocked vote with an open bug"
}

test_session_files_record_the_run() {
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  local dir session
  dir=$(state_dir)
  session=$(cat "$dir/current")
  [[ -n $session ]] || fail "no current session"
  assert_eq "$(cat "$dir/sessions/$session.status")" 0 "recorded session status"
  assert_file_contains "$dir/sessions/$session.out" "converged after 1 iteration"
  assert_file_contains "$dir/converge.log" "=== run end: exit 0 ==="
  [[ -s $(ls "$dir"/logs/"$session"-0001-worker.jsonl) ]] || fail "no worker log"
  assert_file_contains "$dir/logs/$session-0001-worker.prompt.md" "CONVERGED"
}

# A second session reports how the previous one ended.
test_second_session_reports_the_last_run() {
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  run_converge "${LOOP_ARGS[@]}" --consensus 0 docs/requirements.md
  assert_status 0
  assert_output_contains "the last run converged"
}

test_notification_on_convergence() {
  export CONVERGE_NOTIFY='{ printf "%s|%s|%s\n" "$1" "$CONVERGE_EVENT" "$CONVERGE_EXIT"; cat; } >"$FAKE_HARNESS_DIR/notified"'
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_output_contains "notification converged: sent (exit 0)"
  assert_file_contains "$FAKE_HARNESS_DIR/notified" "converged|converged|0"
  assert_file_contains "$FAKE_HARNESS_DIR/notified" "converge repo: converged after 1 iteration"
}

test_notification_on_blocked_stop_holds_the_message() {
  export CONVERGE_NOTIFY='cat >"$FAKE_HARNESS_DIR/notified"'
  scenario worker MESSAGE=$'Tool X is down.\nBLOCKED'
  run_converge "${LOOP_ARGS[@]}" --blocked 1 docs/requirements.md
  assert_status 3
  assert_file_contains "$FAKE_HARNESS_DIR/notified" "Tool X is down."
}

# A failed notification command is reported and changes nothing.
test_failed_notification_keeps_the_result() {
  export CONVERGE_NOTIFY='echo boom >&2; exit 4'
  scenario worker MESSAGE="work remains"
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "notification limit failed (exit 4)"
  assert_output_contains "boom"
}
