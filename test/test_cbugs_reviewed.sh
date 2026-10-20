# The output of cbugs reviewed pending (CB-RVW-24 through CB-RVW-26).

# cbugs_run <arg...>   Runs bin/cbugs for $WORK. Sets STATUS and OUTPUT,
# with standard error in OUTPUT, as run_converge does.
cbugs_run() {
  OUTPUT=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" "$@" 2>&1 </dev/null)
  STATUS=$?
  printf '$ cbugs %s\n%s\n[exit %s]\n' "$*" "$OUTPUT" "$STATUS"
}

head_hash() {
  git -C "$WORK" rev-parse "${1:-HEAD}"
}

# A fresh database holds no record, and every relevant commit is pending.
test_json_on_a_fresh_database() {
  git -C "$WORK" commit -q --allow-empty -m 'Second "quoted" commit'
  cbugs_run reviewed pending --json
  assert_status 0
  assert_eq "$(jq -c . <<<"$OUTPUT")" \
    "{\"recorded\":0,\"commits\":[{\"commit_id\":\"$(head_hash)\",\"subject\":\"Second \\\"quoted\\\" commit\"},{\"commit_id\":\"$(head_hash HEAD~1)\",\"subject\":\"Add requirements\"}]}" \
    "the JSON object"
}

# recorded counts every record, also a second record of the same commit.
test_json_recorded_grows_with_each_record() {
  git -C "$WORK" commit -q --allow-empty -m "Second commit"
  CONVERGE_RUN_DIR=$WORK "$CBUGS" reviewed add HEAD~1 >/dev/null || fail "reviewed add failed"
  cbugs_run reviewed pending --json
  assert_status 0
  assert_eq "$(jq -c . <<<"$OUTPUT")" \
    "{\"recorded\":1,\"commits\":[{\"commit_id\":\"$(head_hash)\",\"subject\":\"Second commit\"}]}" \
    "the JSON object after one record"
  CONVERGE_RUN_DIR=$WORK "$CBUGS" reviewed add HEAD~1 >/dev/null || fail "reviewed add failed"
  cbugs_run reviewed pending --json
  assert_eq "$(jq -c .recorded <<<"$OUTPUT")" 2 "recorded after two records"
}

test_reviewed_add_records_all_profiles_in_one_call() {
  cbugs_run reviewed add --profile claude:a --profile codex:b HEAD
  assert_status 0
  local rows
  rows=$(sqlite3 "$(state_dir)/cbugs.db" 'SELECT profile FROM reviewed ORDER BY id;')
  assert_eq "$rows" $'claude:a\ncodex:b' "profiles in the atomic coverage write"
}

# With no pending commit, the JSON form still prints the object
# (CB-RVW-26.3), and the human form prints nothing (CB-RVW-24).
test_nothing_pending() {
  CONVERGE_RUN_DIR=$WORK "$CBUGS" reviewed add HEAD >/dev/null || fail "reviewed add failed"
  cbugs_run reviewed pending --json
  assert_status 0
  assert_eq "$(jq -c . <<<"$OUTPUT")" '{"recorded":1,"commits":[]}' "the JSON object"
  cbugs_run reviewed pending
  assert_status 0
  assert_eq "$OUTPUT" "" "the human output"
}

test_human_form_lists_hash_and_subject() {
  cbugs_run reviewed pending
  assert_status 0
  assert_eq "$OUTPUT" "$(head_hash) Add requirements" "the human output"
}

# A database error fails the call and prints no object (CB-RVW-26.5).
test_json_database_error_prints_no_object() {
  CONVERGE_RUN_DIR=$WORK "$CBUGS" reviewed pending >/dev/null || fail "first read failed"
  sqlite3 "$(state_dir)/cbugs.db" 'ALTER TABLE reviewed RENAME TO reviewed_away;'
  local out
  out=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" reviewed pending --json 2>/dev/null)
  STATUS=$?
  [[ $STATUS != 0 ]] || fail "the call exited 0 on a database error"
  assert_eq "$out" "" "standard output"
}
