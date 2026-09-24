# Requirements: cbugs

`bin/cbugs` is a bug tracker for one run directory of a converge project. It
gives query and CRUD operations on a database in the state directory of that
run directory.

This document gives the required behavior only. It does not give an
implementation plan. `docs/cbugs-schema.sql` gives the data model.

## Requirement identifiers

Each requirement in this document has an identifier. A citation names it, as
`docs/cbugs-requirements.md:CB-CITE-6`.

- An identifier has the form `CB-<SECTION>-<number>`. `CB` names this document.
  `<SECTION>` names the section. The number counts the requirements of that
  section, from 1.
- A requirement that holds a list of parts numbers each part after a dot, as
  `CB-LIST-2.1`. A citation can name the whole requirement or one part.
- An identifier never changes its meaning. A requirement that this document
  removes leaves its identifier unused. A new requirement takes the next free
  number of its section.
- The "Terms" section defines words. It holds no requirement, and therefore no
  identifier.

These are the section codes.

| Code | Section |
| --- | --- |
| `PRIN` | Design principles |
| `KIND` | Kinds of bug |
| `TASK` | Who logs a task |
| `INV` | Invocation |
| `PLAT` | Platform |
| `DB` | The database |
| `MIG` | Migration |
| `BUG` | Bugs |
| `REV` | Revisions |
| `CITE` | Citations |
| `PROV` | Provenance |
| `RVW` | Reviewed commits |
| `SUM` | The summary |
| `WRITE` | Options that every verb that writes a revision accepts |
| `ADD` | add |
| `NOTE` | note |
| `CLOSE` | close |
| `DISMISS` | dismiss |
| `REOPEN` | reopen |
| `LIST` | list |
| `SHOW` | show |
| `SEARCH` | search |
| `STAT` | Status changes |
| `DUP` | Duplicates |
| `OUT` | Output |
| `ERR` | Errors |
| `CONC` | Concurrency |
| `OOS` | Out of scope |

The identifiers `CB-USER-1` through `CB-USER-3` are unused. `CB-TASK-1` through
`CB-TASK-3` replace them. The identifier `CB-OOS-21` is unused. `CB-MIG-1`
through `CB-MIG-6` replace it.

## Terms

- **Project**: the repository that the operator works on with `converge`. A
  project holds one or more run directories.
- **Run directory**: the directory that a run of `converge` works from, as
  `docs/converge-requirements.md` defines it. One run directory has one bug
  database.
- **Bug**: one defect. A bug has an identifier and a kind, and nothing else
  that cannot change.
- **Kind**: `code`, `spec`, or `task`. See "Kinds of bug".
- **Revision**: one assertion about a bug, by one role, at one commit. A
  revision carries the full state of the bug and a note.
- **Citation**: a reference from a revision to a documented requirement. It
  names a requirements document, and can also name an identifier inside it.
- **Reviewed commit**: a commit of the repository that the table of reviewed
  commits names. The loop records one after a review pass, as
  `docs/converge-requirements.md` gives.
- **Relevant commit**: a commit that git reaches from the repository HEAD and
  that changes one or more paths in the run directory. Every reachable commit
  is relevant when the run directory is the repository root.
- **Unreviewed commit**: a relevant commit that the table of reviewed commits
  does not name.
- **Human user**: the person who runs the project. An agent is not a human
  user.
- **Caller**: the loop, an agent, or the operator that runs the command.
- **State directory**: the durable directory of one run directory, as
  `docs/converge-requirements.md` defines it.

## Purpose

`converge` runs agent roles that must pass information about defects from one
iteration to the next. The guidance file carries process guidance from the
coach. It is the wrong channel for a specific defect, because the coach rewrites
it on each run and keeps it short.

`cbugs` is that second channel. It holds a durable, queryable list of defects
that survives the loss of memory between iterations.

The database holds one more record: the reviewed commits. A review pass of
`converge` covers the commits that no earlier pass recorded, and the loop
reads that record to learn when a pass must run. The record must survive the
death of the loop, so it lives beside the bugs.

This document specifies the command. The roles that use it, the prompts that
instruct them, and the order in which a worker takes up work, belong to
`docs/converge-requirements.md`.

## Design principles

Apply these when a requirement is ambiguous.

- **CB-PRIN-1**: The primary caller is an agent with no memory of prior
  iterations. Every command must be easy to call correctly on the first attempt,
  and its output must be easy to read without a parser.
- **CB-PRIN-2**: The history is the record. The command adds revisions. It never
  changes a revision, and it never removes one. The current state of a bug is the
  newest revision of that bug, so no stored value can disagree with the history.
