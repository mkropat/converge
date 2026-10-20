# Cadence review passes (CV-REV-16 through CV-REV-20) and vote panels
# (CV-CONV-23). These run the real bin/cbugs and bin/review-panel; only the
# agents are fake.

# roles   Prints "<role>@<iteration>" for every call, in order.
roles() {
  calls | sed -E 's/.* role=([^ ]*) iteration=([^ ]*) .*/\1@\2/' | paste -sd' '
}

pending() {
  CONVERGE_RUN_DIR=$WORK "$CBUGS" reviewed pending
}

# reviewed_rows   Prints "<iteration> <profile>" for each coverage record.
reviewed_rows() {
  sqlite3 "$(state_dir)/cbugs.db" 'SELECT iteration, profile FROM reviewed ORDER BY id;'
}

# The repository starts with one unreviewed commit, so --review-after 1
# makes a pass due before the first worker, and again after each commit.
test_cadence_pass_before_and_after_workers() {
  scenario reviewer MESSAGE="nothing found"
  scenario worker MESSAGE=work COMMIT="Add the export"
  scenario reviewer MESSAGE="nothing found"
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_eq "$(roles)" "reviewer@0 worker@1 reviewer@1 worker@2" "call order"
  assert_output_contains "pending review 1 unreviewed commit"
  assert_output_contains "the pass recorded 1 commit"
  assert_eq "$(pending)" "" "unreviewed commits after the run"
  assert_eq "$(reviewed_rows | paste -sd,)" "0|claude:opus,1|claude:opus" "coverage records"
  call_prompt 1 | grep -qF "Add requirements" ||
    fail "the first reviewer prompt does not list the unreviewed commit"
  call_prompt 3 | grep -qF "Add the export" ||
    fail "the second reviewer prompt does not list the new commit"
}

test_no_pass_below_the_threshold() {
  scenario worker MESSAGE=work COMMIT="one"
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 3 --max-iterations 2 docs/requirements.md
  assert_status 1
  assert_calls 0 "role=reviewer"
  assert_eq "$(pending | wc -l)" 2 "unreviewed commits"
}

test_no_review_disables_cadence_passes() {
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --no-review --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_calls 0 "role=reviewer"
}

# A failed pass records no coverage; the commits stay unreviewed.
test_failed_pass_records_nothing() {
  scenario reviewer MESSAGE=oops EXIT=1
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "the pass failed and recorded no commit"
  assert_eq "$(pending | wc -l)" 1 "unreviewed commits"
}

# A reviewer chain falls back, and coverage names the profile that
# succeeded (CV-HARN-24).
test_reviewer_fallback_records_the_successful_profile() {
  export CONVERGE_REVIEWER_PROFILE='claude:r1,claude:r2'
  scenario reviewer EXIT=1
  scenario reviewer MESSAGE="nothing found"
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_eq "$(reviewed_rows)" "0|claude:r2" "coverage records"
}

test_bugs_logged_by_a_pass_are_reported() {
  scenario_script reviewer 'MESSAGE=found; cbugs add --kind code --title "Export drops rows" --cite docs/requirements.md:T-1 >/dev/null'
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "bug #1 code Export drops rows"
  CONVERGE_RUN_DIR=$WORK "$CBUGS" list --json | jq -e 'length == 1 and .[0].title == "Export drops rows"' >/dev/null ||
    fail "the bug is not in the tracker"
}

# The first done vote starts one vote panel, which runs before the
# convergence exit (CV-CONV-23). Panel reviewers run with no iteration.
test_first_done_vote_runs_a_vote_panel() {
  scenario worker MESSAGE=CONVERGED
  scenario reviewer MESSAGE="nothing found" COST=0.5
  run_converge --foreground --no-coach --review-after 100 --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" "worker@1 reviewer@unset" "call order"
  assert_output_contains "the vote panel read the live working tree and reported no error"
  # The panel shares the loop's cost session and ledger (CV-COST-10).
  local session
  session=$(cat "$(state_dir)/current")
  grep -qx "$session"$'\treviewer\tclaude:opus\t0.5' "$(state_dir)/cost-history.tsv" ||
    fail "the panel reviewer row is not in the session ledger"
}

# Only a change of the count from zero to one starts a panel.
test_one_panel_per_vote_streak() {
  scenario worker MESSAGE=CONVERGED
  scenario reviewer MESSAGE="nothing found"
  scenario worker MESSAGE=CONVERGED
  run_converge --foreground --no-coach --review-after 100 --consensus 2 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" "worker@1 reviewer@unset worker@2" "call order"
}

# Panel findings are advisory: they do not stop convergence (CV-CONV-22).
test_panel_findings_do_not_block_convergence() {
  export CONVERGE_REVIEW_PANEL_MERGE_PROFILE='claude:merger'
  scenario worker MESSAGE=CONVERGED
  scenario_script reviewer 'MESSAGE=found; cbugs add --kind code --title "Late defect" --cite docs/requirements.md:T-1 >/dev/null'
  scenario merge MESSAGE="no duplicates"
  run_converge --foreground --no-coach --review-after 100 --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" "worker@1 reviewer@unset merge@unset" "call order"
  assert_eq "$(call_field 3 model)" merger "merge model"
  assert_output_contains "retained new code bugs"
}

test_no_review_disables_the_vote_panel() {
  scenario worker MESSAGE=CONVERGED
  run_converge --foreground --no-coach --no-review --consensus 1 docs/requirements.md
  assert_status 0
  assert_calls 0 "role=reviewer"
}
