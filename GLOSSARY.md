# converge

One vocabulary for the `converge` loop, the `review-panel` command, and the
`cbugs` tracker. The requirements documents under `docs/` give the normative
definitions in their "Terms" sections. This glossary picks one word for each
concept and names the words to avoid.

## Language

### People and places

**Operator**:
The person who runs the project and its commands: starts the loop, resolves spec bugs, and asks for tasks. An agent is never an operator.
_Avoid_: human user, human, user, person, owner, caller (when the caller is a person)

**Project**:
The repository that the operator works on with `converge`. A project holds one or more run directories.
_Avoid_: repo, codebase

**Run directory**:
The directory that one run of `converge` works from, and that its state belongs to. The repository root or any subdirectory can be one.
_Avoid_: working directory, project directory, scope directory

### Loop and agents

**Loop**:
The `converge` process that schedules and runs agent iterations in the background.
_Avoid_: controller, daemon, runner

**Client**:
The `converge` command that the operator runs to start a loop or attach to the running one.
_Avoid_: frontend, terminal

**Session**:
One run of the loop, from start to its result.
_Avoid_: run, execution

**Harness**:
The agent command that the loop starts for an agent, such as `claude`, `opencode`, or `codex`.
_Avoid_: CLI, backend, provider

**Profile**:
One harness, one model, and an optional effort, written `harness:model[:effort]`.
_Avoid_: model (when a whole profile is meant), config

**Role**:
The job of one agent: worker, reviewer, coach, discovery agent, merge agent, or fixer.
_Avoid_: agent type, persona

**Invocation**:
One start of a harness process for one role with one profile.
_Avoid_: call, agent call, run

**Attempt**:
An invocation inside a fallback chain.
_Avoid_: try, retry

**Fallback chain**:
The attempts that one scheduled run of a role makes through its profile list. It ends at the first success, or when every profile has started once.
_Avoid_: retry loop, rotation

**Iteration**:
One scheduled worker chain, counted toward the worker limit and the coach cadence.
_Avoid_: step, cycle, turn

**Worker**:
The agent of one iteration. It reads the requirements and the code, then makes one useful change.
_Avoid_: implementer, builder, coder

**Fixer**:
A worker iteration that runs on the fixer profile list because the coach escalated.
_Avoid_: strong worker, escalated worker, repair iteration

**Discovery agent**:
The agent that selects requirements sources and writes lookup instructions for one session.
_Avoid_: scanner, finder

**Lookup instructions**:
The instructions that discovery produces to read the requirements sources of one session. They select sources, not a copy of their content.
_Avoid_: requirements cache, discovered requirements

**Scope**:
The requirements paths that the operator names on the command line. An empty scope requires discovery.
_Avoid_: targets, inputs

**Coach**:
The agent that reads recent worker logs and writes guidance. The loop starts it on a cadence, after a blocked vote, or after a stall.
_Avoid_: supervisor, mentor, manager

**Guidance file**:
The file that the coach writes and that the loop puts into each worker prompt.
_Avoid_: coach notes, hints, memory

**Journal**:
The coach's private record of its observations and interventions.
_Avoid_: coach log, diary

**Escalation**:
The coach's request, in its final message, that the next worker iteration runs as a fixer.
_Avoid_: upgrade, promotion

### Review

**Reviewer**:
An agent that checks the code against the requirements and files bugs.
_Avoid_: auditor, inspector, critic

**Review pass**:
One run of a reviewer that the loop starts.
_Avoid_: review round, audit

**Cadence pass**:
A review pass that the count of unreviewed commits starts. It reads the unreviewed commits in the considered history.
_Avoid_: cadence review, periodic review, incremental review

**Vote panel**:
One panel run that the loop starts when the done count first rises from zero to one. Its reviewers read the whole live working tree.
_Avoid_: panel (alone), convergence review, final review

**Panel run**:
One `review-panel` invocation: its reviewers, its merge pass, and its closing report.
_Avoid_: review session, panel session

**Merge agent**:
The agent of a panel run that combines duplicate new bugs after the reviewers finish.
_Avoid_: deduplicator, consolidator

**New bug**:
A bug that a reviewer of this panel run created.
_Avoid_: finding, result

