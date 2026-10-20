# Argument validation. Every test here stops before an agent starts, so the
# fake harness queue stays empty and any harness call is a failure.

# expect_usage_error <message> <args...>   Runs converge and checks for a
# usage stop (status 2) that names the problem and starts no agent.
expect_usage_error() {
  local message=$1; shift
  run_converge "$@"
  assert_status 2
  assert_output_contains "$message"
  assert_calls 0
}

test_help_prints_usage_and_exits_zero() {
  run_converge --help
  assert_status 0
  assert_output_contains "Usage: converge [options] [scope ...]"
  run_converge -h
  assert_status 0
  assert_output_contains "Usage: converge"
}

test_help_makes_no_state() {
  run_converge --help
  assert_status 0
  [[ -z $(ls -A "$XDG_STATE_HOME") ]] || fail "--help made state: $(ls -A "$XDG_STATE_HOME")"
}

# The parser judges the whole call before it acts on help (CV-INV-11).
test_help_does_not_hide_a_rejected_argument() {
  expect_usage_error "unknown option '--bogus'" --help --bogus
}

test_unknown_option() {
  expect_usage_error "unknown option '--bogus'" --foreground --bogus
}

test_unknown_option_rejected_by_the_client_too() {
  expect_usage_error "unknown option '--bogus'" --bogus
}

test_missing_value_at_the_end() {
  expect_usage_error "'--consensus' needs a value" --foreground --consensus
}

# A following option is not taken as the value; the parser still reads it.
test_missing_value_before_an_option() {
  expect_usage_error "'--timeout' needs a value" --timeout --bogus
  assert_output_contains "unknown option '--bogus'"
}

test_every_value_option_needs_a_value() {
  local opt
  for opt in --consensus --blocked --stall-after --stall-notify --coach-first \
    --coach-every --review-after --timeout --max-iterations; do
    expect_usage_error "'$opt' needs a value" --foreground "$opt"
  done
}

# A negative number looks like an option, so it reads as a missing value.
test_negative_value_reads_as_missing() {
  expect_usage_error "'--timeout' needs a value" --foreground --timeout -1
}

test_retired_options() {
  local opt
  for opt in --model --model=opus --harness --harness=claude --coach-model \
    --coach-model=x --review-model --review-model=x; do
    expect_usage_error "'$opt' is retired" --foreground "$opt"
  done
}

test_arguments_after_double_dash() {
  expect_usage_error "unexpected argument '--model' after --" --foreground -- --model opus
  assert_output_contains "unexpected argument 'opus' after --"
}

# A bare -- with nothing after it passes nothing through, so it is accepted.
test_bare_double_dash_is_accepted() {
  run_converge --foreground --consensus 0 docs/requirements.md --
  assert_status 0
  assert_calls 0
}

# One call reports every rejected argument, not only the first (CV-INV-11).
test_all_rejections_reported_together() {
  run_converge --bogus --model x --consensus -- extra
  assert_status 2
  assert_output_contains "unknown option '--bogus'"
  assert_output_contains "'--model' is retired"
  assert_output_contains "'--consensus' needs a value"
  assert_output_contains "unexpected argument 'extra' after --"
}

test_non_integer_values() {
  local opt
  for opt in --consensus --blocked --stall-after --stall-notify --coach-first \
    --coach-every --review-after --timeout; do
    expect_usage_error "$opt needs a whole number, got 'abc'" --foreground "$opt" abc
    expect_usage_error "$opt needs a whole number, got '1.5'" --foreground "$opt=1.5"
  done
  expect_usage_error "--max-iterations needs a whole number" --foreground --max-iterations abc
  expect_usage_error "--max-iterations needs a whole number" --foreground --max-iterations=
}

# The client checks the values too, before it starts a loop (CV-SCOPE-2).
test_client_validates_before_spawning() {
  expect_usage_error "--consensus needs a whole number" --consensus abc
  [[ -z $(ls "$(state_dir)/sessions" 2>/dev/null) ]] || fail "the client started a session"
}

test_zero_rejected_where_positive_needed() {
  local opt
  for opt in --blocked --stall-after --stall-notify --coach-every --review-after; do
    expect_usage_error "$opt needs a positive integer" --foreground "$opt" 0
  done
}

test_zero_consensus_converges_without_agents() {
  run_converge --foreground --consensus 0 docs/requirements.md
  assert_status 0
  assert_output_contains "converged after 0 iterations"
  assert_calls 0
}

test_zero_max_iterations_stops_without_agents() {
  run_converge --foreground --max-iterations 0 docs/requirements.md
  assert_status 1
  assert_output_contains "reached the limit of 0 iterations"
  assert_calls 0
}

# Zero is a whole number, so these accept it.
test_zero_coach_first_and_timeout_accepted() {
  run_converge --foreground --consensus 0 --coach-first 0 --timeout 0 docs/requirements.md
  assert_status 0
}

# Bash reads 08 as bad octal and 010 as eight. The values must read as
# decimal (validate_start_options normalizes them).
test_leading_zero_values_read_as_decimal() {
  run_converge --foreground --consensus 0 --max-iterations 08 --coach-every 010 docs/requirements.md
  assert_status 0
  assert_output_contains "at most 8 iterations"
  assert_output_contains "then every 10 iterations"
}

