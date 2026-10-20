# External citations keep URI syntax after the scheme separator (CB-CITE-13).

test_uri_ending_with_scheme_separator_is_accepted() {
  local uri='https://example.invalid/a://'
  CONVERGE_RUN_DIR=$WORK "$CBUGS" add --kind code --title URI --note test \
    --cite "$uri" >/dev/null || fail "cbugs rejected a valid URI citation"
  local output
  output=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" show 1 --json) || fail "cbugs show failed"
  assert_eq "$(jq -r '.revisions[0].citations[0].path' <<<"$output")" "$uri" "stored URI"
  assert_eq "$(jq -r '.revisions[0].citations[0].req' <<<"$output")" null "URI requirement id"
}

test_show_keeps_header_revisions_and_citations_in_one_snapshot() {
  CONVERGE_RUN_DIR=$WORK "$CBUGS" add --kind code --title Initial --note first \
    --cite docs/requirements.md:T-1 >/dev/null || fail "cbugs add failed"
  local output
  output=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" show 1 --json) || fail "cbugs show failed"
  assert_eq "$(jq -r '.current_revision' <<<"$output")" 1 "header current revision"
  assert_eq "$(jq -r '[.revisions[] | select(.current)] | length' <<<"$output")" 1 "current history row"
  assert_eq "$(jq -r '.revisions[0].citations[0].path' <<<"$output")" docs/requirements.md "revision citation"
}
