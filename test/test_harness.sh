# Profile rotation and fallback chains (CV-HARN-23, CV-HARN-24), timeouts
# (CV-FAIL-18), the wait after a chain without output (CV-FAIL-16), and the
# argv and output of each supported harness (CV-HARN-21).

LOOP_ARGS=(--foreground --no-coach --no-review)

test_inherited_session_does_not_reuse_foreground_ids() {
  export CONVERGE_SESSION=fixed-session
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  local ids
  ids=$(find "$(state_dir)/sessions" -name '*.status' -printf '%f\n' | sed 's/\.status$//' | sort -u)
  assert_eq "$(wc -l <<<"$ids" | tr -d ' ')" 2 "session ids"
}

# models   Prints the model of every call, in order, on one line.
models() {
  calls | sed -E 's/.* model=([^ ]*) .*/\1/' | paste -sd' '
}

# iterations   Prints the iteration of every call, in order, on one line.
iterations() {
  calls | sed -E 's/.* iteration=([^ ]*) .*/\1/' | paste -sd' '
}

test_round_robin_across_iterations() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario worker MESSAGE=work
  scenario worker MESSAGE=work
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_eq "$(models)" "a b a" "worker models"
}

# A nonzero exit starts the next profile at once, in the same iteration,
# and the next iteration starts after the last profile tried.
test_failure_falls_back_within_the_iteration() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b,claude:c'
  scenario worker MESSAGE=quota EXIT=1
  scenario worker MESSAGE=work
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_eq "$(models)" "a b c" "worker models"
  assert_eq "$(iterations)" "1 1 2" "worker iterations"
  # There is no wait between the attempts of one chain.
  assert_output_lacks "before continuing"
}

# A chain ends after every profile has started once.
test_chain_stops_after_every_profile_failed() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario worker EXIT=1
  scenario worker EXIT=2
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_eq "$(models)" "a b" "worker models"
  assert_output_contains "worker exited with status 2"
  assert_output_contains "iteration 1 failed"
}

# The vote of a chain comes from its successful attempt; an earlier failed
# attempt in the same chain does not reset the done count (CV-CONV-26).
test_failed_attempt_before_success_keeps_the_count() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario worker MESSAGE=CONVERGED
  scenario worker MESSAGE=CONVERGED EXIT=1
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --no-refactor --consensus 2 docs/requirements.md
  assert_status 0
  assert_eq "$(models)" "a b a" "worker models"
  assert_eq "$(iterations)" "1 2 2" "worker iterations"
}