- **CB-PRIN-3**: A defect and an assertion about a defect are different things.
  The bug holds the identity. A revision holds what a role said, when, and at
  which commit.
- **CB-PRIN-4**: Prefer too little process over too much. Add a field or a verb
  only when a role needs it to do its work.
- **CB-PRIN-5**: The command holds no policy. It does not judge which bug
  matters, and it does not stop a loop. The prompts hold the policy.

## Kinds of bug

There are three kinds, and the difference decides who acts.

- **CB-KIND-1**: A **code bug** is a defect in the project code. A worker fixes
  it.
- **CB-KIND-2**: A **spec bug** is an ambiguity, a gap, or a contradiction in
  the requirements documents. The human user resolves it. No agent works on a
  spec bug, and no agent waits for one.
- **CB-KIND-3**: A **task** is a punchlist item that a human user asked for.
  A worker does it. It is usually not a violation of a requirement, but a tweak
  that the requirements permit. A task must not contradict a requirements
  document: a later worker that reads the document would undo the change.
- **CB-KIND-4**: The command must treat the three kinds the same way in every
  operation, with one exception: `add --kind task`. See "Who logs a task".
  Only the value of the field differs.
- **CB-KIND-5**: The kind must not change. It is the one fact that decides who
  acts, so a bug whose kind was wrong is a different bug. The caller dismisses
  the bug, logs a new one of the right kind, and names the other bug in both
  notes.

### Who logs a task

A task records what a human user asked for. An agent that logs one invents
work that no person requested, and a worker then does it.

- **CB-TASK-1**: `add --kind task` must stop with an error when the environment
  holds `CONVERGE_ROLE`. An agent that the loop starts therefore cannot log a
  task, whatever a prompt tells it. The error must say that a task records a
  request from a human user, and must name the role that it read.
- **CB-TASK-2**: The command must apply this test to `add` only. A worker must
  be able to note, close, dismiss, and reopen a task, because a worker does
  the work that the task names.
- **CB-TASK-3**: The help text of `add` must say that an agent must never log a
  task unless a human user directed it. The prompts must say the same. See
  `docs/converge-requirements.md`.

## Invocation

- **CB-INV-1**: The command must live at `bin/cbugs`.
- **CB-INV-2**: The command must operate on the run directory of the call: the
  current working directory, or the value of `CONVERGE_RUN_DIR` when the
  environment holds it.
- **CB-INV-3**: The first argument must be a verb, or the id of a bug. The verbs
  are `add`, `list`, `show`, `search`, `note`, `close`, `dismiss`, `reopen`,
  `reviewed add`, and `reviewed pending`.
- **CB-INV-4**: A first argument that is a whole number is the id of a bug.
  `cbugs <id>` must do what `cbugs show <id>` does, with the same options and
  the same output. A reader that saw an id in a listing therefore types the id
  alone.
- **CB-INV-5**: No verb is a whole number, so the two forms never disagree.
- **CB-INV-6**: `cbugs` with no argument must print the summary. See "The
  summary". It must not print the help text.
- **CB-INV-7**: `cbugs --help` must list the verbs. `cbugs <verb> --help` must
  give the options of that verb.
- **CB-INV-8**: Every verb must accept `--json`. See "Output".
- **CB-INV-9**: The command must take no option that names a run directory. The
  current directory, or the environment of an agent of the loop, names the run
  directory.

## Platform

- **CB-PLAT-1**: The command must run on Linux and on macOS, under the same
  conditions as `converge`.
- **CB-PLAT-2**: The command must stop with an error when a necessary tool is
  absent. The error must name the Homebrew formula that supplies the tool on
  macOS.

## The database

- **CB-DB-1**: The database must be a SQLite database in the state directory of
  the run directory. One run directory has one bug database, and two run
  directories of one project share no bug.
- **CB-DB-2**: The command must derive the state directory from the absolute
  path of the run directory of the call, by the same rule that `converge`
  uses. The current working directory names the run directory, and
  `CONVERGE_RUN_DIR` names it in place of the current directory when the
  environment holds it. The loop exports that variable for every agent, so an
  agent that changes its working directory still reads and writes the bugs of
  its own run, and never the bugs of another run directory that it moved into.
  A directory that `converge` has run in must give the same state directory to
  both commands.
- **CB-DB-3**: Retired. The command stopped with an error when the state
  directory did not exist, and told the operator to run `converge` first.
  **CB-DB-7** and **CB-DB-8** replace this behavior: the command now uses the
  state directory of an ancestor when the run directory has none, and creates
  the state directory when the whole chain has none. The change removes the
  state directory from the failures of CB-ERR-3.
- **CB-DB-4**: The command must create the database on first use, inside a state
  directory that exists.
