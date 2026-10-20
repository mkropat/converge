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
