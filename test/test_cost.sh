# The cost ledger and the cost summary (CV-COST-1 through CV-COST-10).

LOOP_ARGS=(--foreground --no-coach --no-review)

ledger() {
  cat "$(state_dir)/cost-history.tsv"
}

test_ledger_rows_per_invocation() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b:high'
  scenario worker MESSAGE=work COST=0.25
  scenario worker MESSAGE=work
  scenario worker MESSAGE=work COST=0
  run_converge "${LOOP_ARGS[@]}" --max-iterations 3 docs/requirements.md
  assert_status 1
  local session expected
  session=$(cat "$(state_dir)/current")
  expected=$(printf '%s\tworker\tclaude:a\t0.25\n%s\tworker\tclaude:b:high\t\n%s\tworker\tclaude:a\t0\n' \
    "$session" "$session" "$session")
  assert_eq "$(ledger)" "$expected" "cost ledger"
}

# Absent cost is logged as null, never as a recorded zero.
test_absent_cost_is_null_in_the_log() {
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  grep -q '"event":"cost","cost_usd":null' "$(state_dir)"/logs/*-0001-worker.jsonl ||
    fail "the worker log has no null cost event"
  assert_output_contains "Total spend                         —        —"
}

# A failed attempt with a cost still has its row, under its own profile.
test_failed_attempt_has_a_row() {
  export CONVERGE_WORKER_PROFILE='claude:a,claude:b'
  scenario worker EXIT=1 COST=0.1
  scenario worker MESSAGE=work COST=0.2
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_eq "$(ledger | cut -f2- | paste -sd'|')" $'worker\tclaude:a\t0.1|worker\tclaude:b\t0.2' "ledger rows"
}

# A zero cost is a sample; an absent cost is not (CV-COST-3).
test_summary_averages_count_only_recorded_costs() {
  scenario worker MESSAGE=work COST=0.3
  scenario worker MESSAGE=work
  scenario worker MESSAGE=work COST=0
  run_converge "${LOOP_ARGS[@]}" --max-iterations 3 docs/requirements.md
  assert_output_contains "Total spend                     \$0.300000  \$0.300000"
  assert_output_contains "Average per worker invocation   \$0.150000  \$0.150000"
}

# The cumulative column carries costs from earlier sessions; the session
# column does not.
test_cumulative_cost_across_sessions() {
  scenario worker MESSAGE=CONVERGED COST=1.5
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  scenario worker MESSAGE=CONVERGED COST=0.5
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  assert_output_contains "Total spend                     \$0.500000  \$2.000000"
  [[ $(ledger | cut -f1 | sort -u | wc -l) == 2 ]] || fail "expected two sessions in the ledger"
}

# OpenCode reports cost per step, so the loop sums the stream.
test_opencode_stream_cost() {
  export CONVERGE_WORKER_PROFILE='opencode:p/m'
  scenario worker MESSAGE=work COST=0.125
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_eq "$(ledger | cut -f2-)" $'worker\topencode:p/m\t0.1250000000' "ledger row"
}

# Codex reports no dollar cost; the cost stays absent.
test_codex_cost_is_absent() {
  export CONVERGE_WORKER_PROFILE='codex:gpt-5-codex'
  scenario worker MESSAGE=work
  run_converge "${LOOP_ARGS[@]}" --max-iterations 1 docs/requirements.md
  assert_eq "$(ledger | cut -f2-)" $'worker\tcodex:gpt-5-codex\t' "ledger row"
}

# A torn line from a killed run is dropped, not counted, and the costs of
# later sessions still count (CV-COST-9).
#
test_torn_ledger_line_is_ignored() {
  local dir
  dir=$("$CONVERGE" --init-state)
  printf 'old\tworker\tclaude:sonnet\t2\nold\twork' >"$dir/cost-history.tsv"
  scenario worker MESSAGE=CONVERGED COST=1
  run_converge "${LOOP_ARGS[@]}" --consensus 1 docs/requirements.md
  assert_status 0
  session_cost_counted() {
    [[ $OUTPUT == *"Total spend                     \$1.000000  \$3.000000"* ]]
  }
  session_cost_counted || fail "the session cost was not counted after a torn ledger line"
}
