# Coach cadence (CV-COACH-10), stall and blocked triggers (CV-COACH-11),
# escalation to a fixer iteration (CV-HARN-26), and stall notification.

# roles   Prints "<role>@<iteration>" for every call, in order. A fixer runs
# with CONVERGE_ROLE=worker, so it shows as a worker; models tell them apart.
roles() {
  calls | sed -E 's/.* role=([^ ]*) iteration=([^ ]*) model=([^ ]*) .*/\1@\2/' | paste -sd' '
}

models() {
  calls | sed -E 's/.* model=([^ ]*) .*/\1/' | paste -sd' '
}

# work_commit   Queues a worker that commits and does not vote, so it is
# neither a vote nor a stall.
work_commit() {
  scenario worker MESSAGE=work COMMIT="work $((SCENARIO_SEQ + 1))"
}

test_coach_cadence_first_then_every() {
  work_commit; work_commit; work_commit; work_commit
  scenario coach MESSAGE="guidance written"
  scenario coach MESSAGE="guidance written"
  run_converge --foreground --no-review --coach-first 1 --coach-every 2 --max-iterations 4 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "worker@1 coach@1 worker@2 worker@3 coach@3 worker@4" "call order"
  assert_output_contains "coach (cadence)"
  assert_output_contains "after 1 iteration, then every 2 iterations"
}

test_coach_first_zero_runs_before_the_first_worker() {
  work_commit
  scenario coach MESSAGE=ok
  run_converge --foreground --no-review --coach-first 0 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "coach@0 worker@1" "call order"
}

# A failed coach still resets the cadence.
test_failed_coach_resets_the_cadence() {
  work_commit; work_commit; work_commit
  scenario coach MESSAGE=oops EXIT=1
  run_converge --foreground --no-review --coach-first 1 --coach-every 3 --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "worker@1 coach@1 worker@2 worker@3" "call order"
  assert_output_contains "coach exited with status 1"
}

test_no_coach_disables_the_coach() {
  work_commit; work_commit
  run_converge --foreground --no-review --no-coach --coach-first 0 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_calls 0 "role=coach"
}

# The coach sees the worker logs since its last run.
test_coach_prompt_lists_the_pending_worker_logs() {
  work_commit; work_commit; work_commit
  scenario coach MESSAGE=ok
  run_converge --foreground --no-review --coach-first 2 --max-iterations 3 docs/requirements.md
  assert_status 1
  local prompt
  prompt=$(call_prompt 3)
  [[ $prompt == *"-0001-worker.jsonl"* && $prompt == *"-0002-worker.jsonl"* ]] ||
    fail "the coach prompt does not list both worker logs:"$'\n'"$prompt"
}

test_guidance_reaches_the_next_worker() {
  local guidance
  guidance="$("$CONVERGE" --init-state)/guidance.md"
  work_commit
  scenario_script coach "MESSAGE=ok; printf 'Always run the unit tests.\n' >'$guidance'"
  work_commit
  run_converge --foreground --no-review --coach-first 1 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_output_contains "guidance updated"
  call_prompt 3 | grep -qF "Always run the unit tests." ||
    fail "the worker after the coach did not get the guidance"
  call_prompt 1 | grep -qF "Always run the unit tests." &&
    fail "the worker before the coach got the guidance"
  return 0
}

# ESCALATE schedules one fixer iteration on the fixer list; the worker
# rotation does not advance (CV-HARN-26.1).
test_escalation_runs_one_fixer_on_the_fixer_list() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  export CONVERGE_FIXER_PROFILE='claude:opus:max'
  work_commit
  scenario coach MESSAGE=$'The worker keeps failing at the parser.\nESCALATE'
  work_commit; work_commit
  run_converge --foreground --no-review --coach-first 1 --coach-every 100 --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_eq "$(models)" "a opus opus b" "models (worker, coach, fixer, worker)"
  assert_eq "$(roles)" "worker@1 coach@1 worker@2 worker@3" "roles"
  assert_eq "$(call_field 3 effort)" max "fixer effort"
  assert_output_contains "coach escalated; the next worker iteration will be a fixer"
  assert_output_contains "fixer iteration 2 of 3"
  call_prompt 3 | grep -qF "more capable profile for one iteration only" ||
    fail "the fixer prompt does not say it is a fixer"
  call_prompt 4 | grep -qF "more capable profile" &&
    fail "the worker after the fixer got the fixer prompt"
  cut -f2,3 "$(state_dir)/cost-history.tsv" | grep -qx $'fixer\tclaude:opus:max' ||
    fail "the ledger has no fixer row"
}

