# State selection and creation follow CB-DB-7 and CB-DB-8.

test_nested_run_uses_nearest_ancestor_state() {
  local root_state child child_state output
  "$CONVERGE" --init-state >/dev/null
  root_state=$(state_dir)
  child="$WORK/nested/run"
  mkdir -p "$child"
  child_state=$(cd "$child" && "$CONVERGE" --state-dir)
  [[ ! -e $child_state ]] || fail "nested run state already exists"

  output=$(cd "$child" && "$CBUGS" add --kind code --title "Ancestor bug" --note x 2>&1) ||
    fail "cbugs add in nested run failed: $output"
  assert_eq "$output" 1 "bug id in ancestor database"
  [[ -e $root_state/cbugs.db ]] || fail "ancestor database was not used"
  [[ ! -e $child_state/cbugs.db ]] || fail "nested state was created despite ancestor state"

  output=$(CONVERGE_RUN_DIR="$child" "$CBUGS" list --json 2>&1) ||
    fail "cbugs list in nested run failed: $output"
  assert_eq "$(jq -r '.[0].title' <<<"$output")" "Ancestor bug" "ancestor bug visibility"
}

test_own_state_takes_precedence_over_ancestor_state() {
  local root_state child child_state output
  root_state=$(state_dir)
  child="$WORK/nested/run"
  mkdir -p "$child"
  child_state=$(cd "$child" && "$CONVERGE" --state-dir)
  mkdir -p "$child_state"
  CONVERGE_RUN_DIR="$child" "$CBUGS" add --kind code --title "Child bug" --note x \
    >/dev/null </dev/null || fail "cbugs add in nested run failed"
  [[ -e $child_state/cbugs.db ]] || fail "nested database was not used"
  [[ ! -e $root_state/cbugs.db ]] || fail "ancestor database was used instead of own state"
}

test_state_creation_failure_prints_no_bug() {
  local child fake_converge output
  child="$TEST_TMP/no-state-run"
  mkdir -p "$child"
  fake_converge="$TEST_TMP/bin/converge"
  cat >"$fake_converge" <<'EOF'
#!/usr/bin/env bash
echo "init denied" >&2
exit 7
EOF
  chmod +x "$fake_converge"
  output=$(cd "$child" && "$CBUGS" add --kind code --title "No bug" --note x 2>&1)
  local status=$?
  [[ $status != 0 ]] || fail "cbugs add succeeded after state creation failed"
  [[ $output == *"cannot create the state directory"* && $output == *"init denied"* ]] ||
    fail "state creation failure did not name its cause: $output"
  [[ $output != 1 ]] || fail "cbugs printed a bug id after state creation failed"
  [[ -z $(find "$XDG_STATE_HOME" -mindepth 1 -print -quit) ]] ||
    fail "failed state creation left state behind"
}