- **CB-DB-5**: The command must never write into the repository.
- **CB-DB-6**: Retired. The command looked for no state directory of a parent
  of the run directory, and the caller that wanted the bugs of a run directory
  changed its working directory to it. **CB-DB-8** replaces this behavior with
  the walk over the parent chain.
- **CB-DB-7**: When no state directory exists for the run directory of the
  call, or for an ancestor that the walk of CB-DB-8 tests, the command must
  create the state directory for the run directory before it answers the call.
  The creation happens for every verb, and a read creates the state directory
  in the same way as a write.
  - **CB-DB-7.1**: The command must create no state directory with operations
    of its own. It must run `converge --init-state` with the working directory
    of the child set to the run directory of the call, and `converge` must be
    the command that PATH names. One tool therefore makes the directories, and
    not two.
  - **CB-DB-7.2**: The command must discard the output of a creation that
    succeeds. When the creation fails, the command must stop with an error
    that names the cause, and must print no bug.
- **CB-DB-8**: When the state directory does not exist for the run directory
  of the call, the command must find the nearest ancestor that holds a state
  directory, and must use that state directory in place of one for the run
  directory.
  - **CB-DB-8.1**: The command must derive the state directory of each
    ancestor of the run directory, by the rule that CB-DB-2 gives, from the
    parent of the run directory upward. The first ancestor whose state
    directory exists gives the state directory of the call.
  - **CB-DB-8.2**: When the run directory is in a repository, the walk must
    end with the root of the repository, and the command must test no ancestor
    above it. When the run directory is not in a repository, the walk must end
    with the root of the file system. A state directory of another repository
    must therefore never take the bugs of this one.
  - **CB-DB-8.3**: A call in a run directory without a state directory of its
    own writes its bugs into the database of the state directory that the walk
    finds. This is the one case in which two run directories share a bug
    database, and CB-DB-1 holds in every other case. A later run of `converge`
    in the same run directory creates its own state directory, and reads no
    bug from the state directory that the walk found.
  - **CB-DB-8.4**: The command must resolve no state directory, and must
    create none, for a call that asks for the help text. `cbugs --help` and
    `cbugs <verb> --help` must therefore work in any directory.

## Migration

A database of an earlier version is a record, not a dead file. The command
migrates it, and the history carries over.

- **CB-MIG-1**: Retired. CB-MIG-9 replaces the version 4 requirement.
- **CB-MIG-2**: The command knows how to migrate version 2. When a call finds a
  database of version 2, the command must migrate the database to the current
  version before it answers the call, whatever the verb. A read migrates the
  database in the same way as a write.
- **CB-MIG-3**: The migration from version 2 to version 3 renames the kind
  `user` to `task`, and nothing else. Every bug id, every revision, and every
  citation must be the same after the migration as before it. After it, the
  database answers as if the kind had always been `task`.
- **CB-MIG-4**: The migration must be one transaction. A migration that fails
  must leave the database as it was. The command prints the error, changes
  nothing, and the next call tries again.
- **CB-MIG-5**: Two callers that find the same old database at the same time
  must end with one migrated database. The rules of "Concurrency" govern the
  migration: the second caller waits, finds the current version, and goes on.
- **CB-MIG-6**: When a call finds a database of a version that the command does
  not know, the command must stop with an error that names the version of the
  database and the current version. The error must not tell the operator to
  delete the file.
- **CB-MIG-7**: The command knows how to migrate version 3. When a call finds
  a database of version 3, the command must migrate the database to the
  current version before it answers the call, whatever the verb, in the way
  that CB-MIG-2 gives for version 2.
- **CB-MIG-8**: The migration from version 3 to version 4 creates the table of
  reviewed commits, and nothing else. Every bug, every revision, and every
  citation must be the same after the migration as before it.

- **CB-MIG-9**: The database must record the version of its model in `PRAGMA
  user_version`. The current version is 5.
- **CB-MIG-10**: The command must migrate version 4 to the current version
  before it answers any verb. The supported paths from versions 2 and 3 must
  remain available, as CB-MIG-2 and CB-MIG-7 require.
- **CB-MIG-11**: The migration from version 4 to version 5 must allow multiple
  review records per commit and add the optional profile. It must preserve
  every existing review id, full commit hash, iteration, and timestamp without
  change. Each existing record must have a NULL profile, which means unknown.
  Every bug, revision, and citation must remain unchanged. The transaction and
  concurrency rules of CB-MIG-4 and CB-MIG-5 apply.

## Bugs

A bug holds these values, and no more.

- **CB-BUG-1**: **Id**: a small integer, unique in the bug database, that counts
  from 1. The operator and the agent name a bug by this integer. An agent can
  cite it in a commit message.
