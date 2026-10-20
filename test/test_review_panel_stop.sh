# A hard stop reports reviewers as stopped, not as timed out.

test_hard_stop_lists_reviewers_as_stopped() {
  local output_file="$TEST_TMP/panel.out" panel_pid status
  export CONVERGE_REVIEW_PANEL_PROFILE='claude:a,claude:b'
  scenario reviewer SLEEP=30
  scenario reviewer SLEEP=30
  CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" --timeout 30 docs/requirements.md >"$output_file" 2>&1 &
  panel_pid=$!
  local i
  for ((i = 0; i < 100; i++)); do
    [[ $(call_count 'role=reviewer') -ge 2 ]] && break
    sleep 0.1
  done
  [[ $(call_count 'role=reviewer') -ge 2 ]] || fail "both reviewers did not start"
  kill -TERM "$panel_pid" 2>/dev/null || true
  wait "$panel_pid"; status=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' "$output_file")
  assert_eq "$status" 143 "panel status"
  assert_output_contains "reviewer 1/2 claude:a stopped by the operator"
  assert_output_contains "reviewer 2/2 claude:b stopped by the operator"
  assert_output_lacks "exit status 124"
}

test_reviewer_timeout_remains_a_timeout() {
  local output
  export CONVERGE_REVIEW_PANEL_PROFILE='claude:a'
  scenario reviewer SLEEP=30
  output=$(CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" --timeout 1 docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_eq "$STATUS" 2 "panel status"
  assert_output_contains "reviewer 1/1 claude:a exceeded the 1s timeout"
  assert_output_contains "reviewer 1/1 claude:a: exit status 124"
}

test_panel_records_successful_profiles_in_one_coverage_write() {
  export CONVERGE_REVIEW_PANEL_PROFILE='claude:a,claude:b'
  scenario reviewer MESSAGE="nothing found"
  scenario reviewer MESSAGE="nothing found"
  local output rows
  output=$(CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_eq "$STATUS" 0 "panel status"
  rows=$(sqlite3 "$(state_dir)/cbugs.db" 'SELECT profile FROM reviewed ORDER BY id;')
  assert_eq "$rows" $'claude:a\nclaude:b' "coverage profiles"
}

test_hard_stop_lists_merge_as_stopped() {
  local output_file="$TEST_TMP/merge-panel.out" panel_pid status i
  export CONVERGE_REVIEW_PANEL_MERGE_PROFILE='claude:merge'
  scenario_script reviewer 'MESSAGE=found; cbugs add --kind code --title "Finding" --note x >/dev/null'
  scenario merge SLEEP=30
  CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" --timeout 30 docs/requirements.md >"$output_file" 2>&1 &
  panel_pid=$!
  for ((i = 0; i < 100; i++)); do
    [[ $(call_count 'role=merge') -ge 1 ]] && break
    sleep 0.1
  done
  [[ $(call_count 'role=merge') -ge 1 ]] || fail "the merge agent did not start"
  kill -TERM "$panel_pid" 2>/dev/null || true
  wait "$panel_pid"; status=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' "$output_file")
  assert_eq "$status" 143 "panel status"
  assert_output_contains "merge profile claude:merge stopped by the operator"
  assert_output_lacks "merge profile claude:merge: exit status 124"
}
