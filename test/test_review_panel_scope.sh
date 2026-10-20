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