- **CB-BUG-2**: **Kind**: `code`, `spec`, or `task`. It never changes.

## Revisions

A bug carries one or more revisions, in the order that callers wrote them.

- **CB-REV-1**: A revision holds these values.
  - **CB-REV-1.1**: **Status**: `open`, `closed`, or `wontfix`.
  - **CB-REV-1.2**: **Title**: one line that names the defect.
  - **CB-REV-1.3**: **Note**: what the caller saw or did. It can hold many
    lines, and it can be empty.
  - **CB-REV-1.4**: **Role**: the role of the caller.
  - **CB-REV-1.5**: **Iteration**: the worker iteration number.
  - **CB-REV-1.6**: **Commit**: the commit that the caller examined.
  - **CB-REV-1.7**: **Citations**: none, one, or many references to a documented
    requirement.
  - **CB-REV-1.8**: **Created time**.

These rules govern every revision.

- **CB-REV-2**: The newest revision of a bug gives the current status and the
  current title.
- **CB-REV-3**: Each revision carries the full state, and not only the part that
  the caller changed. A verb that writes a revision must copy the status and the
  title of the previous revision forward, and must change only what the caller
  asked it to change.
- **CB-REV-4**: The citations are the one value that a revision does not copy
  forward. They are what this caller cited, and a revision with no citation
  cites nothing. See "Citations".
- **CB-REV-5**: The first revision of a bug reports the defect. `add` writes the
  bug and that revision together.
- **CB-REV-6**: Every role writes revisions. The reviewer writes one when it logs
  a defect. The worker writes one when it closes a defect, and the commit of that
  revision is the commit that holds the fix. The coach and the operator write one
  when they comment.
- **CB-REV-7**: The created time of the first revision is the time the bug was
  logged. The created time of the newest revision is the time the bug last
  changed.
- **CB-REV-8**: A revision does not name what it did. A reader sees a close by
  the change of the status, and a correction by the change of the title. The note
  says the rest, in prose.

## Citations

A citation points from a revision to the requirement that the revision speaks
about. A reader of a bug goes from the report to the requirement that the code
must meet, and does not search the documents for it. The option is also a
reminder: a role that must name the requirement thinks about which requirement
it means.

- **CB-CITE-1**: A citation holds a **path** to a requirements document, and an
  optional **requirement identifier** inside that document.
- **CB-CITE-2**: Every verb that writes a revision must accept
  `--cite <path>[:<id>]`. The colon separates the path from the identifier. The
  last colon of the value is the separator. With no colon, the citation names the
  whole document.
- **CB-CITE-3**: The option must be repeatable. One revision can cite many
  requirements.
- **CB-CITE-4**: The command must store the path as the caller wrote it, and
  must store the identifier as the caller wrote it.
- **CB-CITE-5**: The command must record two identical citations of one call
  once.
- **CB-CITE-6**: A citation belongs to the revision that wrote it. No revision
  inherits the citations of the previous one, and a revision with no `--cite`
  option retracts nothing. The citations of a bug are the citations of all its
  revisions together.
- **CB-CITE-7**: The command must stop with an error when the path names no file
  at the time of the call, and must write nothing. This catches a path that an
  agent invented. The command must not test the path again later: a document that
  a later commit renames leaves a citation that a reader can still understand.
- **CB-CITE-8**: The command must stop with an error when the value gives an
  empty path, or a colon with an empty identifier after it.
- **CB-CITE-9**: The command must not read the document, and must accept any
  identifier. Documents write their identifiers in different ways, and the
  command holds no policy about them.

## Provenance

- **CB-PROV-1**: The loop must export the role and the iteration number into the
  environment of each agent that it starts. The variables are `CONVERGE_ROLE` and
  `CONVERGE_ITERATION`.
- **CB-PROV-2**: The command must read the role and the iteration from the
  environment. The caller gives no option for them, and therefore cannot get them
  wrong.
- **CB-PROV-3**: When a variable is absent, the command must record no value for
  it and must continue. An operator who runs the command by hand gets a revision
  with no role and no iteration.
- **CB-PROV-4**: The command must read the commit from the repository. The commit
  is the HEAD of the repository at the time of the call.
- **CB-PROV-5**: When the repository has no commit, the command must record no
  commit and must continue.

## Reviewed commits

The database holds review history beside the bugs. Each record names one
commit that a review pass covered. More than one record can name the same
commit. The loop records the coverage, and no agent records it. See the review
sections of `docs/converge-requirements.md` for the loop behavior.