# Without a fixer list, the fixer takes the next worker profile.
test_escalation_without_fixer_list_uses_the_worker_rotation() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  work_commit
  scenario coach MESSAGE=ESCALATE
  work_commit; work_commit
  run_converge --foreground --no-review --coach-first 1 --coach-every 100 --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_eq "$(models)" "a opus b a" "models (worker, coach, fixer, worker)"
}

# ESCALATE from a failed coach schedules nothing.
test_failed_coach_cannot_escalate() {
  work_commit; work_commit
  scenario coach MESSAGE=ESCALATE EXIT=1
  run_converge --foreground --no-review --coach-first 1 --coach-every 100 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_output_lacks "fixer iteration"
}

test_blocked_vote_makes_the_coach_due() {
  scenario worker MESSAGE=$'Spec bug #9 stops all work.\nBLOCKED'
  scenario coach MESSAGE="It is a real block."
  scenario worker MESSAGE=BLOCKED
  run_converge --foreground --no-review --coach-first 100 --blocked 2 docs/requirements.md
  assert_status 3
  assert_eq "$(roles)" "worker@1 coach@1 worker@2" "call order"
  assert_output_contains "coach (blocked vote)"
  call_prompt 2 | grep -qF "Spec bug #9 stops all work." ||
    fail "the coach prompt lacks the blocked message"
  call_prompt 2 | grep -qF "no open record" || fail "the coach prompt omits missing-spec evidence"
  call_prompt 2 | grep -qF "gave up, circled" || fail "the coach prompt omits worker behavior evidence"
}

# Chains with output, no commit, and no vote are stalled (CV-COACH-11).
test_stalled_chains_make_the_coach_due() {
  scenario worker MESSAGE="looked around"
  scenario worker MESSAGE="looked around"
  scenario coach MESSAGE=ok
  work_commit
  run_converge --foreground --no-review --coach-first 100 --stall-after 2 --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "worker@1 worker@2 coach@2 worker@3" "call order"
  assert_output_contains "coach (stall)"
  call_prompt 3 | grep -qF "Consecutive stalled chains: 2." ||
    fail "the coach prompt lacks the stall count"
}

test_commit_resets_the_stall_count() {
  scenario worker MESSAGE="looked around"
  work_commit
  scenario worker MESSAGE="looked around"
  run_converge --foreground --no-review --coach-first 100 --stall-after 2 --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_calls 0 "role=coach"
}

# A chain without output is no stall.
test_chain_without_output_is_no_stall() {
  scenario worker MESSAGE="looked around"
  scenario worker EXIT=1 ASSISTANT=0
  CONVERGE_TEST_TIMEOUT=40 run_converge --foreground --no-review --coach-first 100 --stall-after 2 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_calls 0 "role=coach"
}

# The stalled notification goes out once per streak, also with no coach.
test_stall_notification_once_per_streak() {
  export CONVERGE_NOTIFY='{ printf "event=%s\n" "$1"; cat; } >>"$FAKE_HARNESS_DIR/notified"'
  scenario worker MESSAGE="looked around"
  scenario worker MESSAGE="looked around"
  scenario worker MESSAGE="looked around"
  run_converge --foreground --no-review --no-coach --stall-notify 2 --max-iterations 3 docs/requirements.md
  assert_status 1
  assert_eq "$(grep -c '^event=stalled' "$FAKE_HARNESS_DIR/notified")" 1 "stalled notifications"
  assert_file_contains "$FAKE_HARNESS_DIR/notified" "stall streak reached 2 stalled chains"
  assert_file_contains "$FAKE_HARNESS_DIR/notified" "event=limit"
}