test_overflow_rejected() {
  expect_usage_error "--timeout exceeds the supported integer range" \
    --foreground --timeout 9223372036854775808
  expect_usage_error "--consensus exceeds the supported integer range" \
    --foreground --consensus 99999999999999999999
  expect_usage_error "--max-iterations exceeds the supported integer range" \
    --foreground --max-iterations 9223372036854775808
}

test_largest_integer_accepted() {
  run_converge --foreground --consensus 0 --timeout 9223372036854775807 \
    --max-iterations 0009223372036854775807 docs/requirements.md
  assert_status 0
}

test_equals_form_values() {
  run_converge --foreground --consensus=0 --blocked=3 --stall-after=4 \
    --stall-notify=5 --coach-first=6 --coach-every=7 --review-after=8 \
    --timeout=9 --max-iterations=10 docs/requirements.md
  assert_status 0
  assert_output_contains "at most 10 iterations"
  assert_output_contains "blocked after 3 blocked votes"
  assert_output_contains "9s for one invocation"
}

test_missing_scope_path() {
  expect_usage_error "scope path 'docs/nope.md' does not exist" --foreground docs/nope.md
}

test_init_state_alone() {
  run_converge --init-state
  assert_status 0
  local dir=$OUTPUT
  [[ $dir == "$XDG_STATE_HOME"/converge/repo-* ]] || fail "unexpected state path '$dir'"
  [[ -d $dir/logs && -d $dir/sessions ]] || fail "--init-state did not make $dir/logs and sessions"
  [[ -d $TMPDIR/converge/${dir##*/} ]] || fail "--init-state did not make the runtime directory"
  # The init operation writes no session output and no log (CV-INV-10.3).
  [[ ! -e $dir/converge.log && -z $(ls -A "$dir/sessions") ]] || fail "--init-state wrote a log or a session"
}

test_init_state_twice_succeeds() {
  run_converge --init-state
  local first=$OUTPUT
  run_converge --init-state
  assert_status 0
  assert_eq "$OUTPUT" "$first" "state path"
}

test_init_state_rejects_other_arguments() {
  expect_usage_error "--init-state cannot be combined with '--foreground'" --init-state --foreground
  expect_usage_error "--init-state cannot be combined with 'docs/requirements.md'" --init-state docs/requirements.md
  expect_usage_error "--init-state cannot be combined with '--consensus=1'" --consensus=1 --init-state
  expect_usage_error "--init-state cannot be combined with '--state-dir'" --init-state --state-dir
  [[ -z $(ls -A "$XDG_STATE_HOME") ]] || fail "a rejected --init-state made state"
}

test_init_state_with_help_prints_help_only() {
  run_converge --init-state --help
  assert_status 0
  assert_output_contains "Usage: converge"
  [[ -z $(ls -A "$XDG_STATE_HOME") ]] || fail "--init-state --help made state"
}

test_state_dir_prints_path_and_makes_nothing() {
  run_converge --state-dir
  assert_status 0
  [[ $OUTPUT == "$XDG_STATE_HOME"/converge/repo-* ]] || fail "unexpected state path '$OUTPUT'"
  [[ -z $(ls -A "$XDG_STATE_HOME") && -z $(ls -A "$TMPDIR") ]] || fail "--state-dir made a directory"
  local query=$OUTPUT
  run_converge --init-state
  assert_eq "$OUTPUT" "$query" "--state-dir and --init-state paths"
}

test_state_dir_rejects_other_arguments() {
  expect_usage_error "--state-dir cannot be combined with '--foreground'" --state-dir --foreground
  expect_usage_error "--state-dir cannot be combined with 'docs'" --state-dir docs
}

test_state_dir_with_help_prints_help() {
  run_converge --state-dir -h
  assert_status 0
  assert_output_contains "Usage: converge"
}

# A subdirectory is its own run directory, with its own state (CV-ID).
test_state_dir_differs_per_run_directory() {
  local root sub
  root=$("$CONVERGE" --state-dir)
  sub=$(cd docs && "$CONVERGE" --state-dir)
  [[ $root != "$sub" ]] || fail "root and docs share state $root"
  [[ ${sub##*/} == repo-docs-* ]] || fail "unexpected subdirectory slug '${sub##*/}'"
}

test_needs_home_or_xdg_state_home() {
  run_converge_env() { STATUS=0; OUTPUT=$(env -u HOME -u XDG_STATE_HOME "$CONVERGE" --state-dir 2>&1) || STATUS=$?; }
  run_converge_env
  assert_status 2
  assert_output_contains "set HOME or XDG_STATE_HOME"
}

# --foreground never attaches: a loop that holds the lock stops it (CV-BG-10).
test_foreground_refuses_when_a_loop_runs() {
  local runtime
  runtime="$TMPDIR/converge/$(basename "$(state_dir)")"
  mkdir -p "$runtime"
  # Hold the loop lock the way a running loop holds it.
  flock "$runtime/loop.lock" sleep 30 &
  local holder=$!
  local i
  for ((i = 0; i < 50; i++)); do
    flock -n "$runtime/loop.lock" true || break
    sleep 0.1
  done
  run_converge --foreground docs/requirements.md
  kill "$holder" 2>/dev/null
  assert_status 2
  assert_output_contains "a converge loop already runs for this run directory"
  assert_calls 0
}
