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
  # CV-REV-17: only a pass with no coverage record in the bug database
  # judges how far back to read.
  call_prompt 1 | grep -qF "First pass: judge how far back to read" ||
    fail "the first reviewer prompt does not grant the first-pass judgment"
  call_prompt 3 | grep -qF "First pass:" &&
    fail "the reviewer prompt after a recorded pass grants the first-pass judgment"
  call_prompt 3 | grep -qF "Every selected unreviewed commit (1, newest first)" ||
    fail "the reviewer prompt after a recorded pass does not list every commit"
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
  run_converge --foreground --no-coach --no-refactor --review-after 100 --consensus 1 docs/requirements.md
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
  run_converge --foreground --no-coach --no-refactor --review-after 100 --consensus 2 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" "worker@1 reviewer@unset worker@2" "call order"
}

# Panel findings are advisory: they do not stop convergence (CV-CONV-22).
test_panel_findings_do_not_block_convergence() {
  export CONVERGE_REVIEW_PANEL_MERGE_PROFILE='claude:merger'
  scenario worker MESSAGE=CONVERGED
  scenario_script reviewer 'MESSAGE=found; cbugs add --kind code --title "Late defect" --cite docs/requirements.md:T-1 >/dev/null'
  scenario merge MESSAGE="no duplicates"
  run_converge --foreground --no-coach --no-refactor --review-after 100 --consensus 1 docs/requirements.md
  assert_status 0
  assert_eq "$(roles)" "worker@1 reviewer@unset merge@unset" "call order"
  assert_eq "$(call_field 3 model)" merger "merge model"
  assert_output_contains "retained new code bugs"
}

test_panel_reports_new_bug_closed_outside_duplicate_merge() {
  export CONVERGE_REVIEW_PANEL_MERGE_PROFILE='claude:merger'
  scenario worker MESSAGE=CONVERGED
  scenario_script reviewer 'MESSAGE=found; id=$(cbugs add --kind code --title "Closed during panel" --note x); cbugs close "$id" --note "closed during the run" >/dev/null'
  scenario merge MESSAGE="no duplicates"
  run_converge --foreground --no-coach --no-refactor --review-after 100 --consensus 1 docs/requirements.md
  assert_status 0
  assert_output_contains "retained new code bugs"
  assert_output_contains "Closed during panel"
}

test_panel_merge_prompt_uses_creation_title_for_hidden_bug() {
  export CONVERGE_REVIEW_PANEL_MERGE_PROFILE='claude:merger'
  git -C "$WORK" checkout -q -b side
  git -C "$WORK" commit -q --allow-empty -m "Side commit"
  git -C "$WORK" checkout -q main
  scenario worker MESSAGE=CONVERGED
  scenario_script reviewer 'MESSAGE=found; git checkout -q side; id=$(cbugs add --kind code --title "Original hidden title" --commit side --note x); cbugs note "$id" --title "Unreachable revised title" --note x --commit side; git checkout -q main'
  scenario merge MESSAGE="no duplicates"
  run_converge --foreground --no-coach --no-refactor --review-after 100 --consensus 1 docs/requirements.md
  assert_status 0
  local prompt
  prompt=$(find "$(state_dir)/logs" -name '*-merge.prompt.md' -print -quit)
  [[ -n $prompt ]] || fail "the panel wrote no merge prompt"
  assert_file_contains "$prompt" "#1 (code, hidden): Original hidden title"
  if grep -qF "Unreachable revised title" "$prompt"; then
    fail "the merge prompt used an unreachable revision title"
  fi
}

test_no_review_disables_the_vote_panel() {
  scenario worker MESSAGE=CONVERGED
  run_converge --foreground --no-coach --no-review --no-refactor --consensus 1 docs/requirements.md
  assert_status 0
  assert_calls 0 "role=reviewer"
}

# env_line   Scenario text that records the role, iteration, and review pass
# of the agent that runs it.
env_line() {
  printf '%s' 'printf "%s %s %s\n" "$CONVERGE_ROLE" "${CONVERGE_ITERATION-unset}" "${CONVERGE_REVIEW_PASS-unset}" >>"$FAKE_HARNESS_DIR/env.log"'
}