- **CB-RVW-1**: The database must hold one table of reviewed commits. One row
  names one commit of the repository. The command must write the full hash of
  the commit that git resolves from the value that the caller gave.
- **CB-RVW-2**: Retired. CB-RVW-11 replaces the review fields requirement.
- **CB-RVW-3**: Retired. CB-RVW-12 replaces the single-record requirement.
- **CB-RVW-4**: The command must never change a row of reviewed commits, and
  must never remove one. A commit that the history drops can come back, and a
  row that waits does no harm.
- **CB-RVW-5**: The command must offer the verbs `reviewed add` and `reviewed
  pending`. `cbugs reviewed`, with no second word, must stop with an error
  that names the two verbs.
- **CB-RVW-6**: Retired. CB-RVW-13 and CB-RVW-17 replace the write and output
  requirements.
- **CB-RVW-7**: `reviewed add` must stop with an error when the environment
  holds `CONVERGE_ROLE`. The loop records the commits of a pass, and no agent
  of the loop records one. The error must name the role that the call read.
  An operator who runs the command by hand may record commits. The command
  must apply this test to `reviewed add` only: `reviewed pending` changes
  nothing, and every caller may run it.
- **CB-RVW-8**: `cbugs reviewed pending` must print the unreviewed commits, the
  newest first. The command must use the run directory to select relevant
  commits from the history that the repository HEAD reaches. A commit is
  relevant when it changes one or more paths in the run directory. Every
  reachable commit is relevant when the run directory is the repository root.
  The command must consider only the 1,000 newest relevant commits. It must
  ignore all older commits, whether or not a review record exists for them.
  This limit applies before the command selects the unreviewed commits. The
  command must read the repository at the time of the call. When the considered
  history holds no relevant commit, and when no considered commit is
  unreviewed, the command must print nothing and exit with the status 0.
- **CB-RVW-9**: The human form of `reviewed pending` must give one line for
  each commit, with the hash and the subject of the commit. The `--json` form
  must give the same information as JSON.
- **CB-RVW-10**: The command must stop with an error when a value that
  `reviewed add` names does not name a commit of the repository. The command
  reads the repository for these verbs as it reads HEAD for the provenance of
  a revision, as CB-PROV-4 gives.

- **CB-RVW-11**: Each review record must hold a full commit hash, the worker
  iteration that the pass followed, a completion timestamp in `created_at`,
  and an optional profile string. The iteration comes from `--iteration`, not
  the environment. An omitted iteration records NULL. The record has an id
  that is unique in the table. It holds no named profile ID.
- **CB-RVW-12**: Each successful `reviewed add` call must append one immutable
  record per distinct resolved commit in that call. Repeated arguments that
  resolve to the same commit produce one record in that call. A later call
  must append a new record even when all its values match an existing record.
  The commit hash must not be unique in the table. CB-RVW-4 still applies.
- **CB-RVW-13**: `cbugs reviewed add` must accept commits as arguments or on
  standard input, one commit per line. One call must be one transaction. A
  failed call must record nothing. A call with no commit must fail.
- **CB-RVW-14**: `reviewed add` must accept optional `--profile <profile>`.
  It must accept only one profile, not a list or repeated `--profile` options.
  An omitted option must store SQL NULL, which means unknown. A supplied value
  must use `harness:model[:effort]`. The harness must be `claude` or `opencode`.
  Each supplied field must be nonempty and contain no colon, comma, or
  whitespace. A slash is allowed in a field. The optional effort is a value
  native to the selected harness, not a shared scale. The command must store
  the supplied canonical string without substitution of a named profile ID.
  An invalid profile must fail before any record is written.
- **CB-RVW-15**: `reviewed add` must accept optional
  `--completed-at <timestamp>`. The value must be a valid UTC date and time in
  `YYYY-MM-DDTHH:MM:SSZ` form. An invalid value must fail before any record is
  written. The command must store the supplied value unchanged in `created_at`.
  Without the option, it must use the current UTC time, to the second, once
  for the whole call. Every record of the call must use that same timestamp.
- **CB-RVW-16**: After a successful review pass, the loop must supply its
  profile through `--profile` and its completion time through `--completed-at`.
  Every commit covered by that pass must receive the same completion timestamp,
  even if the loop needs more than one call. A failed pass must record nothing.
  These fields describe commit coverage. They must not create a separate pass
  table or a finding record. See the review sections of
  `docs/converge-requirements.md`.
- **CB-RVW-17**: The human output of `reviewed add` must remain one summary
  line. It must give the number of records added, the number of distinct input
  commits that had any record before the call, the profile, and the completion
  timestamp. It must show an absent profile as `unknown`. The JSON output must
  remain one object with `added` and `already` counts and add `profile` and
  `created_at` fields. `added` counts all new records, including repeated
  reviews. `already` counts input commits with prior coverage, not skipped
  writes. An unknown profile must be JSON null. `created_at` must be the stored
  timestamp. `reviewed pending` keeps the output of CB-RVW-9; pending commits
  have no review metadata.
