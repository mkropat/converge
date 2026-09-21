-- Data model: cbugs
--
-- This file is the data model of the bug database that `bin/cbugs` keeps in
-- the state directory of a converge project. See docs/cbugs-requirements.md
-- for the behavior of the command.
--
-- The model is event sourced. A bug is a stable identifier and a kind. Every
-- other value of the bug lives in the revisions, and the newest revision of a
-- bug is the current state. Nothing is ever changed, and nothing is ever
-- removed. The history is therefore true by construction, and no stored value
-- can disagree with it.
--
-- The reviewed commits form a history of coverage. Multiple rows can name
-- one commit, and each row is immutable.

PRAGMA user_version = 6;

-- The identity of a defect.
--
-- The table holds only what cannot change. `kind` decides who acts: a worker
-- fixes a `code` bug and does a `task`, and the human user resolves a `spec`
-- bug, which is an ambiguity or a gap in the requirements documents. A `task`
-- is a punchlist item that a human user asked for. A defect whose kind was
-- wrong is a different defect. The caller dismisses the bug and logs a new one.
--
-- The one-column-and-a-kind table earns its place: it gives out an identifier
-- atomically. A command that computed the next id from the revisions could
-- give the same id to two callers that write at the same time.
CREATE TABLE bug (
  id   INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('code', 'spec', 'task'))
);

-- One assertion about a bug, by one role, at one commit.
--
-- Each revision carries the full state of the bug, and not only the part that
-- the caller changed. A caller that writes a revision copies the values of the
-- previous revision forward, and changes the ones it means to change. The
-- newest revision is therefore the truth, with nothing to fold and no null to
-- read as "unchanged".
--
-- The first revision of a bug is the report of the defect. A later revision
-- closes the bug, dismisses it, reopens it, corrects the title, or only adds a
-- note.
--
-- `commit_id` is the commit that the caller examined. It is the HEAD of the
-- repository, unless the caller names another commit. For a close, it is
-- therefore the commit that holds the fix.
--
-- `role` and `iteration` come from the environment that the loop exports. Both
-- are null when a person runs the command.
--
-- `panel_run` and `panel_profile` come from the same kind of contract, in the
-- environment of the agents that `bin/review-panel` starts. A run of that
-- command exports its own identity and the canonical profile of each agent,
-- so every revision an agent writes names the panel run it belongs to, and
-- the reviewer invocation that filed it. Both are null for every other
-- caller, and null values hold no meaning: the plain authorship rules of
-- `role` and `iteration` stand beside them unchanged.
CREATE TABLE revision (
  id            INTEGER PRIMARY KEY,
  bug_id        INTEGER NOT NULL REFERENCES bug (id),
  status        TEXT NOT NULL CHECK (status IN ('open', 'closed', 'wontfix')),
  title         TEXT NOT NULL CHECK (title <> ''),
  note          TEXT NOT NULL,
  role          TEXT,
  iteration     INTEGER,
  commit_id     TEXT,
  created_at    TEXT NOT NULL,
  panel_run     TEXT CHECK (panel_run <> ''),
  panel_profile TEXT CHECK (panel_profile <> '')
);

CREATE INDEX revision_bug ON revision (bug_id, id);

-- One reference from a revision to a documented requirement.
--
-- A revision has none, one, or many citations. The citation says which
-- requirement the revision speaks about: the reader of a bug goes from the
-- report to the requirement that the code must meet, without a search.
--
-- `path` is the path of a requirements document, as the caller wrote it. `req`
-- is an identifier inside that document, and is null when the caller cited the
-- whole document.
--
-- A citation is an assertion of one revision, and no other revision inherits
-- it. A revision that writes no citation cites nothing, and this is not a
-- retraction of an earlier one. The citations of a bug are therefore the
-- citations of all its revisions together.
CREATE TABLE citation (
  id          INTEGER PRIMARY KEY,
  revision_id INTEGER NOT NULL REFERENCES revision (id),
  path        TEXT NOT NULL CHECK (path <> ''),
  req         TEXT CHECK (req <> '')
);

CREATE INDEX citation_revision ON citation (revision_id, id);

-- The current state of each bug.
--
-- `created_at` is the time of the first revision. `updated_at` is the time of
-- the newest one, and `list` puts the newest first. There is no closed time:
-- the history says when a bug closed, by whom, and at which commit.
CREATE VIEW bug_current AS
SELECT
  b.id                                                              AS id,
  b.kind                                                            AS kind,
  r.status                                                          AS status,
  r.title                                                           AS title,
  r.id                                                              AS revision_id,
  (SELECT MIN(created_at) FROM revision WHERE bug_id = b.id)        AS created_at,
  r.created_at                                                      AS updated_at
FROM bug AS b
JOIN revision AS r
  ON r.id = (SELECT MAX(id) FROM revision WHERE bug_id = b.id);

-- One commit that a review pass covered.
--
-- The loop records one row for every commit that it gave to a review pass,
-- after the pass ends with success. The count of the commits that no row
-- names, and that HEAD reaches, tells the loop when the next pass runs. The
-- record lives here because it must survive the death of the loop: a pass
-- that a Ctrl-C kills records nothing, and the next run of the loop reviews
-- the same commits.
--
-- `commit_id` is the full hash that git resolves from the value that the
-- caller gave. A rebase or an amendment gives a commit a new hash, so work
-- that a pass covered before the change names no row after it, and the loop
-- reviews the new history.
--
-- `iteration` comes from `--iteration`, or is null when omitted. `profile`
-- comes from `--profile` as harness:model[:effort], or is null for unknown.
-- `created_at` is the completion time from `--completed-at`, or the call time.
-- The loop supplies the profile and the same completion time for a whole pass.
--
-- Nothing changes a row, and nothing removes one. A commit that the history
-- drops can come back, and a row that waits does no harm.
CREATE TABLE reviewed (
  id         INTEGER PRIMARY KEY,
  commit_id  TEXT NOT NULL,
  iteration  INTEGER,
  created_at TEXT NOT NULL,
  profile    TEXT CHECK (profile <> '')
);

CREATE INDEX reviewed_commit ON reviewed (commit_id);

-- Notes on the model
--
-- Times are ISO-8601 strings in UTC, to the second. SQLite compares them
-- correctly as text, and a person can read them.
--
-- An id counts from 1 and is never reused, because nothing deletes a row.
--
-- The order of the revisions of a bug is the order of their ids. A caller
-- writes the bug and its revision in one transaction.
--
-- A revision carries no name for what it did. A reader sees a close by the
-- change of the status, and a correction by the change of the title. The note
-- says the rest, in prose.
--
-- A file path is not a column. The caller names the path in the note, where it
-- writes the rest of the report. No query filters on a file. A citation is not
-- an exception: it names a requirements document, and not the code that holds
-- the defect.
--
-- `PRAGMA user_version` records the version of this model. A command that
-- meets a database of an earlier version migrates it to this version on first
-- use in one transaction. The step from version 2 to version 3 renames kind
-- `user` to `task`. Version 3 to version 4 adds the reviewed table. Version 4
-- to version 5 removes commit uniqueness and adds profile, preserving every
-- review id, hash, iteration, and timestamp, with null for each old profile.
-- Version 5 to version 6 adds the two panel columns of the revision table,
-- with null for each old revision. All steps preserve bugs, revisions, and
-- citations except the kind rename. Unsupported versions cause an error that
-- names both versions.
