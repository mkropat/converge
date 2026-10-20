# Help requests do not resolve or create project state (CB-DB-8.4).

test_search_help_after_text_does_not_create_state() {
  local output
  output=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" search query -h 2>&1) ||
    fail "cbugs search help failed"
  [[ $output == *'Usage: cbugs search'* ]] || fail "search help was not printed"
  [[ -z $(find "$XDG_STATE_HOME" -mindepth 1 -print -quit) ]] ||
    fail "search help created state"
}

test_search_help_as_first_argument_does_not_create_state() {
  local output
  output=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" search -h 2>&1) ||
    fail "cbugs search -h failed"
  [[ $output == *'Usage: cbugs search'* ]] || fail "search help was not printed"
  [[ -z $(find "$XDG_STATE_HOME" -mindepth 1 -print -quit) ]] ||
    fail "search help created state"
}
