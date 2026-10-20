# The no-argument summary uses the same title form as cbugs list (CB-SUM-2).

test_summary_decodes_bug_titles() {
  CONVERGE_RUN_DIR=$WORK "$CBUGS" add --kind code --title 'First title' --note test \
    >/dev/null || fail "cbugs add failed"
  local output
  output=$(CONVERGE_RUN_DIR=$WORK "$CBUGS") || fail "cbugs summary failed"
  OUTPUT=$output
  assert_output_contains 'First title'
  [[ $output != *'Rmlyc3QgdGl0bGU='* ]] || fail "summary printed a base64 title"
}
