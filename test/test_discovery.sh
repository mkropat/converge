# Requirements discovery for a session with no scope argument (CV-DISC).

LOOP_ARGS=(--foreground --no-coach --no-review --no-refactor)

# write_lookup <text>   Scenario text for a discovery agent that writes the
# lookup file whose path its prompt names.
write_lookup() {
  printf '%s\n' 'f=$(sed -n "s/.*identify usable sources: //p" <<<"$PROMPT")' \
    "printf '%s\\n' $(printf '%q' "$1") >\"\$f\""
}

roles() {
  calls | sed -E 's/.* role=([^ ]*) iteration=([^ ]*) model=([^ ]*) .*/\1@\2:\3/' | paste -sd' '
}

test_accepted_lookup_reaches_the_worker() {
  scenario_script discovery "MESSAGE=found; $(write_lookup 'Read docs/requirements.md in full.')"
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1
  assert_status 0
  assert_eq "$(roles)" "discovery@unset:sonnet worker@1:sonnet" "call order"
  assert_output_contains "accepted requirements lookup instructions"
  call_prompt 2 | grep -qF "Read docs/requirements.md in full." ||
    fail "the worker prompt lacks the lookup instructions"
  local result
  result=$(ls "$(state_dir)"/sessions/*.discovery.result)
  assert_file_contains "$result" "status=accepted"
}

test_missing_lookup_fails_with_status_2() {
  export CONVERGE_NOTIFY='cat >"$FAKE_HARNESS_DIR/notified"'
  scenario discovery MESSAGE="I found no requirements."
  run_converge "${LOOP_ARGS[@]}" --consensus 1
  assert_status 2
  assert_calls 1
  assert_output_contains "requirements discovery failed; no normal agent will start"
  assert_file_contains "$FAKE_HARNESS_DIR/notified" "stopped because requirements discovery failed"
}

test_blank_lookup_is_rejected() {
  scenario_script discovery "MESSAGE=found; $(write_lookup '   ')"
  run_converge "${LOOP_ARGS[@]}" --consensus 1
  assert_status 2
  assert_calls 1
}

# Discovery falls back over the worker list, and does not advance the
# worker rotation (CV-DISC-13).
test_discovery_falls_back_without_advancing_workers() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario discovery EXIT=1
  scenario_script discovery "MESSAGE=found; $(write_lookup 'Read docs/requirements.md.')"
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1
  assert_status 0
  assert_eq "$(roles)" "discovery@unset:a discovery@unset:b worker@1:a" "call order"
}

# A failed attempt cannot leave a lookup file for a later attempt.
test_lookup_from_a_failed_attempt_is_discarded() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario_script discovery "EXIT=1; $(write_lookup 'Read docs/requirements.md.')"
  scenario discovery MESSAGE="nothing found"
  run_converge "${LOOP_ARGS[@]}" --consensus 1
  assert_status 2
  assert_calls 2
}

test_discovery_timeout_ends_the_chain() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario discovery SLEEP=30
  run_converge "${LOOP_ARGS[@]}" --timeout 1 --consensus 1
  assert_status 2
  assert_calls 1
  assert_output_contains "discovery exceeded the 1s timeout"
}

test_explicit_scope_skips_discovery() {
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs
  assert_status 0
  assert_output_contains "requirements skipped (explicit scope)"
  assert_calls 0 "role=discovery"
}

test_no_discovery_when_no_agent_can_start() {
  run_converge "${LOOP_ARGS[@]}" --max-iterations 0
  assert_status 1
  assert_output_contains "requirements skipped (no agent can start)"
  assert_calls 0
}