**Retained new bug**:
A new bug that the merge pass does not close as a duplicate.
_Avoid_: surviving finding, kept finding

**Complete run**:
A panel run in which every reviewer, the required merge pass, and the required result recording succeed.
_Avoid_: successful run, clean run

**Relevant commit**:
A commit that the repository `HEAD` reaches and that changes a path in the run directory.
_Avoid_: in-scope commit, affecting commit

**Review history**:
The commits that the branch and base-reference rules select, before path and count limits.
_Avoid_: branch history, commit range

**Considered history**:
The 1,000 newest relevant commits in the review history.
_Avoid_: window, lookback

**Reviewed commit**:
A commit that a review pass or a panel run has recorded in the bug tracker.
_Avoid_: covered commit, seen commit

**Unreviewed commit**:
A commit in the considered history that no review has recorded.
_Avoid_: pending commit (except in the `reviewed pending` verb), new commit

**Directory HEAD**:
The newest relevant commit of a run directory.
_Avoid_: scope HEAD, local HEAD

### Votes and stops

**Done vote**:
The final message of a successful worker that holds the token `CONVERGED` alone on a line.
_Avoid_: vote (alone), convergence vote, approval

**Blocked vote**:
The final message of a successful worker that holds the token `BLOCKED` alone on a line.
_Avoid_: block, stuck vote

**Non-vote**:
The final message of a successful worker that holds no vote token, or both vote tokens.
_Avoid_: abstention, no vote

**Convergence**:
The stop that `N` consecutive done votes cause. It is the successful result of a session.
_Avoid_: completion, done state, success (alone)

**Blocker**:
An open spec bug, or a tool or resource that no worker can reach, that stops a piece of work.
_Avoid_: dependency, impediment, obstacle

**Stalled chain**:
A worker chain that produced output, left no new relevant commit, and gave no vote.
_Avoid_: idle iteration, spin, no-op iteration

**Graceful stop**:
The stop that the first Ctrl-C or a stop request causes. Active invocations finish, and no new one starts.
_Avoid_: soft stop, pause, drain

**Hard stop**:
The stop that a second Ctrl-C or SIGTERM causes. Active invocations and their children end at once.
_Avoid_: kill, abort, force stop

### Bug tracker

**Bug tracker**:
The `cbugs` command and its database for one run directory. It keeps the bugs and the reviewed commits.
_Avoid_: issue tracker, ticket system, store

**Bug**:
One record in the bug tracker. A bug has an identifier and a kind, and nothing else that cannot change.
_Avoid_: issue, ticket, finding, item, record (when a bug is meant)

**Kind**:
The class of a bug: code, spec, or task. It decides who acts, and it never changes.
_Avoid_: type, category, label

**Code bug**:
A defect in the project code. A worker fixes it.
_Avoid_: bug (when the kind matters), error, flaw

**Spec bug**:
An ambiguity, a gap, or a contradiction in the requirements documents. The operator resolves it, and no agent works on it or waits for it.
_Avoid_: question, open point, requirements issue

**Task**:
A punchlist item that an operator asked for. A worker does it. Only an operator directs the record of one.
_Avoid_: todo, feature request, chore, ticket

**Revision**:
One assertion about a bug, by one role, at one commit. It carries the full state of the bug and a note.
_Avoid_: update, edit, history entry, event

**Visible revision**:
A revision with no commit, or one whose commit the current `HEAD` reaches.
_Avoid_: reachable revision, live revision

**Current revision**:
The visible revision of a bug with the greatest revision id.
_Avoid_: latest revision, head revision, state

**Hidden bug**:
A stored bug with no visible revision at the current `HEAD`.
_Avoid_: deleted bug, orphaned bug, archived bug

**Citation**:
A reference from a revision to a requirements document, and optionally to one identifier inside it.
_Avoid_: link, reference, source

**Caller**:
Whoever runs `cbugs`: the loop, an agent, or the operator.
_Avoid_: client, invoker

### State

**State directory**:
The durable directory of one run directory. It holds the bug database, the guidance file, the journal, and the logs, and it survives a restart.
_Avoid_: data directory, cache, home

**Runtime directory**:
The temporary directory of one run directory. It holds the locks and the pipes, and nothing that must survive a restart.
_Avoid_: tmp directory, lock directory, scratch