- **CB-RVW-18**: For CB-RVW-8, any review record is sufficient coverage.
  Existing migrated records and manual records with an unknown profile count.
  The command must not require a number of reviews or a particular profile
  before it removes a commit from the pending result.

## The summary

`cbugs` with no argument prints what the caller most probably wants: the open
bugs. A caller that runs the command with no argument does not know what to do
next, and the help text does not tell it which bugs are open.

- **CB-SUM-1**: The summary must print the ten open bugs whose newest revision
  is the newest, in that order. It must show every kind.
- **CB-SUM-2**: Each bug must use the same line form as `list`, so that the two
  listings read the same way.
- **CB-SUM-3**: After the bugs, the summary must print a footer of at most three
  lines. The footer must name the other verbs and must point to `cbugs --help`.
  The bugs are the point of the output, so the footer must stay short.
- **CB-SUM-4**: When more than ten bugs are open, the footer must give the number
  of open bugs that the summary did not show, and must name the command that
  shows them all.
- **CB-SUM-5**: When no bug is open, the summary must print one line that says
  so, and must then print the footer.
- **CB-SUM-6**: The summary must exit with the status 0.
- **CB-SUM-7**: The summary takes no option, and it has no `--json` form. It is
  for a person who is looking around. An agent that wants a listing runs `list`.

## Verbs

### Options that every verb that writes a revision accepts

`add`, `note`, `close`, `dismiss`, and `reopen` write a revision.

- **CB-WRITE-1**: Each one must accept these options.
  - **CB-WRITE-1.1**: `--note <text>`: the note of the revision.
  - **CB-WRITE-1.2**: `--cite <path>[:<id>]`: a citation of the revision. It is
    repeatable. See "Citations".
  - **CB-WRITE-1.3**: `--title <text>`: a new title. Without it, the revision
    keeps the title of the previous revision. This lets a worker correct the
    wording of a defect it understands better, in the same call as the note it
    was already writing.
  - **CB-WRITE-1.4**: `--commit <id>`: the commit, in place of HEAD.
- **CB-WRITE-2**: When `--note` is absent, the command must read the note from
  standard input. This lets an agent give a long report with a here-document, and
  it avoids a shell quoting problem.
- **CB-WRITE-3**: When `--note` is absent and standard input is a terminal, `add`
  and `note` must stop with an error. They must not wait for input that no one
  will type. `close`, `dismiss`, and `reopen` must instead write an empty note,
  because the change of the status is already the record.

### add

- **CB-ADD-1**: `cbugs add` must create one bug with the status `open`, must
  write its first revision, and must print the id of the bug.
- **CB-ADD-2**: `--kind code|spec|task` is required. `--title <text>` is
  required.
- **CB-ADD-3**: `add --kind task` must stop with an error when the environment
  holds `CONVERGE_ROLE`. See "Who logs a task".

### note

- **CB-NOTE-1**: `cbugs note <id>` must write a revision that keeps the status.
- **CB-NOTE-2**: The verb must accept the note as an argument after the id, as
  well as through `--note` and standard input.
- **CB-NOTE-3**: A note is valid on a bug in any status.

### close

- **CB-CLOSE-1**: `cbugs close <id>` must write a revision with the status
  `closed`.
- **CB-CLOSE-2**: `closed` means that the defect is gone. A worker closes a code
  bug when it fixes the bug. The human user closes a spec bug when the
  requirements no longer hold the ambiguity.

### dismiss

- **CB-DISMISS-1**: `cbugs dismiss <id>` must write a revision with the status
  `wontfix`.
- **CB-DISMISS-2**: `wontfix` means that no one will act on the bug. It covers a
  bug that is a duplicate of another, a bug that is wrong, and a defect that the
  project accepts. The two terminal statuses stay apart, so that a count of
  closed bugs is a count of defects that someone fixed.

### reopen

- **CB-REOPEN-1**: `cbugs reopen <id>` must write a revision with the status
  `open`.
- **CB-REOPEN-2**: `reopen` is valid on a bug that is `closed` and on a bug that
  is `wontfix`.

### list

- **CB-LIST-1**: `cbugs list` must print the bugs of the run directory.
- **CB-LIST-2**: Options:
  - **CB-LIST-2.1**: `--kind code|spec|task`: show only that kind. The option
    must be repeatable, and several values mean the union, so that a worker can
    ask for the code bugs and the tasks in one call.
  - **CB-LIST-2.2**: `--status open|closed|wontfix`: show only that status. The
    option must be repeatable, so that a caller can ask for the closed bugs and
    the dismissed bugs together.