# CV-ENV-10: only the reviewer of a cadence pass carries the pass id. A value
# in the environment of the loop reaches no agent and no notification.
test_review_pass_id_reaches_only_the_cadence_reviewer() {
  export CONVERGE_REVIEW_PASS=outer-value
  export CONVERGE_NOTIFY='printf "notify %s\n" "${CONVERGE_REVIEW_PASS-unset}" >>"$FAKE_HARNESS_DIR/env.log"; cat >/dev/null'
  scenario_script reviewer "MESSAGE='nothing found'; $(env_line)"
  scenario_script coach "MESSAGE=ok; $(env_line)"
  scenario_script worker "MESSAGE=CONVERGED; $(env_line)"
  scenario_script reviewer "MESSAGE='nothing found'; $(env_line)"
  run_converge --foreground --no-refactor --review-after 1 --coach-first 0 --consensus 1 docs/requirements.md
  assert_status 0
  local session
  session=$(cat "$(state_dir)/current")
  assert_eq "$(sort "$FAKE_HARNESS_DIR/env.log" | paste -sd,)" \
    "coach 0 unset,notify unset,reviewer 0 $session-review-1,reviewer unset unset,worker 1 unset" \
    "agent environments"
  assert_file_contains "$(state_dir)/converge.log" "review pass id: $session-review-1"
}

# CV-OUT-18: the report names the bugs that the reviewer created. A note on
# an old bug and a bug that the operator logs during the pass are not in it.
test_pass_report_names_only_the_bugs_the_reviewer_created() {
  CONVERGE_RUN_DIR=$WORK "$CBUGS" add --kind code --title "Old defect" --note x >/dev/null </dev/null ||
    fail "cbugs add failed"
  scenario_script reviewer 'MESSAGE=found
cbugs add --kind code --title "Export drops rows" --cite docs/requirements.md:T-1 --note x >/dev/null
cbugs note 1 "still there" >/dev/null
env -u CONVERGE_ROLE -u CONVERGE_ITERATION -u CONVERGE_REVIEW_PASS cbugs add --kind code --title "Operator defect" --note x >/dev/null'
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "bug #2 code Export drops rows"
  assert_output_lacks "bug #1 "
  assert_output_lacks "bug #3 "
  assert_output_lacks "Operator defect"
  CONVERGE_RUN_DIR=$WORK "$CBUGS" list --json | jq -e 'length == 3' >/dev/null ||
    fail "the tracker does not hold the three bugs"
}

# A fallback chain is one pass: the report names the bugs of every attempt,
# and both carry the same pass id.
test_pass_report_names_the_bugs_of_every_attempt() {
  export CONVERGE_REVIEWER_PROFILE='claude:r1,claude:r2'
  scenario_script reviewer 'EXIT=1; cbugs add --kind code --title "First attempt defect" --note x >/dev/null'
  scenario_script reviewer 'MESSAGE=found; cbugs add --kind spec --title "Second attempt gap" --note x >/dev/null'
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "bug #1 code First attempt defect"
  assert_output_contains "bug #2 spec Second attempt gap"
  local session one two
  session=$(cat "$(state_dir)/current")
  one=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" show 1 --json | jq -r '.revisions[0].review_pass')
  two=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" show 2 --json | jq -r '.revisions[0].review_pass')
  assert_eq "$one" "$session-review-1" "pass id of the first attempt"
  assert_eq "$two" "$session-review-1" "pass id of the second attempt"
}

# A bug that the pass created at a commit that HEAD does not reach is still
# in the report, with a mark.
test_pass_report_marks_a_hidden_bug() {
  git -C "$WORK" checkout -q -b side
  git -C "$WORK" commit -q --allow-empty -m "Side commit"
  git -C "$WORK" checkout -q main
  scenario_script reviewer 'MESSAGE=found; cbugs add --kind code --title "Side defect" --commit side --note x >/dev/null'
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_status 1
  assert_output_contains "bug #1 code Side defect (hidden at HEAD)"
}

# A failed read of the pass's bugs is not "no bug" (CV-OUT-18).
test_failed_bug_read_warns() {
  local db
  db="$(state_dir)/cbugs.db"
  scenario_script reviewer "MESSAGE=found; cbugs add --kind code --title Lost --note x >/dev/null; sqlite3 '$db' 'ALTER TABLE revision RENAME TO revision_away;'"
  scenario worker MESSAGE=work
  run_converge --foreground --no-coach --review-after 1 --max-iterations 1 docs/requirements.md
  assert_output_contains "cannot report the bugs this pass logged"
  assert_output_lacks "the review pass logged no bug"
}

# The loop reads the bug database only through cbugs.
test_converge_reads_no_database_directly() {
  assert_eq "$(grep -c sqlite3 "$CONVERGE")" 0 "sqlite3 mentions in bin/converge"
}
