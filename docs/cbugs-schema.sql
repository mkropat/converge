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

PRAGMA user_version = 3;

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
CREATE TABLE revision (
  id         INTEGER PRIMARY KEY,
  bug_id     INTEGER NOT NULL REFERENCES bug (id),
  status     TEXT NOT NULL CHECK (status IN ('open', 'closed', 'wontfix')),
  title      TEXT NOT NULL CHECK (title <> ''),
  note       TEXT NOT NULL,
  role       TEXT,
  iteration  INTEGER,
  commit_id  TEXT,
  created_at TEXT NOT NULL
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
-- meets a database of version 2 migrates it to this version on first use: it
-- renames every kind `user` to `task`, in one transaction, and changes nothing
-- else. A command that meets a database of any other version stops with an
-- error that names the version of the database and the current version.
