# An unscoped panel names its accepted lookup instructions as its scope (RP-OUT-1).

test_unscoped_panel_reports_lookup_scope() {
  local lookup="$TEST_TMP/lookup.txt" output
  printf 'Read docs/requirements.md.\n' >"$lookup"
  scenario reviewer MESSAGE='nothing found'
  output=$(cd "$WORK" && CONVERGE_RUN_DIR="$WORK" \
    CONVERGE_REQUIREMENTS_LOOKUP_REQUIRED=1 \
    CONVERGE_REQUIREMENTS_LOOKUP_FILE="$lookup" \
    "$REPO_ROOT/bin/review-panel" 2>&1) || fail "review-panel failed"
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_output_contains "scope"
  assert_output_contains "from requirements lookup instructions"
  assert_output_lacks "empty (the run directory)"
}

test_zero_timeout_selects_the_finite_limit() {
  scenario reviewer MESSAGE='nothing found'
  local output
  output=$(CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" --timeout 0 docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_eq "$STATUS" 0 "panel status"
  assert_output_contains '2147483647s for one invocation'
}

test_opencode_effort_uses_one_model_option() {
  export CONVERGE_REVIEW_PANEL_PROFILE='opencode:provider/model:fast'
  scenario reviewer MESSAGE='nothing found'
  (cd "$WORK" && CONVERGE_RUN_DIR="$WORK" \
    "$REPO_ROOT/bin/review-panel" docs/requirements.md) >/dev/null 2>&1 ||
    fail "review-panel failed"
  assert_eq "$(call_field 1 model)" 'provider/model' "OpenCode model"
  assert_eq "$(call_field 1 effort)" fast "OpenCode effort"
}

test_panel_does_not_pass_environment_review_pass_to_agents() {
  export CONVERGE_REVIEW_PASS=stale-pass
  scenario reviewer MESSAGE='nothing found'
  (cd "$WORK" && CONVERGE_RUN_DIR="$WORK" \
    "$REPO_ROOT/bin/review-panel" docs/requirements.md) >/dev/null 2>&1 ||
    fail "review-panel failed"
  assert_eq "$(call_field 1 review_pass)" unset "review pass environment"
}

test_codex_final_message_is_marked_after_following_tool() {
  export CONVERGE_REVIEW_PANEL_PROFILE='codex:gpt-5-codex'
  scenario reviewer MESSAGE=$'FIRST commentary\nReview complete.' FOLLOWUP_TOOL=1
  local output before_tool after_tool
  output=$(cd "$WORK" && CONVERGE_RUN_DIR="$WORK" \
    "$REPO_ROOT/bin/review-panel" docs/requirements.md 2>&1) ||
    fail "review-panel failed"
  OUTPUT=$(sed -E $'s/\\x1b\\[[0-9;]*m//g' <<<"$output")
  before_tool=${OUTPUT%%'❯ true'*}
  after_tool=${OUTPUT#*'❯ true'}
  [[ $before_tool == *'FIRST commentary'* ]] || fail "commentary did not precede the tool call"
  [[ $after_tool == *'▍ reviewer 1/1 codex:gpt-5-codex Review complete.'* ]] ||
    fail "final message was not repeated after the tool call"
}

test_codex_mcp_web_search_and_failed_file_change_are_visible_in_panel() {
  export CONVERGE_REVIEW_PANEL_PROFILE='codex:gpt-5-codex'
  scenario reviewer MESSAGE='Review complete.' MCP_TOOL=1 MCP_STATUS=failed \
    MCP_ERROR='MCP boom' WEB_SEARCH=1 FILE_KIND=update FILE_STATUS=failed \
    FILE_ERROR='file boom'
  local output
  output=$(cd "$WORK" && CONVERGE_RUN_DIR="$WORK" \
    "$REPO_ROOT/bin/review-panel" docs/requirements.md 2>&1) ||
    fail "review-panel failed"
  OUTPUT=$(sed -E $'s/\\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_output_contains 'mcp files/read'
  assert_output_contains 'web_search latest result'
  assert_output_contains 'MCP boom'
  assert_output_contains 'update changed.txt'
  assert_output_contains 'file boom'
}

test_panel_excludes_dismissed_duplicates_from_retained_findings() {
  export CONVERGE_REVIEW_PANEL_MERGE_PROFILE='claude:merge'
  cbugs add --kind code --title 'Existing finding' --note 'existing' \
    --cite docs/requirements.md >/dev/null || fail "could not create existing bug"
  scenario_script reviewer 'cbugs add --kind code --title "Duplicate finding" --note "same defect" --cite docs/requirements.md >/dev/null'
  scenario_script merge 'new_id=$(cbugs list --panel-run "$REVIEW_PANEL_RUN" --json | jq -r ".[0].id"); cbugs dismiss "$new_id" --note "duplicate of 1" >/dev/null'
  local output
  output=$(cd "$WORK" && CONVERGE_RUN_DIR="$WORK" \
    "$REPO_ROOT/bin/review-panel" docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_eq "$STATUS" 0 "panel status"
  assert_output_lacks 'retained new code bug'
  assert_output_contains 'No new bugs found.'
}
