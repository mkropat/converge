# The report must show each retained bug and count each kind (RP-OUT-3).

test_complete_panel_reports_retained_code_and_spec_bugs() {
  scenario_script reviewer '
    cbugs add --kind code --title "Code finding" --note evidence >/dev/null
    cbugs add --kind spec --title "Spec finding" --note evidence >/dev/null
  '
  scenario merge MESSAGE='no duplicates'
  local output
  output=$(CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_status 1
  assert_output_contains '1 retained new code bug, 1 retained new spec bug'
  assert_output_contains 'retained new code bug #1: Code finding'
  assert_output_contains 'retained new spec bug #2: Spec finding'
  assert_output_lacks 'No new bugs found.'
  assert_output_lacks 'bug #false'
}

test_panel_reports_bugs_after_first_findings_read_fails() {
  cp "$REPO_ROOT/bin/review-panel" "$TEST_TMP/bin/review-panel"
  export PANEL_TEST_CBUGS="$CBUGS"
  export PANEL_TEST_FINDINGS_READ="$TEST_TMP/findings-read"
  cat >"$TEST_TMP/bin/cbugs" <<'EOF'
#!/usr/bin/env bash
if [[ ${1-} == list && ${2-} == --panel-run && ! -f $PANEL_TEST_FINDINGS_READ ]]; then
  : >"$PANEL_TEST_FINDINGS_READ"
  exit 1
fi
exec "$PANEL_TEST_CBUGS" "$@"
EOF
  chmod +x "$TEST_TMP/bin/cbugs"
  scenario_script reviewer 'cbugs add --kind code --title "Code finding" --note evidence >/dev/null'
  scenario merge MESSAGE='no duplicates'
  local output
  output=$(CONVERGE_RUN_DIR="$WORK" "$TEST_TMP/bin/review-panel" docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_status 2
  assert_output_contains '1 retained new code bug, 0 retained new spec bugs'
  assert_output_contains 'retained new code bug #1: Code finding'
  assert_output_contains 'findings: cbugs list --panel-run failed before the merge'
  assert_output_contains 'the summary above is incomplete'
  assert_output_lacks 'No new bugs found.'
  assert_output_lacks 'bug #false'
}

test_panel_retains_bug_dismissed_by_another_writer() {
  scenario_script reviewer 'cbugs add --kind code --title "Code finding" --note evidence >/dev/null'
  scenario_script merge '
    env -u CONVERGE_ROLE -u REVIEW_PANEL_RUN -u REVIEW_PANEL_PROFILE -u REVIEW_PANEL_INVOCATION \
      cbugs dismiss 1 --note "Accepted by another writer" >/dev/null
    cbugs note 1 --note "No duplicate found" >/dev/null
  '
  local output
  output=$(CONVERGE_RUN_DIR="$WORK" "$REPO_ROOT/bin/review-panel" docs/requirements.md 2>&1)
  STATUS=$?
  OUTPUT=$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$output")
  assert_status 1
  assert_output_contains 'retained new code bug #1: Code finding'
  assert_output_lacks 'No new bugs found.'
}
