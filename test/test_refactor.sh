# Refactor pass scheduling, boundaries, and vote handling.

roles() {
  calls | sed -E 's/.* role=([^ ]*) iteration=([^ ]*) .*/\1@\2/' | paste -sd' '
}

test_done_vote_runs_refactor_before_panel_and_convergence() {
  export CONVERGE_WORKER_PROFILE='claude:worker-a,claude:worker-b'
  scenario worker MESSAGE=CONVERGED
  scenario refactor MESSAGE='no safe refactor'
  run_converge --foreground --no-coach --no-review --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" "worker@1 refactor@1" "call order"
  assert_eq "$(call_field 1 model)" worker-a "worker profile"
  assert_eq "$(call_field 2 model)" worker-a "independent refactor profile"
  call_prompt 2 | grep -qF 'Session start commit:' || fail "Refactor prompt omits session boundary"
  call_prompt 2 | grep -qF 'Pass start commit:' || fail "Refactor prompt omits pass boundary"
  call_prompt 2 | grep -qF 'Cite the coding standard' || fail "Refactor prompt omits coding standard rule"
}

test_no_refactor_keeps_normal_done_vote() {
  scenario worker MESSAGE=CONVERGED
  run_converge --foreground --no-coach --no-review --no-refactor --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_count)" 1 "invocation count"
}

test_refactor_environment_and_cost_use_distinct_role() {
  export CONVERGE_REVIEW_PASS=outer-value
  scenario_script worker 'MESSAGE=CONVERGED; printf "%s %s %s\n" "$CONVERGE_ROLE" "$CONVERGE_ITERATION" "${CONVERGE_REVIEW_PASS-unset}" >>"$FAKE_HARNESS_DIR/env.log"'
  scenario_script refactor 'MESSAGE="no safe refactor"; printf "%s %s %s\n" "$CONVERGE_ROLE" "$CONVERGE_ITERATION" "${CONVERGE_REVIEW_PASS-unset}" >>"$FAKE_HARNESS_DIR/env.log"; COST=0.25'
  run_converge --foreground --no-coach --no-review --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(cat "$FAKE_HARNESS_DIR/env.log")" $'worker 1 unset\nrefactor 1 unset' 'agent environments'
  grep -q $'\trefactor\tclaude:sonnet\t0.25$' "$(state_dir)/cost-history.tsv" ||
    fail "Refactor cost did not use the distinct role"
  assert_output_contains 'Average per refactor invocation $0.250000'
}

test_cadence_refactor_runs_before_next_worker() {
  scenario worker MESSAGE=work COMMIT='worker change'
  scenario refactor MESSAGE='no safe refactor'
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --no-review --refactor-after 1 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "worker@1 refactor@1 worker@2" "call order"
  assert_output_contains 'Refactor (cadence)'
}

test_dirty_tracked_tree_skips_refactor_and_preserves_vote() {
  printf 'pre-existing change\n' >> docs/requirements.md
  scenario worker MESSAGE=CONVERGED
  run_converge --foreground --no-coach --no-review --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_count)" 1 "invocation count"
  assert_output_contains 'Refactor skipped: tracked files have staged or unstaged changes'
  assert_output_lacks 'Refactor changed tracked files'
}

test_refactor_commit_clears_done_vote() {
  scenario worker MESSAGE=CONVERGED
  scenario refactor MESSAGE=refactored COMMIT='Refactor selected code'
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --no-review --consensus 1 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "worker@1 refactor@1 worker@2" "call order"
  assert_output_contains 'done and blocked votes reset'
  assert_output_lacks 'converged after'
}

test_failed_done_vote_refactor_keeps_vote_without_wait() {
  scenario worker MESSAGE=CONVERGED
  scenario refactor EXIT=1
  run_converge --foreground --no-coach --no-review --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(call_count)" 2 "invocation count"
  assert_output_lacks 'waits 10s before continuing'
  assert_output_contains 'converged after 1 iteration'
}

test_refactor_change_cancels_panel_until_next_done_vote() {
  scenario worker MESSAGE=CONVERGED
  scenario refactor MESSAGE=changed COMMIT='Refactor selected code'
  scenario worker MESSAGE=CONVERGED
  scenario refactor MESSAGE='no safe refactor'
  scenario worker MESSAGE=CONVERGED
  scenario refactor MESSAGE='no safe refactor'
  scenario reviewer MESSAGE='nothing found'
  run_converge --foreground --no-coach --review-after 100 --consensus 2 --max-iterations 3 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" 'worker@1 refactor@1 worker@2 refactor@2 reviewer@unset worker@3 refactor@3' 'call order'
  assert_output_contains 'vote panel'
  assert_output_contains 'Refactor changed tracked files; done and blocked votes reset'
}