# A timeout kills the invocation and ends the chain with no fallback.
test_timeout_ends_the_chain_without_fallback() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario worker SLEEP=30
  local started=$SECONDS
  run_converge "${LOOP_ARGS[@]}" --timeout 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_calls 1
  assert_output_contains "worker exceeded the 1s timeout; killed it"
  ((SECONDS - started < 20)) || fail "the timeout did not stop the sleeping worker"
  grep -q '"event":"timeout"' "$(state_dir)"/logs/*-0001-worker.jsonl ||
    fail "the worker log records no timeout event"
}

# A harness that exits 124 by itself did not time out: that is an ordinary
# failure, and the chain falls back.
test_exit_124_without_timeout_is_a_failure() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario worker EXIT=124
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_eq "$(models)" "a b" "worker models"
  assert_output_contains "worker exited with status 124"
  assert_output_lacks "exceeded the"
}

# A timed-out worker cannot vote, even after it wrote CONVERGED.
test_timed_out_worker_cannot_vote() {
  scenario worker SLEEP=30 MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --timeout 1 --consensus 1 --max-iterations 1 docs/requirements.md
  assert_status 1
}

# A failed chain without output waits before the next iteration
# (CV-FAIL-16). A quota rejection's synthetic message is no output.
test_chain_without_output_waits() {
  scenario worker EXIT=1 ASSISTANT=synthetic
  scenario worker MESSAGE=CONVERGED
  CONVERGE_TEST_TIMEOUT=40 run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 2 docs/requirements.md
  assert_status 0
  assert_output_contains "waits 10s before continuing"
}

# Output from a failed attempt resets the wait, so no wait happens.
test_failed_chain_with_output_does_not_wait() {
  scenario worker EXIT=1
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 2 docs/requirements.md
  assert_status 0
  assert_output_lacks "before continuing"
}

# The last permitted iteration has nothing to wait for.
test_no_wait_after_the_last_iteration() {
  scenario worker EXIT=1 ASSISTANT=0
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_lacks "before continuing"
  assert_output_contains "iteration 1 failed"
}

# A harness that is not installed fails at its first invocation.
test_missing_harness_fails_at_invocation() {
  rm "$TEST_TMP/bin/codex"
  local stripped
  stripped=$(tr ':' '\n' <<<"$PATH" | while read -r d; do [[ -x $d/codex ]] || printf '%s:' "$d"; done)
  export PATH=${stripped%:}
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex,claude:sonnet'
  scenario worker MESSAGE=CONVERGED
  scenario refactor MESSAGE='no safe refactor'
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_output_contains "worker exited with status 127"
  assert_eq "$(models)" "sonnet sonnet" "worker and Refactor fallback models"
}

test_claude_effort_is_passed() {
  export CONVERGE_WORKER_PROFILE='claude:opus:high'
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_field 1 harness)" claude "harness"
  assert_eq "$(call_field 1 model)" opus "model"
  assert_eq "$(call_field 1 effort)" high "effort"
  assert_output_contains "worker · claude:opus:high"
}

test_opencode_vote_and_effort() {
  export CONVERGE_WORKER_PROFILE='opencode:provider/model:fast'
  scenario worker MESSAGE=$'Nothing remains.\nCONVERGED'
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_field 1 harness)" opencode "harness"
  assert_eq "$(call_field 1 model)" provider/model "model"
  assert_eq "$(call_field 1 effort)" fast "native effort"
}

test_opencode_tool_event_does_not_replace_last_assistant_message() {
  export CONVERGE_WORKER_PROFILE='opencode:provider/model'
  scenario worker MESSAGE=CONVERGED OPENCODE_TOOL=1
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_lacks "converged vote 1 of 1"
}

test_opencode_joins_text_parts_of_last_assistant_message() {
  export CONVERGE_WORKER_PROFILE='opencode:provider/model'
  scenario worker MESSAGE='No work.' OPENCODE_EXTRA_TEXT=$'\nCONVERGED' \
    OPENCODE_MESSAGE_ID=m3 OPENCODE_TOOL_MESSAGE_ID=m3 OPENCODE_TOOL=1
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_output_contains "converged vote 1 of 1"
}

test_codex_vote_and_effort() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex:high'
  scenario worker MESSAGE=CONVERGED
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_field 1 harness)" codex "harness"
  assert_eq "$(call_field 1 effort)" high "reasoning effort"
}

test_codex_final_agent_message_is_marked_final_after_tool_call() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex'
  scenario worker MESSAGE=$'FIRST commentary\nCONVERGED' FOLLOWUP_TOOL=1
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_output_contains '▍ CONVERGED'
  local before_tool=${OUTPUT%%'❯ true'*} after_tool=${OUTPUT#*'❯ true'}
  [[ $before_tool == *'FIRST commentary'* ]] || fail "commentary did not precede the tool call"
  [[ $after_tool == *'▍ FIRST commentary'* ]] || fail "final message was not repeated after the tool call"
}

test_codex_commentary_precedes_following_tool_call() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex'
  scenario worker MESSAGE=$'FIRST commentary\nCONVERGED' FOLLOWUP_TOOL=1
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  local before_tool=${OUTPUT%%'❯ true'*}
  [[ $before_tool == *'FIRST commentary'* ]] || fail "commentary did not precede the tool call"
}

test_opencode_tool_event_after_assistant_does_not_hide_final_message() {
  export CONVERGE_WORKER_PROFILE='opencode:model'
  scenario worker MESSAGE=CONVERGED OPENCODE_TOOL=1
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_lacks 'converged vote 1 of 1'
}

test_codex_file_change_operation_is_visible_as_a_write() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex'
  scenario worker MESSAGE=done FILE_KIND=update
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains 'update changed.txt'
}

test_codex_mcp_web_search_and_failed_file_change_are_visible() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex'
  scenario worker MESSAGE=done MCP_TOOL=1 MCP_STATUS=failed MCP_ERROR='MCP boom' \
    WEB_SEARCH=1 FILE_KIND=update FILE_STATUS=failed FILE_ERROR='file boom'
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains 'mcp files/read'
  assert_output_contains '"path":"a.txt"'
  assert_output_contains 'web_search latest result'
  assert_output_contains 'MCP boom'
  assert_output_contains 'update changed.txt'
  assert_output_contains 'file boom'
}

# A codex run without an agent message produced no output and gives no vote.
test_codex_without_output_gives_no_vote() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex'
  scenario worker MESSAGE=CONVERGED ASSISTANT=0
  run_converge "${LOOP_ARGS[@]}" --consensus 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "iteration 1 produced no output"
}

# A worker commit appears in the iteration report.
test_worker_commit_is_reported() {
  scenario worker MESSAGE=done COMMIT="Add the export"
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "1 commit, 1 file changed"
  assert_output_contains "Add the export"
}

test_uncommitted_changes_are_reported() {
  scenario_script worker 'MESSAGE=done; echo x >stray.txt'
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "1 path left uncommitted"
  assert_output_contains "stray.txt"
}
