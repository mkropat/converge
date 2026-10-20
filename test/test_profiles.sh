# Profile parsing (CV-HARN-12, CV-HARN-17 through CV-HARN-19, CV-HARN-25).
# The loop validates every profile variable at startup, before any agent
# starts, so --consensus 0 gives a run that parses profiles and stops.

# start_loop   Runs a loop that parses the profiles and starts no agent.
start_loop() {
  run_converge --foreground --consensus 0 docs/requirements.md
}

# expect_profile_error <message>   Checks for a startup stop that names it.
expect_profile_error() {
  start_loop
  assert_status 2
  assert_output_contains "$1"
  assert_calls 0
}

test_default_profiles_shown_on_the_panel() {
  start_loop
  assert_status 0
  assert_output_contains "worker     claude:sonnet"
  assert_output_contains "review     claude:opus"
  assert_output_contains "coach      claude:opus"
  assert_output_contains "fixer      worker profile list"
}

test_bad_profile_syntax() {
  local bad
  for bad in claude gpt:x claude: :x claude:a:b:c 'claude:so net' 'claude::high' 'Claude:x'; do
    export CONVERGE_WORKER_PROFILE=$bad
    expect_profile_error "must be claude:model[:effort], opencode:model[:effort], or codex:model[:effort]"
  done
}

test_each_role_variable_is_parsed() {
  local var
  for var in CONVERGE_WORKER_PROFILE CONVERGE_REVIEWER_PROFILE CONVERGE_COACH_PROFILE \
    CONVERGE_FIXER_PROFILE CONVERGE_REVIEW_PANEL_PROFILE CONVERGE_REVIEW_PANEL_MERGE_PROFILE; do
    (
      export "$var=bogus"
      expect_profile_error "profile 'bogus' must be"
    ) || exit 1
  done
}

test_empty_but_set_variables_rejected() {
  local var
  for var in CONVERGE_WORKER_PROFILE CONVERGE_REVIEWER_PROFILE CONVERGE_COACH_PROFILE \
    CONVERGE_FIXER_PROFILE CONVERGE_REVIEW_PANEL_PROFILE CONVERGE_REVIEW_PANEL_MERGE_PROFILE; do
    (
      export "$var="
      expect_profile_error "$var is set but empty"
    ) || exit 1
  done
}

# A disabled role still has its profiles checked (CV-HARN-19).
test_disabled_roles_are_still_validated() {
  export CONVERGE_COACH_PROFILE=claude CONVERGE_REVIEWER_PROFILE=claude:opus
  run_converge --foreground --consensus 0 --no-coach --no-review docs/requirements.md
  assert_status 2
  assert_output_contains "coach profile 'claude' must be"
}

test_duplicate_entries_after_trimming() {
  export CONVERGE_WORKER_PROFILE='claude:sonnet,  claude:sonnet '
  expect_profile_error "worker profile list repeats 'claude:sonnet'"
}

# A different effort makes a different profile.
test_same_model_with_different_effort_is_no_duplicate() {
  export CONVERGE_WORKER_PROFILE='claude:sonnet,claude:sonnet:high'
  start_loop
  assert_status 0
  assert_output_contains "worker     claude:sonnet, claude:sonnet:high"
}

test_spaces_around_entries_are_trimmed() {
  export CONVERGE_WORKER_PROFILE='  claude:sonnet ,	codex:gpt-5-codex  '
  start_loop
  assert_status 0
  assert_output_contains "worker     claude:sonnet, codex:gpt-5-codex"
}

test_trailing_leading_and_inner_empty_entries() {
  local list
  for list in 'claude:sonnet,' ',claude:sonnet' 'claude:sonnet,,claude:opus' 'claude:sonnet, '; do
    export CONVERGE_WORKER_PROFILE=$list
    expect_profile_error "worker profile '' must be"
  done
}

test_newline_in_list_rejected() {
  export CONVERGE_WORKER_PROFILE=$'claude:sonnet\nclaude:opus'
  expect_profile_error "worker profile list must use commas between entries"
}

test_claude_efforts() {
  local e
  for e in low medium high xhigh max; do
    export CONVERGE_WORKER_PROFILE="claude:sonnet:$e"
    start_loop
    assert_status 0
  done
  export CONVERGE_WORKER_PROFILE=claude:sonnet:huge
  expect_profile_error "worker profile 'claude:sonnet:huge' has an effort claude does not support"
}

# OpenCode variants and Codex efforts pass through unvalidated (CV-HARN-18).
test_other_harness_efforts_pass_through() {
  export CONVERGE_WORKER_PROFILE='opencode:provider/model:anything,codex:gpt-5-codex:whatever'
  start_loop
  assert_status 0
}

test_retired_variables_rejected_even_when_empty() {
  local var
  for var in CONVERGE_HARNESS CONVERGE_CLAUDE_MODEL CONVERGE_CLAUDE_REVIEW_MODEL \
    CONVERGE_CLAUDE_COACH_MODEL CONVERGE_OPENCODE_MODEL \
    CONVERGE_OPENCODE_REVIEW_MODEL CONVERGE_OPENCODE_COACH_MODEL; do
    (
      export "$var="
      expect_profile_error "$var is retired; set CONVERGE_WORKER_PROFILE"
    ) || exit 1
  done
}

# The client rejects a retired variable in the operator's terminal, before
# it starts a background loop that would only fail there.
test_client_rejects_retired_variable() {
  export CONVERGE_HARNESS=claude
  run_converge --consensus 0 docs/requirements.md
  assert_status 2
  assert_output_contains "CONVERGE_HARNESS is retired"
  [[ -z $(ls "$(state_dir)/sessions" 2>/dev/null) ]] || fail "the client started a session"
}

test_fixer_profile_shown_when_set() {
  export CONVERGE_FIXER_PROFILE='claude:opus:max'
  start_loop
  assert_status 0
  assert_output_contains "fixer      claude:opus:max"
}

test_fixer_profile_list_is_not_shortened() {
  local profiles='claude:opus:max, codex:gpt-5-codex:high, opencode:anthropic/claude-opus-4-1:high, codex:gpt-5:xhigh'
  export CONVERGE_FIXER_PROFILE=$profiles
  start_loop
  assert_status 0
  assert_output_contains "fixer      $profiles"
}
