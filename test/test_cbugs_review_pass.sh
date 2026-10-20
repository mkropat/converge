# The review pass of a revision (CB-REV-12, CB-PROV-9), its list and search
# filters (CB-LIST-10, CB-SEARCH-7), its show fields (CB-SHOW-8), and the
# migration that adds it (CB-MIG-17).

# cbugs_run <arg...>   Runs bin/cbugs for $WORK. Sets STATUS and OUTPUT,
# with standard error in OUTPUT, as run_converge does.
cbugs_run() {
  OUTPUT=$(CONVERGE_RUN_DIR=$WORK "$CBUGS" "$@" 2>&1 </dev/null)
  STATUS=$?
  printf '$ cbugs %s\n%s\n[exit %s]\n' "$*" "$OUTPUT" "$STATUS"
}

# add_bug <title> [pass]   Logs one code bug, with CONVERGE_REVIEW_PASS set
# to the pass when one is given. Prints the id.
add_bug() {
  CONVERGE_RUN_DIR=$WORK CONVERGE_REVIEW_PASS=${2:-} \
    "$CBUGS" add --kind code --title "$1" --note x </dev/null ||
    fail "cbugs add '$1' failed"
}

test_revision_stores_the_review_pass() {
  add_bug "Tagged" pass-1 >/dev/null
  add_bug "Plain" >/dev/null
  cbugs_run show 1 --json
  assert_status 0
  assert_eq "$(jq -r '.revisions[0].review_pass' <<<"$OUTPUT")" pass-1 "review pass of bug 1"
  cbugs_run show 2 --json
  assert_eq "$(jq -r '.revisions[0] | has("review_pass") and .review_pass == null' <<<"$OUTPUT")" true \
    "review pass of bug 2"
  cbugs_run show 1
  assert_output_contains "review pass pass-1"
}

# The filter selects the bugs that the pass created, and not a bug that the
# pass only changed with a note.
test_list_review_pass_selects_created_bugs() {
  add_bug "Old bug" >/dev/null
  add_bug "Other pass" pass-0 >/dev/null
  add_bug "First find" pass-1 >/dev/null
  add_bug "Second find" pass-1 >/dev/null
  CONVERGE_RUN_DIR=$WORK CONVERGE_REVIEW_PASS=pass-1 "$CBUGS" note 1 "seen again" >/dev/null ||
    fail "cbugs note failed"
  cbugs_run list --review-pass pass-1 --json
  assert_status 0
  assert_eq "$(jq -c '[.[].id] | sort' <<<"$OUTPUT")" "[3,4]" "bugs of pass-1"
  cbugs_run list --review-pass=pass-0 --json
  assert_eq "$(jq -c '[.[].id]' <<<"$OUTPUT")" "[2]" "bugs of pass-0"
  cbugs_run list --review-pass pass-9 --json
  assert_status 0
  assert_eq "$OUTPUT" "" "bugs of an unknown pass"
  cbugs_run search find --review-pass pass-1 --json
  assert_status 0
  assert_eq "$(jq -c '[.[].id] | sort' <<<"$OUTPUT")" "[3,4]" "search within pass-1"
  cbugs_run search bug --review-pass pass-1 --json
  assert_eq "$OUTPUT" "" "search for a noted bug within pass-1"
}

# A bug that the pass created at a commit that HEAD no longer reaches stays
# in the selection, with the hidden mark (CB-LIST-10.1).
test_list_review_pass_includes_hidden_bugs() {
  git -C "$WORK" checkout -q -b side
  git -C "$WORK" commit -q --allow-empty -m "Side commit"
  add_bug "Side find" pass-1 >/dev/null
  git -C "$WORK" checkout -q main
  add_bug "Main find" pass-1 >/dev/null
  cbugs_run list --json
  assert_eq "$(jq -c '[.[].id]' <<<"$OUTPUT")" "[2]" "visible bugs"
  cbugs_run list --review-pass pass-1 --json
  assert_status 0
  assert_eq "$(jq -c 'map({id, hidden: (.hidden == true or .hidden == 1)}) | sort_by(.id)' <<<"$OUTPUT")" \
    '[{"id":1,"hidden":true},{"id":2,"hidden":false}]' "bugs of pass-1"
  cbugs_run list --review-pass pass-1 --visibility hidden --json
  assert_eq "$(jq -c '[.[].id]' <<<"$OUTPUT")" "[1]" "hidden bugs of pass-1"
  cbugs_run list --review-pass pass-1
  [[ $(grep -c hidden <<<"$OUTPUT") == 1 ]] || fail "the human form does not mark one hidden bug"
}