- **CB-LIST-3**: With no option, `cbugs list` must show every bug, in every kind
  and every status.
- **CB-LIST-4**: The order must put the bug with the newest revision first. A bug
  that a role reviewed or closed recently therefore comes before an older one.
- **CB-LIST-5**: The listing must show, for each bug, the id, the kind, the
  current status, and the current title. It must not show the revisions.

### show

- **CB-SHOW-1**: `cbugs show <id>` must print one bug in full: the id, the kind,
  the current status, the current title, and every revision in order.
- **CB-SHOW-2**: Each revision must show its citations, with the revision that
  wrote them. A reader sees which requirement each role named, and when.
- **CB-SHOW-3**: The history must show a title that a later revision replaced. A
  reader must be able to see that the wording changed, and when.
- **CB-SHOW-4**: `cbugs <id>` must be the same command as `cbugs show <id>`. See
  "Invocation". The two forms accept the same options, print the same output, and
  give the same error for an id that names no bug.

### search

- **CB-SEARCH-1**: `cbugs search <text>` must print the bugs whose title, in any
  revision, whose notes, or whose citations contain the text. A caller that
  searches for a requirement identifier therefore finds every bug that cites it.
- **CB-SEARCH-2**: The search must ignore the difference between capital letters
  and small letters.
- **CB-SEARCH-3**: `search` must accept the same options as `list`, and must use
  the same order and the same listing form.
- **CB-SEARCH-4**: The reviewer uses `search` to find an existing bug before it
  logs a new one. The coach uses it to find a theme across the history.

## Status changes

- **CB-STAT-1**: A change of the status writes a revision, in the same way as a
  note.
- **CB-STAT-2**: A change to the status that the bug already holds must succeed
  and must write the revision. This keeps an agent that repeats a command from
  failing.
- **CB-STAT-3**: The revisions are therefore the full history of the bug. The
  command keeps no second log, and it stores no state that the history could
  contradict.

## Duplicates

- **CB-DUP-1**: The command must not test for a duplicate, and must not refuse a
  bug that looks like one that exists.
- **CB-DUP-2**: The prompts instruct the reviewer to run `search` before it logs
  a bug. `dismiss` with a note that names the other bug closes out a duplicate
  that gets through.

## Output

- **CB-OUT-1**: Every verb must print in a form that a person can read, by
  default.
- **CB-OUT-2**: Every verb must accept `--json`, and must then print the same
  information as JSON. An agent that wants to process the output uses this form.
- **CB-OUT-3**: The human form of a listing must give one line for each bug, and
  must align the columns, so that an operator can scan it.
- **CB-OUT-4**: The output must use color when it writes to a terminal, and no
  color when it writes to a file or a pipe. Unlike `converge`, this command sees
  what reads it.
- **CB-OUT-5**: The `--json` form must never use color.
- **CB-OUT-6**: A listing with no result must print nothing to standard output,
  and must exit with the status 0. An empty list is a normal answer, not a
  failure.

## Errors

- **CB-ERR-1**: A command that succeeds must exit with the status 0.
- **CB-ERR-2**: A command that fails must print a message to standard error that
  names the cause, and must exit with a non-zero status.
- **CB-ERR-3**: These are failures: a first argument that is neither a verb nor
  a whole number, an option that does not exist, a value that a field does not
  accept, a missing required option, an id that names no bug, a citation whose
  path names no file, a value of `CONVERGE_RUN_DIR` that names no directory,
  and a creation call that fails or that finds no `converge` command on PATH.
  `add --kind task` from an agent of the loop is also a failure. `reviewed add`
  that names no commit of the repository is also a failure. `reviewed add`
  from an agent of the loop is also a failure.
- **CB-ERR-4**: The command specifies no further exit statuses. A caller reads
  the message.

## Concurrency

- **CB-CONC-1**: Two callers can run the command at the same time. A worker
  starts sub-agents, and each one can log a bug.
- **CB-CONC-2**: A write must never be lost, and a record must never be partial.
  Two writes at the same time must both take effect, or the one that fails must
  print an error and change nothing.
- **CB-CONC-3**: Two callers that add a bug at the same time must get different
  ids.
- **CB-CONC-4**: A caller that writes a revision must read the previous revision
  and write the new one as one unit. Two callers that write at the same time must
  not lose the change of one of them.
- **CB-CONC-5**: When the database is busy, the command must wait and try again,
  up to a bounded time. It must stop with an error only after that time.
- **CB-CONC-6**: A read must never see a partial record.

## Out of scope

These are recorded decisions, not oversights.

- **CB-OOS-1**: Retired. CB-OOS-26 replaces the pass-record exclusion.
- **CB-OOS-2** — **A change of the kind of a bug**: rejected. The kind decides
  who acts. The caller dismisses the bug and logs a new one.
- **CB-OOS-3** — **A revision that gives only what changed**: rejected. A full
  state on each revision costs a few repeated values, and it makes the newest
  revision the answer to every question about the present. Nothing has to fold
  the history.
- **CB-OOS-4** — **A name for what a revision did**: rejected. The change of the
  status and of the title says it, and the note gives the reason. A name would be
  a second fact to keep true.
- **CB-OOS-5** — **A stored current status, or a stored closed time**: rejected.
  Every value that the history implies stays derived. This is the point of the
  model.
- **CB-OOS-6** — **Severity or priority**: rejected for v1. Every open code bug
  blocks convergence, so a rank changes no outcome. The worker prompt gives the
  order.
- **CB-OOS-7** — **A citation on the bug, and not on the revision**: rejected. A
  citation is what one role asserted, like a note. A reviewer that cites the wrong
  requirement leaves a record that a later revision answers, and neither
  overwrites the other.
- **CB-OOS-8** — **Citations copied forward, as the status and the title are**:
  rejected. A full state on each revision serves a value that has one current
  answer. The citations of a bug accumulate, and a caller that had to repeat every
  earlier citation to add one would repeat it wrong.
- **CB-OOS-9** — **A verb that removes a citation**: rejected. Nothing in this
  model removes anything. A revision that cites the right requirement, with a note
  that says why, corrects an earlier one.
- **CB-OOS-10** — **A test that the requirement identifier is in the document**:
  rejected. Each document writes its identifiers in its own way, and a heading is
  not a stable identifier. The command tests the path only.
- **CB-OOS-11** — **A filter on the citation in `list`**: rejected for v1.
  `search` finds the bugs that cite a requirement, and it uses the same listing
  form.
- **CB-OOS-12** — **A file path as a field**: rejected. The caller names the path
  in the note, where it writes the rest of the report. No query filters on a file,
  so a field would only repeat the prose.
- **CB-OOS-13** — **A filter on role, iteration, or commit**: rejected for v1.
  `search` finds a bug by its text, and `show` gives the revisions. Add a filter
  when a role needs one.
- **CB-OOS-14** — **`--limit`**: rejected for v1. A run directory holds few
  enough bugs for a full listing. The newest-first order puts the recent bugs at
  the top. The summary shows ten bugs, but that count is fixed, and `list` shows
  every bug.
- **CB-OOS-15** — **Delete**: rejected. `dismiss` covers a bug that no one wants,
  and the record stays for the coach to read. A permanent record is the point.
- **CB-OOS-16** — **A link between two bugs**: rejected for v1. A note that names
  the other id is enough.
- **CB-OOS-17** — **A veto of the `CONVERGED` vote by the loop**: rejected for
  v1. The worker prompt instructs the worker not to vote while an open code bug
  exists. The loop does not query the database, and `cbugs` stays a plain tool.
- **CB-OOS-18** — **An option that names a run directory**: rejected. The
  current directory, or the environment of an agent of the loop, names the run
  directory. An operator who wants another run directory changes directory.
- **CB-OOS-19** — **A bug database in the repository**: rejected. `converge`
  writes nothing into the repository, and a bug list in git would collide with the
  work of a worker.
- **CB-OOS-20** — **Assignment of a bug to a role**: rejected. The kind decides
  who acts.
- **CB-OOS-22** — **An interactive mode**: rejected. Every caller is a script or
  an agent.
- **CB-OOS-23** — **A backup of the database before a migration**: rejected. The
  migration is one transaction, and a failure leaves the file as it was. A copy
  would only guard against a defect in the migration itself.
- **CB-OOS-24** — **A migration from version 1**: rejected. Version 1 is a
  different model: it holds reports and stored state, not revisions. It gets
  the same error as any version that the command does not know. See
  "Migration".
- **CB-OOS-25** — **A removal of a reviewed commit**: rejected. A commit that
  the history drops can come back, as a cherry-pick brings one back, and the
  row does no harm while the commit is away. The count of the unreviewed
  commits reads only relevant commits from the history that the repository
  HEAD reaches.
- **CB-OOS-26** — **A separate review pass table or finding record**: rejected.
  Review history records commit coverage, including the profile and completion
  time. It holds no findings. Coverage records may exist even when a pass finds
  no defect. The logs of the loop record the pass itself.