test_empty_review_pass_is_rejected() {
  add_bug "Tagged" pass-1 >/dev/null
  cbugs_run list --review-pass ""
  [[ $STATUS != 0 ]] || fail "list accepted an empty review pass"
  assert_output_contains "--review-pass must name a review pass id"
  cbugs_run list --review-pass=
  [[ $STATUS != 0 ]] || fail "list accepted an empty review pass in the = form"
  cbugs_run search Tagged --review-pass ""
  [[ $STATUS != 0 ]] || fail "search accepted an empty review pass"
}

# An empty CONVERGE_REVIEW_PASS counts as an absent one (CB-PROV-9).
test_empty_environment_value_records_no_pass() {
  CONVERGE_RUN_DIR=$WORK CONVERGE_REVIEW_PASS= "$CBUGS" add --kind code --title T --note x \
    >/dev/null </dev/null || fail "cbugs add failed"
  cbugs_run show 1 --json
  assert_eq "$(jq -r '.revisions[0].review_pass' <<<"$OUTPUT")" null "review pass"
}

# A version 8 database gains the column, keeps every stored value, and
# gives each old revision a null review pass (CB-MIG-17, CB-MIG-18).
test_migration_from_version_8() {
  local db
  db="$(state_dir)/cbugs.db"
  mkdir -p "${db%/*}"
  sqlite3 "$db" <<'SQL' || fail "cannot create the version 8 database"
CREATE TABLE bug (id INTEGER PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('code', 'spec', 'task')));
CREATE TABLE revision (
  id INTEGER PRIMARY KEY, bug_id INTEGER NOT NULL REFERENCES bug (id),
  status TEXT NOT NULL CHECK (status IN ('open', 'closed', 'wontfix')),
  title TEXT NOT NULL CHECK (title <> ''), note TEXT NOT NULL, role TEXT,
  iteration INTEGER, commit_id TEXT, created_at TEXT NOT NULL,
  panel_run TEXT CHECK (panel_run <> ''), panel_profile TEXT CHECK (panel_profile <> ''),
  panel_invocation TEXT CHECK (panel_invocation <> ''));
CREATE INDEX revision_bug ON revision (bug_id, id);
CREATE TABLE citation (id INTEGER PRIMARY KEY, revision_id INTEGER NOT NULL REFERENCES revision (id),
  path TEXT NOT NULL CHECK (path <> ''), req TEXT CHECK (req <> ''));
CREATE INDEX citation_revision ON citation (revision_id, id);
CREATE TABLE reviewed (id INTEGER PRIMARY KEY, commit_id TEXT NOT NULL, iteration INTEGER,
  created_at TEXT NOT NULL, profile TEXT CHECK (profile <> ''));
CREATE INDEX reviewed_commit ON reviewed (commit_id);
INSERT INTO bug VALUES (1, 'code'), (2, 'spec');
INSERT INTO revision VALUES
  (1, 1, 'open', 'Old code bug', 'n1', 'reviewer', 3, NULL, '2026-01-01T00:00:00Z', 'run-a', 'claude:opus', 'inv-1'),
  (2, 2, 'open', 'Old spec bug', 'n2', NULL, NULL, NULL, '2026-01-02T00:00:00Z', NULL, NULL, NULL),
  (3, 1, 'closed', 'Old code bug', 'fixed', 'worker', 4, NULL, '2026-01-03T00:00:00Z', NULL, NULL, NULL);
INSERT INTO citation VALUES (1, 1, 'docs/requirements.md', 'T-1');
INSERT INTO reviewed VALUES (1, 'abc', 2, '2026-01-01T00:00:00Z', 'claude:opus');
PRAGMA user_version = 8;
SQL
  local before after
  before=$(sqlite3 "$db" "SELECT * FROM bug; SELECT * FROM revision; SELECT * FROM citation; SELECT * FROM reviewed;")
  cbugs_run list --json
  assert_status 0
  assert_eq "$(sqlite3 "$db" 'PRAGMA user_version;')" 9 "version after migration"
  after=$(sqlite3 "$db" "SELECT * FROM bug;
    SELECT id, bug_id, status, title, note, role, iteration, commit_id, created_at, panel_run, panel_profile, panel_invocation FROM revision;
    SELECT * FROM citation; SELECT * FROM reviewed;")
  assert_eq "$after" "$before" "stored values after migration"
  assert_eq "$(sqlite3 "$db" 'SELECT count(*) FROM revision WHERE review_pass IS NULL;')" 3 \
    "old revisions with a null review pass"
  CONVERGE_RUN_DIR=$WORK CONVERGE_REVIEW_PASS=pass-1 "$CBUGS" add --kind code --title New --note x \
    >/dev/null </dev/null || fail "cbugs add after migration failed"
  cbugs_run list --review-pass pass-1 --json
  assert_eq "$(jq -c '[.[].id]' <<<"$OUTPUT")" "[3]" "bugs of pass-1 after migration"
}
