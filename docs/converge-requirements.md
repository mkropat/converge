# Requirements: converge

`bin/converge` is a loop that runs autonomous agent iterations until a project satisfies its requirements documents. One run works from one directory of the project: the root of the repository, or a subdirectory of it. That directory is the run directory, and the state of the run belongs to it.

This document gives the required behavior only. It does not give an implementation plan.

## Requirement identifiers

Each requirement in this document has an identifier. A citation names it, as
`docs/converge-requirements.md:CV-ITER-4`.

- An identifier has the form `CV-<SECTION>-<number>`. `CV` names this document.
  `<SECTION>` names the section. The number counts the requirements of that
  section, from 1.
- A requirement that holds a list of parts numbers each part after a dot, as
  `CV-ITER-3.5`. A citation can name the whole requirement or one part.
- An identifier never changes its meaning. A requirement that this document
  removes leaves its identifier unused. A new requirement takes the next free
  number of its section.
- The "Terms" section defines words. It holds no requirement, and therefore no
  identifier.
- Section-intro prose is context, not a requirement. A normative sentence
  belongs in a numbered item.

These are the section codes.

| Code | Section |
| --- | --- |
| `PRIN` | Design principles |
| `INV` | Invocation |
| `SCOPE` | Requirements scope |
| `DISC` | Requirements discovery |
| `PLAT` | Platform |
| `HARN` | Harness |
| `BG` | Background operation |
| `ITER` | Iteration behavior |
| `ENV` | The environment of an agent |
| `OUT` | Output |
| `COST` | Cost tracking |
| `CONV` | Convergence and stopping |
| `REV` | Reviewer |
| `COACH` | Coach |
| `REF` | Refactor |
| `NOTIFY` | Notification |
| `SL` | State and logs |
| `STATE` | The state directory |
| `RUN` | The runtime directory |
| `ID` | Identity of a run |
| `FAIL` | Signals, timeouts, and failures |
| `OOS` | Out of scope |

## Terms

- **Run directory**: the current working directory when the operator starts the run. The root of the repository and any subdirectory of it can be the run directory.
- **Operator**: the person who runs the project and its commands. An agent is not an operator.
- **Loop**: the `converge` script that runs the iterations, in the background.
- **Client**: the `converge` command that the operator runs. The client starts a loop, or attaches to the loop that runs.
- **Controller**: the process that starts agents and records their results: the loop, or the `review-panel` command. An agent is not a controller.
- **Session**: one run of the loop, with its output file, its process id, and its result.
- **Harness**: the agent command that the controller starts for an agent.
- **Attempt**: one invocation of a harness, with one profile, inside a fallback chain.
- **Fallback chain**: the attempts that one scheduled run of a role makes through its profile list. The chain ends when an attempt succeeds, or when every entry of the list has started once.
- **Discovery agent**: an agent that selects requirements sources and writes instructions to read them.
- **Lookup instructions**: the specific instructions that discovery produces for one session. They select sources, not a fixed copy of their content.
- **Worker**: one agent instance that the loop starts for one iteration.
- **Refactor agent**: an agent that improves the structure of code changed during the session and preserves project behavior.
- **Refactor pass**: one scheduled fallback chain of the Refactor agent.
- **Session start commit**: the repository HEAD captured when a new loop session starts.
- **Pass start commit**: the repository HEAD captured before a Refactor pass starts.
- **Reviewer**: an agent that the loop starts to examine code and to log bugs.
- **Review pass**: one run of the reviewer.
- **Cadence pass**: a review pass that the count of unreviewed commits starts. It reads the unreviewed commits in the considered history.
- **Vote panel**: one `review-panel` run made pending when the consecutive done count changes from zero to one. It starts after the done-vote Refactor trigger if the vote still stands. Its reviewers read the whole live working tree in parallel.
- **Relevant commit**: a commit that git reaches from the repository HEAD and that changes one or more paths in the run directory. When the run directory is the repository root, every reachable commit is relevant.
- **Review history**: the commits selected by the branch and base-reference rules of `docs/cbugs-requirements.md:CB-RVW-20` and `CB-RVW-21`.
- **Considered history**: the 1,000 newest relevant commits in the review history, or all relevant commits when fewer than 1,000 exist.
- **Unreviewed commit**: a commit in the considered history that no review pass has recorded in the bug database.
- **Coverage**: the records of the bug tracker that name the commits that a review read. A review pass or a panel run records coverage only when it succeeds. Coverage says what was read; it approves nothing.
- **Directory HEAD**: the newest relevant commit. A run directory with no relevant commit has no directory HEAD.
- **Coach**: an agent that the loop starts on a fixed cadence, after a blocked vote, or after a stall, to review recent worker logs and commits and to write guidance.
- **Done vote**: the final message of a successful worker that holds the token `CONVERGED` alone on a line.
- **Blocked vote**: the final message of a successful worker that holds the token `BLOCKED` alone on a line.
- **Blocker**: an open spec bug, or a tool or resource that no worker can reach, that stops a piece of work.
- **Stalled chain**: a worker chain that produced output, left no new relevant commit, and gave no vote.
- **Stall streak**: the count of consecutive stalled chains. A relevant commit or a worker vote resets it. A coach run does not.
- **Escalation**: the request of the coach, in its final message, that the next worker iteration runs as a fixer.
- **Fixer**: a worker iteration that runs on the fixer profile list because the coach escalated.
- **Bug tracker**: `bin/cbugs`, which keeps the bugs and the reviewed commits of the run directory in its state directory. See `docs/cbugs-requirements.md`.
- **Code bug**: a defect in the code. A worker fixes it.
- **Spec bug**: an ambiguity, a gap, or a contradiction in the requirements documents. The operator resolves it. No agent works on a spec bug, and no agent waits for one.
- **Task**: a punchlist item that an operator asked for. A worker does it. Only an operator directs the record of one.
- **Scope**: the requirements paths that the operator names on the command line. An empty scope requires discovery before the normal invocations.
- **Citation**: a reference from a bug revision to a documented requirement. `cbugs` writes it from a `--cite` option.
- **Guidance file**: the file that the coach writes and that the loop injects into each worker prompt.
- **Journal**: the coach's private record of its observations and interventions.
- **Notification**: a message that the loop sends to the operator when one of the events of **CV-NOTIFY-3** occurs.
- **Notification command**: the shell command line in `CONVERGE_NOTIFY`. The loop runs it to send a notification.
- **State directory**: the durable directory that holds the guidance file, the journal, the bug database, and the logs of one run directory. It survives a restart of the machine.
- **Runtime directory**: the temporary directory that holds the locks and the pipes of one run directory. It holds nothing that must survive a restart of the machine.

## Design principles

These principles explain the intent behind the requirements. Apply them when a requirement is ambiguous.

- **CV-PRIN-1**: The goal is autonomous convergence on the documented requirements. Speed and token cost are secondary.
- **CV-PRIN-2**: Retired. Defined worker context without lookup instructions. **CV-PRIN-7** replaces this behavior.
- **CV-PRIN-3**: No component writes or follows an implementation plan. Requirements documents describe behavior. They do not describe implementation steps.
- **CV-PRIN-4**: A defect that one iteration finds must reach a later iteration. A worker has no memory, so a defect that nobody records is a defect that nobody fixes. The bug tracker is that channel, and the guidance file is not: the coach rewrites the guidance on each coach run, and keeps it short.
- **CV-PRIN-5**: Prefer too little process over too much. Add structure only where it changes outcomes.
- **CV-PRIN-6**: It is acceptable for the loop to stop before the requirements are fully met. It is not acceptable for the loop to add large amounts of code that the requirements do not need. The operator can clarify requirements and restart the loop.
- **CV-PRIN-7**: Each worker must start with no memory of earlier iterations. It must read the current repository state and requirements. It may use the session's lookup instructions and coach guidance. It must not continue a stored implementation plan.

## Invocation

- **CV-INV-1**: The script must live at `bin/converge`.
- **CV-INV-2**: The script must operate on the run directory: the current working directory when the operator starts the run. The run directory can be the root of the repository or any subdirectory of it.
- **CV-INV-3**: The script must accept these options:
  - **CV-INV-3.1**: Retired. Accepted `--harness`. See **CV-INV-11** and **CV-HARN-8**.
  - **CV-INV-3.2**: Retired. Accepted `--model`. See **CV-INV-11** and **CV-HARN-8**.
  - **CV-INV-3.3**: Retired. Accepted `--coach-model`. See **CV-INV-11** and **CV-HARN-8**.
  - **CV-INV-3.4**: Retired. Accepted `--review-model`. See **CV-INV-11** and **CV-HARN-8**.
  - **CV-INV-3.5**: Retired. Defined votes alone as the stop condition. **CV-INV-3.15** replaces this behavior.
  - **CV-INV-3.6**: Retired. `--coach-every <K>` set one period, and `K` could be `0`. **CV-INV-3.16** and **CV-INV-3.17** replace this behavior.
  - **CV-INV-3.7**: `--no-coach`: disable the coach.
  - **CV-INV-3.8**: Retired. `--review-every <R>` gave the number of worker iterations between review passes. **CV-INV-3.14** replaces this behavior. The count lived in the memory of the loop, and a Ctrl-C that stopped the run threw it away. The count of unreviewed commits is durable, in the bug database.
  - **CV-INV-3.9**: `--no-review`: disable the reviewer.
  - **CV-INV-3.10**: `--timeout <seconds>`: the maximum duration of one worker, reviewer, or coach invocation. Default: `3600`. The value must be a nonnegative whole number. Zero must select an effective timeout of `2147483647` seconds. This setting provides no practical time limit, but the finite limit still applies. The command must replace zero with this effective value before execution and use the normal timeout rules.
  - **CV-INV-3.11**: `--max-iterations <N>`: the maximum number of worker iterations. Default: unbounded.
  - **CV-INV-3.12**: `--foreground`: run the loop in the terminal of the operator, and not in the background.
  - **CV-INV-3.13**: Retired. Required more than `N` unreviewed commits. **CV-INV-3.14** replaces this threshold.
  - **CV-INV-3.14**: `--review-after <N>`: run a cadence pass when at least `N` commits are unreviewed, subject to **CV-CONV-34**. `N` must be a positive integer. Default: `5`.
  - **CV-INV-3.15**: `--consensus <N>`: the required number of consecutive successful worker done votes. Default: `2`. `N` must be a whole number. With `N` equal to `0`, the loop must converge without starting any agent. See **CV-CONV-33**, **CV-CONV-26**, and **CV-CONV-31**.
  - **CV-INV-3.16**: `--coach-first <F>`: the number of worker iterations before the first coach run of a session. `F` must be a whole number. `F` can be `0`: then the coach is due before the first worker iteration. Default: `5`. **CV-COACH-10** gives the details.
  - **CV-INV-3.17**: `--coach-every <K>`: the number of worker iterations between one coach run and the next. `K` must be a positive integer. The script must stop with an error when `K` is `0`; `--coach-first 0 --coach-every 1` gives a coach on every check. Default: `10`. **CV-COACH-10** gives the details.
  - **CV-INV-3.18**: `--blocked <N>`: the number of consecutive blocked votes that stop the loop. `N` must be a positive integer. The script must stop with an error when `N` is `0`. Default: `2`. **CV-CONV-29** gives the details.
  - **CV-INV-3.19**: `--stall-after <K>`: the number of consecutive stalled chains that make the coach due. `K` must be a positive integer. The script must stop with an error when `K` is `0`. Default: `3`. **CV-COACH-11** gives the details.
  - **CV-INV-3.20**: `--stall-notify <N>`: the stall streak that sends the `stalled` notification. `N` must be a positive integer. The script must stop with an error when `N` is `0`. Default: `6`. `N` normally exceeds `--stall-after`, so that the coach runs before the operator hears of a stall. The script must not enforce that relation. **CV-NOTIFY-11** gives the details.
  - **CV-INV-3.21**: `--refactor-after <N>`: the number of new relevant commits that makes Refactor due. `N` must be a positive integer. Default: `5`.
  - **CV-INV-3.22**: `--no-refactor`: disable Refactor. Refactor is enabled by default. Disabling review or coaching must not disable Refactor.
- **CV-INV-4**: Retired. Passed unknown options to the harness. **CV-INV-11** rejects harness arguments.
- **CV-INV-5**: Retired. A run took no positional argument. **CV-INV-8** replaces this behavior.
- **CV-INV-6**: Retired. Passed arguments after `--` to the harness. **CV-INV-11** replaces this behavior.
- **CV-INV-7**: The script must stop with an error when an argument before `--` starts with `-` and is not an option of **CV-INV-3**. The error must name the argument. A typo must not become a harness option.
- **CV-INV-8**: The script must accept positional arguments before `--`. Each one names a requirements document file, or a directory that holds requirements documents. "Requirements scope" gives the behavior.
- **CV-INV-9**: The run directory anchors the run. The state directory, the bug database, the resolution of every scope path, the review scope, and the working directory of every agent derive from the run directory, as the sections that govern them give. Two run directories share no state and no bug database. A subdirectory of a repository is therefore a place to run the command in its own right. The repository that contains the run directory supplies the git history. A review pass uses only the relevant commits from that history.
- **CV-INV-10**: The script must accept `--init-state`. A call that holds it
  must start no loop and must attach to none. It must instead perform the init
  operation and exit:
  - **CV-INV-10.1**: The init operation must work on the run directory: the
    current working directory of the call, as CV-INV-2 gives. It must accept no
    argument that names a run directory. The current directory is the one
    anchor of the system, as CV-OOS-26 gives.
  - **CV-INV-10.2**: The init operation must create the state directory, the
    subdirectories of the state directory, and the runtime directory when they
    do not exist, under the same rule as CV-ID-5. It must leave a directory
    that exists as it is. Two init calls that run at the same time must both
    succeed.
  - **CV-INV-10.3**: The init operation must print one line that names the path
    of the state directory. It must exit with the status 0. It must write no
    session output, no session status, no harness record, and no log.
  - **CV-INV-10.4**: The script must stop with an error when the call gives
    `--init-state` a positional argument or another option of CV-INV-3. Such a
    call carries settings that the init operation cannot use.
  - **CV-INV-10.5**: A session tests no harness commands; a missing harness fails on its first invocation. The init operation must test none, because it makes directories and runs no agent.
- **CV-INV-11**: The script must reject `--harness`, `--model`, `--review-model`, and `--coach-model`. It must reject all arguments after `--`. It must name each rejected argument. It must accept no profile option and read no profile configuration file.
- **CV-INV-12**: The script must accept `--state-dir`. A call that holds it
  must start no loop and must attach to none. It must instead perform the
  state query and exit:
  - **CV-INV-12.1**: The state query must work on the run directory: the
    current working directory of the call, as CV-INV-2 gives. It must accept no
    argument that names a run directory, for the reason that CV-INV-10.1 gives.
  - **CV-INV-12.2**: The state query must print one line that names the path
    of the state directory that a run in this directory uses, as CV-ID-1 gives.
    It must exit with the status 0. It must print the same path that
    `--init-state` prints for the same directory.
  - **CV-INV-12.3**: The state query must create no directory and no file. It
    must not test whether the state directory exists. It must write no session
    output, no session status, no harness record, and no log.
  - **CV-INV-12.4**: The script must stop with an error when the call gives
    `--state-dir` a positional argument, an option of CV-INV-3, or
    `--init-state`. The error must name the argument. The state query answers
    one question, and such a call asks a second one.
  - **CV-INV-12.5**: The state query must test no harness command, because it
    runs no agent. It must stop with an error that names `git` when `git` is
    not on PATH, because the name of the state directory derives from the root
    of the repository, and without `git` the script cannot find that root.

## Requirements scope

The operator can point a session at part of the project. The scope says which
requirements documents the agents work on.

- **CV-SCOPE-1**: The scope of a session is the list of positional arguments, in the order that the operator gave them. A session with no positional argument has an empty scope.
- **CV-SCOPE-2**: The script must resolve each path of the scope against the run directory, and must stop with an error when the path does not exist. The error must name the path. A typo must not become a run that ignores the scope.
- **CV-SCOPE-3**: The loop must give each path to an agent as the operator wrote it. An agent runs in the run directory, so a relative path names the same document for the agent as it named for the operator.
- **CV-SCOPE-4**: Retired. Each unscoped agent found requirements itself. **CV-SCOPE-10** replaces this behavior.
- **CV-SCOPE-5**: When the scope is not empty, the worker prompt and the reviewer prompt must give the paths of the scope, and must instruct the agent to work on those requirements documents only. A path that is a directory names every requirements document under it.
- **CV-SCOPE-6**: A scope says what to build and what to judge. It does not remove the other requirements documents of the repository. A change that contradicts a document outside the scope is still a spec bug, as **CV-ITER-3.7** gives.
- **CV-SCOPE-7**: The coach prompt must not carry the scope. The coach reads the logs and the process, and not the requirements documents.
- **CV-SCOPE-8**: Retired. Displayed an empty scope without discovery status. **CV-SCOPE-11** replaces this behavior.
- **CV-SCOPE-9**: Retired. Forbade stored scope records. **CV-SCOPE-12** replaces this behavior.
- **CV-SCOPE-10**: With an empty scope, the loop must use requirements discovery. Each worker and cadence reviewer prompt must include the same accepted lookup text. It must identify that text as the resolved source selection for the session. The prompt must instruct the agent to follow that text to read the current requirements. The agent must not repeat source discovery or select replacement sources.
- **CV-SCOPE-11**: The startup panel must show explicit scope paths when supplied. Otherwise, it must show that discovery is pending or skipped. After successful discovery, the loop must print the full lookup text and its file path.
- **CV-SCOPE-12**: Scope and lookup instructions must belong to one session. An attached client must keep both unchanged. A new session must use its own explicit paths or perform new discovery. Saved logs and lookup files must not select requirements for a later session.
- **CV-SCOPE-13**: Worker and reviewer prompts must instruct agents to read current source content on each invocation. The controller must not freeze requirements content or run a separate refresh agent between iterations. A selected directory or pattern must include files that match when the agent reads it.
- **CV-SCOPE-14**: If an agent cannot read a required source, its prompt must instruct it to report the lookup failure. It must not select a replacement, implement work against incomplete requirements, or vote for convergence. A reviewer must report an incomplete review.
- **CV-SCOPE-15**: Worker and reviewer prompts must instruct agents to cite the original requirements source in bugs. A citation must use the local path or external source reference accepted by `docs/cbugs-requirements.md:CB-CITE-11`. The lookup file is not a requirements source.

## Requirements discovery

Discovery selects sources once. Later agents read their current content.

- **CV-DISC-1**: A new session with no scope paths must run one discovery invocation before any worker, cadence reviewer, or coach. Explicit scope paths must skip discovery. Help, state initialization, attachment, `--consensus 0`, and `--max-iterations 0` must start no discovery agent. An operator stop must prevent a new discovery invocation.
- **CV-DISC-2**: Retired. Used the first worker profile with no fallback. **CV-DISC-13** replaces this behavior.
- **CV-DISC-3**: The discovery prompt must instruct the agent to follow applicable project instructions to locate requirements. If those instructions give no discovery rule, it must find requirements documents under the run directory. Sources may be local documents or external sources accessible through the harness. The controller must contain no discovery rule for a specific service.
- **CV-DISC-4**: The discovery prompt must require specific lookup instructions. They must name selected sources and explain how to read their requirements. They must resolve choices such as issue identities from branch names. They may select a directory or file pattern. Paths must resolve against the run directory. Linked-source selection must be explicit. The output must contain no requirements summary, implementation plan, or instruction to repeat general discovery.
- **CV-DISC-5**: The controller must supply a path specific to the session for one plain text output file in the state directory of the run directory. The discovery prompt must instruct the agent to write lookup instructions there only when it can identify usable sources. Otherwise, it must leave no output file and explain the failure in its final message.
- **CV-DISC-6**: The discovery prompt must permit no changes except writing the supplied output file. It must forbid repository edits, requirements edits, commits, guidance changes, and bug writes.
- **CV-DISC-7**: Retired. Stopped startup on the first failed discovery invocation. **CV-DISC-14** replaces this behavior.
- **CV-DISC-8**: Discovery must not count as a worker iteration, a done vote, or a coach cadence step. It must not advance worker or reviewer profile rotation.
- **CV-DISC-9**: The controller must preserve the accepted lookup text for the session. Changes to branches or general discovery rules must not trigger new discovery or change that text. A new session is required to select different sources.
- **CV-DISC-10**: A vote panel must receive the parent's accepted lookup text when the parent has no explicit scope paths. Its reviewers must use that same text. The panel must not perform new discovery. Coach and merge prompts must not include the lookup block.
- **CV-DISC-11**: Discovery must have its own invocation prompt, stream log, profile, and result record under the normal logging rules. The accepted lookup file must remain available for diagnosis after the session ends. Files from different sessions must not overwrite one another.
- **CV-DISC-12**: The controller must retain the existing done vote rules. It must not monitor source content or change the done count or the blocked count because requirements changed. Workers must read current requirements before voting. The controller must not claim that different invocations read identical content.
- **CV-DISC-13**: Discovery must run as a fallback chain under **CV-HARN-24** over the `CONVERGE_WORKER_PROFILE` list, from its first entry, with the normal worker default when unset. The chain must not advance the worker rotation, as **CV-DISC-8** gives. Each attempt must use the run directory and the normal harness, effort, access, timeout, and output rules. The harness must retain its normal project instructions and tool configuration. The controller must not parse project instruction files to find discovery rules.
- **CV-DISC-14**: The controller must accept discovery only when an attempt succeeds and its output is a readable regular file with text other than whitespace. A nonzero exit must start the next attempt of the chain. The controller must remove an output file that a failed attempt left before it starts the next attempt. A timeout, an invalid output after a successful exit, or a chain with no successful attempt must stop startup with status `2`. It must start no normal agent and perform no attempt beyond the chain. Operator-stop statuses must take priority.

## Platform

- **CV-PLAT-1**: The script must run on Linux and on macOS.
- **CV-PLAT-2**: The script may use bash 4 syntax. macOS supplies bash 3.2. The
  script must test the version of bash before it runs any bash 4 syntax, and
  must stop with an error when the version is too old.
- **CV-PLAT-3**: The script uses the GNU versions of `timeout`, `tail`, `flock`,
  and `setsid`. The BSD versions that macOS supplies do not accept the necessary
  options.
- **CV-PLAT-4**: On macOS, the operator installs the GNU versions with Homebrew,
  from the `coreutils` and `util-linux` formulae. Homebrew keeps them off the
  normal PATH. The script must find them and put them on its own PATH.
- **CV-PLAT-5**: The script must stop with an error when a necessary tool is
  absent, or when the tool on the PATH is the BSD version. The error must name
  the Homebrew formula that supplies the GNU version.
- **CV-PLAT-6**: The script must not add a second code path for BSD tools. One
  code path, on GNU tools, keeps the behavior the same on both platforms.

## Harness

Each role selects a harness, a model, and optional effort through an agent profile.

- **CV-HARN-1**: Retired. Selected one harness for the run. **CV-HARN-8** replaces this behavior.
- **CV-HARN-2**: Retired. Kept one harness on attach. **CV-HARN-13** preserves the profile lists.
- **CV-HARN-3**: Retired. Stored the selected harness. **CV-HARN-12** forbids new selection state.
- **CV-HARN-4**: Retired. Tested one harness. **CV-HARN-19** validates profile lists.
- **CV-HARN-5**: Retired. Selected models through options, old environment variables, and harness defaults. **CV-HARN-8** replaces this behavior.
  - **CV-HARN-5.1**: Retired. Defined Claude model defaults. See **CV-HARN-8**.
  - **CV-HARN-5.2**: Retired. Defined OpenCode model defaults. See **CV-HARN-8**.
- **CV-HARN-6**: Retired. Printed one harness and three models. **CV-HARN-15** replaces this output.
- **CV-HARN-7**: Retired. Defined output normalization for two harnesses. **CV-HARN-21** replaces it.
  - **CV-HARN-7.1**: Retired. Defined final-message extraction. See **CV-HARN-21**.
  - **CV-HARN-7.2**: Retired. Required computed invocation totals. See **CV-HARN-21**.
  - **CV-HARN-7.3**: Retired. Defined reported tool failures. See **CV-HARN-21**.

- **CV-HARN-8**: For workers, cadence reviewers, and coaches, the loop must select ordered, comma-separated profile lists only from `CONVERGE_WORKER_PROFILE`, `CONVERGE_REVIEWER_PROFILE`, and `CONVERGE_COACH_PROFILE`. An unset variable defaults to `claude:sonnet` for the worker and `claude:opus` for the reviewer and coach. An empty value is an error.
- **CV-HARN-9**: Retired. Restricted profiles to Claude and OpenCode. **CV-HARN-17** replaces it.
- **CV-HARN-10**: Retired. Required rejection of unsupported effort by the loop. **CV-HARN-18** replaces it.
- **CV-HARN-11**: Retired. Required startup validation of all profile settings. **CV-HARN-19** replaces it.
- **CV-HARN-12**: The loop must ignore old stored harness selection and write no new harness or profile selection state. On a new session, it must reject a set `CONVERGE_HARNESS` or `CONVERGE_<HARNESS>_MODEL`, `CONVERGE_<HARNESS>_REVIEW_MODEL`, or `CONVERGE_<HARNESS>_COACH_MODEL`, for `CLAUDE` or `OPENCODE`, including empty values. The error must name the old variable and direct the operator to the role profile variables.
- **CV-HARN-13**: The loop must take a session snapshot of the profile lists. An attached client must leave these lists unchanged, even if its environment differs. A new session must read its own environment.
- **CV-HARN-14**: Retired. Rotated profiles with no fallback after a failure. **CV-HARN-23** and **CV-HARN-24** replace this behavior.
- **CV-HARN-15**: The startup panel must show each role's full canonical profile list and whether the role is disabled. Each invocation line and invocation log must identify the selected full canonical profile, including explicit effort.

Example environment:

```sh
export CONVERGE_WORKER_PROFILE='claude:sonnet, codex:gpt-5-codex'
export CONVERGE_REVIEWER_PROFILE='claude:opus, codex:gpt-5-codex:high'
export CONVERGE_COACH_PROFILE='claude:opus, codex:gpt-5-codex'
```

- **CV-HARN-16**: Retired. Selected one merge profile for vote panels. **CV-HARN-25** replaces this behavior.

- **CV-HARN-17**: Each profile must have the form `harness:model[:effort]`. The loop must trim spaces around each list entry. Each present field must be nonempty and contain no whitespace, colon, or comma. A model may contain `/`. The harness must be `claude`, `opencode`, or `codex`. The canonical profile is the trimmed entry, with all field values unchanged. The loop must reject duplicate canonical profiles within a role. All supported harnesses must be usable for workers, cadence reviewers, panel reviewers, merge agents, and coaches, including mixed harness lists.
- **CV-HARN-18**: Effort must use the selected harness's native setting. Omitted effort must use the harness default. Explicit Codex effort must be passed unchanged as `model_reasoning_effort`; only the Codex CLI must validate its value and compatibility with the model. The loop must validate its syntax under **CV-HARN-17**, but must not maintain an allowed-value list or discover supported Codex efforts. For other harnesses, the loop must reject an unsupported explicit effort under their existing conventions. It must never omit or replace explicit effort as a fallback.
- **CV-HARN-19**: Before the first agent invocation, the loop must validate profile syntax for all roles, enabled or disabled, and settings subject to loop validation under **CV-HARN-18**. It must report those invalid settings before starting any agent. The loop tests no harness command; a missing harness fails on its first invocation. A Codex effort rejected by the CLI must be an invocation failure under the normal failure and rotation rules.
- **CV-HARN-20**: Each Codex invocation must start a fresh, non-interactive `codex exec` session with JSONL output and ephemeral session storage. It must run with full filesystem and network access and approval prompts disabled, under the same direct-launch convention as the other harnesses. It must use the selected model and any explicit effort. It must inherit normal Codex authentication, user configuration, MCP servers, skills, and project instructions, while explicitly setting the invocation's model, supplied effort, permissions, and run directory. It must not resume a prior Codex session. Converge must retain its normal invocation logs and prompts; the coach must read those logs without requiring native Codex rollout files.
- **CV-HARN-21**: The loop must normalize each supported harness's output under the transcript and logging requirements. For Claude, the final message is its result message. For OpenCode, it is the text of the last assistant message. For Codex, it is the text of the last completed `agent_message` item; earlier agent messages are transcript commentary and must not supply done votes. Codex command executions must show the reported command and identify a reported nonzero exit as a tool failure. Other harnesses must show tool failures when their streams report them; OpenCode shell errors reported as normal results retain the existing display convention. File-change items must make changed paths and the reported operation visible. The full emitted stream, including available tool results, must remain in the invocation log. Turns and duration must use reported totals or be computed from the stream and elapsed invocation time when possible; unavailable statistics must remain absent. Cost must follow the existing **CV-COST-1** through **CV-COST-10** rules. Absent Codex dollar cost must remain absent, with no estimate from token usage and no additional token tracking or summary feature.
- **CV-HARN-22**: Codex invocation success must use the process exit status and the existing timeout and operator-stop rules. The loop must not require a separate successful terminal turn event. A failed, timed-out, or stopped worker must not supply a done vote, even when its captured final message contains `CONVERGED`.
- **CV-HARN-23**: Each role must use its list in independent round-robin order. Each session must start each role at its first entry. Cadence passes must use the reviewer sequence. Vote panels and merge invocations must not consume a turn in that sequence. Each started attempt consumes one turn, including a failure or timeout. A skipped or disabled invocation consumes no turn. The next scheduled run of a role must start at the entry after the last attempt of that role.
- **CV-HARN-24**: Each scheduled worker run, cadence pass, and coach run is a fallback chain. The first attempt uses the entry that round-robin selects. When an attempt exits with a nonzero status, the loop must start the next entry of the list at once, with no wait between attempts. The chain ends when an attempt succeeds, or when every entry of the list has started once in this chain. A timeout must end the chain with no further attempt. The loop must check for a stop request before each attempt, and a stop request must end the chain. Every attempt of one chain must cover the same work: the same worker iteration, the same unreviewed commits captured at pass start, or the same coach cadence step. A later attempt must read the live tree as it is, including changes that an earlier attempt left. Each attempt is one invocation under the log, invocation line, cost, and profile-identification rules. A coverage record under **CV-REV-20** must use the profile of the successful attempt. A chain with no successful attempt is a failed run of its role.
- **CV-HARN-25**: Vote panels must resolve profiles through `CONVERGE_REVIEW_PANEL_PROFILE`, then `CONVERGE_REVIEWER_PROFILE`, then `claude:opus`. Their merge profile list must come from `CONVERGE_REVIEW_PANEL_MERGE_PROFILE`, or the first resolved panel profile alone when unset. Panel profile validation, retirement, and merge fallback rules follow `docs/review-panel-requirements.md:RP-PROF-2` through `RP-PROF-13`. These settings belong to the session under **CV-HARN-13**. Panel and merge invocations must not advance any normal role rotation.
- **CV-HARN-26**: The fixer must select its profile list from `CONVERGE_FIXER_PROFILE`. The list follows **CV-HARN-17**, the validation of **CV-HARN-19**, and the session snapshot of **CV-HARN-13**. An empty value is an error. The startup panel must show the fixer list under **CV-HARN-15**, or must say that the fixer uses the worker list when the variable is unset.
  - **CV-HARN-26.1**: When the variable is set, a fixer iteration is a fallback chain under **CV-HARN-24** over the fixer list, in its own round-robin order under **CV-HARN-23**. It must not advance the worker rotation.
  - **CV-HARN-26.2**: When the variable is unset, a fixer iteration is a normal worker chain over the worker list. It advances the worker rotation. The loop must still mark the iteration as a fixer under **CV-OUT-15**. An operator who sets no fixer list still gets the guidance that the escalation produced.

## Background operation

The operator starts a session over a connection that can break, and the session survives the loss of the terminal.

- **CV-BG-1**: The client must run the loop in a process that has no controlling terminal and its own process group. A closed terminal or a lost connection must not stop the loop.
- **CV-BG-2**: The client must start a loop only when no loop runs for the run directory. In all other cases it must attach to the loop that runs. A call with `--foreground` is the exception: it must report the error and exit, as **CV-BG-10** gives.
- **CV-BG-3**: To attach again, the operator runs `converge` again in the same run directory. The client must need no argument for this.
- **CV-BG-4**: One run directory must never have two loops. The test for a running loop must be a lock that the operating system releases when the loop dies. A file that a dead loop leaves behind must not block a new run.
- **CV-BG-5**: The client must write the output of the loop to the terminal:
  - **CV-BG-5.1**: When the client starts the loop, it must show the output from the first line.
  - **CV-BG-5.2**: When the client attaches to a loop that runs, it must first show the last screen of earlier output, then a rule that gives the start time of the loop and the current iteration, then the new output.
- **CV-BG-6**: When the operator gives options to a client that attaches, the client must keep the options of the running loop and must print a warning that it ignored the options.
- **CV-BG-7**: Before the client starts a new loop, it must give one line about the result of the last session, when a last session exists.
- **CV-BG-8**: Ctrl-C must stop the session in two steps, so that one keypress does not throw away the work of an iteration:
  - **CV-BG-8.1**: The first Ctrl-C must stop new agent launches and let active invocations finish. The client must print one prominent message in bold white text. The message must say that active invocations can finish and that a second Ctrl-C stops the session at once.
  - **CV-BG-8.2**: The second Ctrl-C must stop the loop and every agent below it at once.
  - **CV-BG-8.3**: In both cases the client must show the closing report of the loop and exit with status 130.
- **CV-BG-9**: The client must exit with the status of the loop.
- **CV-BG-10**: `--foreground` must run the loop in the terminal, for a person who debugs the loop. The lock still applies. When a loop already runs for the run directory, `--foreground` must report the error and exit. It must not attach, and **CV-BG-6** does not apply.
- **CV-BG-11**: Two loops may run at the same time in two run directories of one repository. Each loop commits to the shared repository, and no lock of the loop spans the repository. A worker of one loop can therefore meet an error from git when a worker of the other loop holds a lock of the repository. The worker prompt tells the worker to wait and to try the commit again, as **CV-ITER-3.13** gives.

## Iteration behavior

- **CV-ITER-1**: Before each iteration, the loop must print one line to stdout with the iteration number and the current time.
- **CV-ITER-2**: Each iteration runs one worker as a non-interactive harness invocation with permission prompts disabled.
- **CV-ITER-3**: The worker prompt must instruct the worker to:
  - **CV-ITER-3.1**: Survey the current repository state with fresh eyes.
  - **CV-ITER-3.2**: Retired. Required each unscoped worker to find requirements. **CV-ITER-3.14** replaces this behavior.
  - **CV-ITER-3.3**: Run `cbugs list --kind code --kind task --status open` and read the open code bugs and the open tasks.
  - **CV-ITER-3.4**: Fix these bugs before it starts work that the requirements name but no bug names. A defect in the code that exists is worth more than a feature that does not, and a task is work that an operator asked for.
  - **CV-ITER-3.5**: Read the citations of a bug with `cbugs show`, and read the requirement that a citation names. The citation says which requirement the fix must meet.
  - **CV-ITER-3.6**: Close each bug that it fixes, with `cbugs close`, and say in the note what it changed.
  - **CV-ITER-3.7**: Do a task in a way that no requirements document contradicts. A change that contradicts a document is a spec bug: log it, and do not make the change.
  - **CV-ITER-3.8**: Select one chunk of work that moves the project toward the requirements, when no open code bug and no open task remain. The chunk must be small enough to complete in one iteration. The chunk must be large enough to be a meaningful step, not a myopic one.
  - **CV-ITER-3.9**: Implement the chunk.
  - **CV-ITER-3.10**: Commit logical changes with clear messages.
  - **CV-ITER-3.11**: Not create plan documents, roadmap documents, or task lists that persist between iterations.
  - **CV-ITER-3.12**: Not work on a spec bug, and not wait for one. The operator resolves a spec bug.
  - **CV-ITER-3.13**: When a commit fails because another process holds a lock of git, wait and try the commit again. A second loop can run in a second run directory of the same repository, as **CV-BG-11** gives.
  - **CV-ITER-3.14**: Read the current requirements selected by explicit scope paths or the session's lookup instructions. Apply **CV-SCOPE-10** through **CV-SCOPE-15**.
  - **CV-ITER-3.15**: Close a bug when the code meets the requirements that its citations name. A gap that the worker finds while it fixes a bug, and that the citations do not name, is a new bug: log it with its own citation, and do not keep the first bug open for it. A bug that stays open for work its citations do not name has no end.
- **CV-ITER-4**: The worker prompt must tell the worker that it may log a bug with `cbugs add`, and must not urge it to. A worker that finds a defect it will not fix in this iteration has somewhere to put it. A worker that hunts for defects is not doing the work of a worker.
- **CV-ITER-5**: Retired. Described citations with local path syntax only. **CV-ITER-9** replaces this requirement.
- **CV-ITER-6**: If the guidance file exists and is not empty, the loop must include its content in the worker prompt.
- **CV-ITER-7**: The loop must not change git state. Workers own all commits. The loop may read git state to report what an iteration changed.
- **CV-ITER-8**: Every worker instruction that reads or acts on open bugs must use
  the cbugs visibility and current-state rules at repository `HEAD`. A hidden bug
  must not count as current worker work.
- **CV-ITER-9**: The worker prompt must instruct the worker to cite the original requirement source for each bug it logs. Citations must follow **CV-SCOPE-15**.
- **CV-ITER-10**: A fixer iteration is a worker iteration. It must use the worker prompt of **CV-ITER-3**, with the guidance of **CV-ITER-6**, and one additional line before the guidance. The line must say that earlier workers could not finish the work that the guidance names, and that this iteration runs on a more capable profile for one iteration only. This wording is required even when the fixer uses the worker list under **CV-HARN-26.2**. The iteration counts toward the worker limit, the coach cadence, the done votes, the blocked votes, and the stall count, exactly as a worker iteration does. One escalation gives one fixer iteration. The iteration after it is a normal worker iteration.

## The environment of an agent

- **CV-ENV-1**: Retired. Listed roles without discovery. **CV-ENV-7** replaces this requirement.
- **CV-ENV-2**: Retired. Required an iteration number for every loop agent. **CV-ENV-8** replaces this requirement.
- **CV-ENV-3**: The bug tracker reads both variables and records them on each revision that an agent writes. An agent therefore cannot record the wrong role, and a prompt does not have to carry the values. The bug tracker also reads and records the pass id of **CV-ENV-10**.
- **CV-ENV-4**: The loop must put `bin/cbugs` on the PATH of every agent that it starts. A worker that cannot run the command cannot fix a bug.
- **CV-ENV-5**: The loop must start every agent with the run directory as its working directory. A scope path, a requirements document, and the bug database therefore resolve for the agent as they resolved for the operator.
- **CV-ENV-6**: The loop must export `CONVERGE_RUN_DIR` into the environment of every agent that it starts. The value is the absolute path of the run directory. An agent that changes its own working directory therefore still reads and writes the bugs of its own run, and never the bugs of another run directory that it moved into. The bug tracker reads the variable, as `docs/cbugs-requirements.md` gives.
- **CV-ENV-7**: Retired. Listed roles without Refactor. **CV-ENV-11** replaces this requirement.
- **CV-ENV-8**: The loop must export the current worker iteration as `CONVERGE_ITERATION` for workers, cadence reviewers, and coaches. Startup reviewers and coaches must receive `0`. Discovery must run with this variable unset.
- **CV-ENV-9**: A fixer iteration must export `CONVERGE_ROLE` as `worker` and `CONVERGE_ITERATION` as its iteration number. A fixer does the work of a worker, and the bug tracker must record it as one. The run log, the invocation line, and the prompt file identify the iteration as a fixer, as **CV-OUT-15** gives.
- **CV-ENV-10**: For each cadence pass, the loop must make one pass id. The id must be unique across sessions. The loop must export it as `CONVERGE_REVIEW_PASS` for each reviewer of that pass, and for each attempt of its fallback chain. The bug tracker records the id on each revision that the reviewer writes, as `docs/cbugs-requirements.md:CB-PROV-9` gives. The loop must not export the variable for any other agent: workers, fixers, coaches, discovery, and the agents of the vote panel run with it unset. A notification command must also run with it unset. A value that the environment of the loop holds at startup must reach no agent.

- **CV-ENV-11**: The loop must export `CONVERGE_ROLE` for each agent it starts. Its value must be `discovery`, `worker`, `reviewer`, `coach`, or `refactor`, as applicable. Fixers follow **CV-ENV-9**. A Refactor invocation must receive the current worker iteration as `CONVERGE_ITERATION`. It must not receive `CONVERGE_REVIEW_PASS`.

## Output

- **CV-OUT-1**: The loop must print its progress in a form that an operator can scan:
  - **CV-OUT-1.1**: A panel at startup with the run settings and the paths that an operator reads. A path inside the home directory appears as a `~/` path.
  - **CV-OUT-1.2**: A heading for each iteration, for each review pass, and for each coach run.
  - **CV-OUT-1.3**: One line for each invocation that starts, with the role and the model. For a worker, this line also gives the log file.
  - **CV-OUT-1.4**: One line for each result: the duration, a done vote with its count, a timeout, an error, or a wait.
  - **CV-OUT-1.5**: A closing report with the result and the total duration of the session.
  - **CV-OUT-1.6**: The count of the unreviewed commits at startup. The operator must see whether a review pass runs before the first worker.
- **CV-OUT-2**: The loop must show a transcript of each invocation while the invocation runs. The operator must not wait for the end of an iteration to see what the agent does.
- **CV-OUT-3**: The transcript must show, in the order that they happen:
  - **CV-OUT-3.1**: The text that the agent writes between its tool calls.
  - **CV-OUT-3.2**: One line for each tool call, with the tool and its main argument. The transcript must make a tool call that changes a file easy to see. It must show a shell command as the agent wrote it.
  - **CV-OUT-3.3**: A shell command that has more than one line must stay on that one line. The loop must join the lines, and must show a mark where each line break was. The operator must see the full command when it is short enough, and must not read a first line that looks complete when it is not.
  - **CV-OUT-3.4**: If a tool-call line is too wide, the loop must shorten it and must show that it shortened it. If the loop shortens a shell command that has more than one line, it must also give the number of lines that the command has, because the shortened text can hide a line break.
  - **CV-OUT-3.5**: One line for each tool call that fails, with the cause.
  - **CV-OUT-3.6**: The final message of the agent, set apart from the rest.
  - **CV-OUT-3.7**: The number of turns, the duration, and the cost that the agent reports.
- **CV-OUT-4**: After each worker, the loop must report what the worker committed: the number of commits, the number of files and lines that changed, and the subject of each commit. The loop must also report files that the worker left uncommitted.
- **CV-OUT-5**: After each review pass, the loop must report each bug that the pass logged, with its id, its kind, and its title. It must report a pass that logged no bug as such.
- **CV-OUT-6**: Retired. Limited bug-list reads to reporting. **CV-OUT-18** retains reporting, in place of the retired **CV-OUT-13**; **CV-CONV-31** forbids convergence decision checks.
- **CV-OUT-7**: After each coach run, the loop must report whether the coach changed the guidance. If the coach changed it, the loop must show the new guidance in full. In both cases the loop must give the path of the guidance file. The loop must not give the path of the coach log, which a person cannot read.
- **CV-OUT-8**: If an invocation fails, the loop must show the last lines that it wrote to stderr. A failure with no messages puts its cause there.
- **CV-OUT-9**: The loop must always use color, bold, and box characters. It writes to a file that a client shows in a terminal, so it cannot ask what reads it.
- **CV-OUT-10**: The loop has no terminal of its own. The client must give it the width of the terminal.
- **CV-OUT-11**: Style must not remove information. Each message that the loop prints must also go to the run log, as plain text.
- **CV-OUT-12**: After each review pass, the loop must report the number of commits that the pass recorded. The vote panel report must say that the panel read the live working tree.

- **CV-OUT-13**: Retired. Found the bugs of a cadence pass by a comparison of the bug lists before and after the pass. **CV-OUT-18** replaces it.
- **CV-OUT-14**: Retired. Gave the visibility of the two lists of **CV-OUT-13**. **CV-OUT-18** reads no list before the pass, and a change of `HEAD` cannot change the bugs of a pass id. This requirement therefore has no remaining purpose.
- **CV-OUT-15**: The heading and the invocation line of a fixer iteration must say that the iteration is a fixer. The run log must record it. The result line of a worker must show a blocked vote with its count, as **CV-OUT-1.4** shows a done vote. The startup panel must show the blocked threshold beside the vote threshold, and the stall threshold beside the coach cadence.
- **CV-OUT-16**: After each coach run, the loop must report whether the coach escalated. After a coach run that the loop started for a blocked vote or a stall, the heading must name that trigger.
- **CV-OUT-17**: When the loop stops on blocked votes, the closing report must say that the loop stopped blocked, give the count of consecutive blocked votes, and show the final message of the last blocked worker in full, set apart. That message names the blockers. The operator must read why the loop stopped without a search of the logs.
- **CV-OUT-18**: The loop must find the bugs of a cadence pass by the pass id of **CV-ENV-10**.
  - **CV-OUT-18.1**: After the pass, the loop must read the bugs with `cbugs list --review-pass <id> --json`, as `docs/cbugs-requirements.md:CB-LIST-10` gives. The bugs of the pass are the bugs that its reviewers created. A note that a reviewer adds to an existing bug does not make that bug a bug of the pass. A bug that another role or the operator logs during the pass is not a bug of the pass.
  - **CV-OUT-18.2**: The report must include a bug of the pass that the repository `HEAD` hides, and must mark it as hidden.
  - **CV-OUT-18.3**: When the read fails, the loop must warn that it cannot report the bugs that the pass logged. It must not report that the pass logged no bug.
  - **CV-OUT-18.4**: The loop must read the bug database only through `cbugs`.
  - **CV-OUT-18.5**: Vote panel reports must use panel attribution under `docs/review-panel-requirements.md`. Bug queries serve reporting, not convergence decisions.

## Cost tracking

- **CV-COST-1**: The loop must track recorded cost for each worker, reviewer, and coach invocation. It must use the harness total, or the cost computed from the message stream under **CV-HARN-21**, without counting the same cost twice. A cost is absent when neither source supplies cost data. The loop must not treat absent cost as a recorded zero.
- **CV-COST-2**: Session spend must be the sum of recorded invocation costs for one loop session. It must include startup invocations and invocations that fail, time out, or stop, when they have recorded cost. An attached client must not start a new cost session or count costs again.
- **CV-COST-3**: The average cost for each role must be its recorded spend divided by its number of invocations with recorded cost. An explicit recorded zero must count as one sample. An invocation with no recorded cost must not count as a sample. Each reviewer invocation must count separately, including a startup review. Worker iteration counts must not serve as the divisor for reviewer or coach averages.
- **CV-COST-4**: Cumulative costs must include the current session and saved costs from all prior sessions for the same absolute run-directory path, under **CV-ID-1** and **CV-ID-3**. Cumulative role averages must use total recorded role spend divided by total recorded samples for that role, not an average of session averages. Cost history must start with sessions that use this feature. The loop must not import costs from older session logs.
- **CV-COST-5**: Cost history must identify an agent profile by its canonical `harness:model[:effort]` under **CV-HARN-17**. It must combine that profile's spend across roles and sessions. Changes to other settings must not create a separate cost identity. Omitted effort remains omitted in the identity, even if the harness default changes. Cost history must not select profiles for a later session.
- **CV-COST-6**: The closing report must include a cost summary on every graceful session exit. This includes convergence, the iteration limit, and the stop after the first Ctrl-C. A second Ctrl-C, SIGTERM under **CV-FAIL-9**, a crash, or a forced kill does not require a cost summary. The closing-report requirements elsewhere in this document still apply.
- **CV-COST-7**: The cost summary must be a table with exactly three columns: label, session cost, and cumulative cost. It must contain these rows in order:
  - **CV-COST-7.1**: Total spend.
  - **CV-COST-7.2**: Average cost per worker invocation, per reviewer invocation, and per coach invocation, in separate rows.
  - **CV-COST-7.3**: Spend per agent profile used by at least one started invocation in the current session, in separate rows. The first column must identify the full canonical profile. Profiles must not become column headers. A profile configured but not used in the current session must have no row. A profile used only in prior sessions must have no row, but its costs and samples must remain in cumulative totals and role averages.
- **CV-COST-8**: The table must show costs in USD. It must use enough decimal places to distinguish a small nonzero cost from zero. Exact decimal formatting is not prescribed. An average with no recorded samples must show `—`. A spend cell with no recorded costs must also show `—`. An explicit recorded zero must show zero. The summary must show recorded costs only, without a warning about absent costs.
- **CV-COST-9**: On every graceful session exit, the loop must save enough cost history in the state directory to produce later cumulative summaries. Saving costs during a session is optional. A crash, a second Ctrl-C, or another immediate stop may lose that session's costs. Costs saved before such a stop must count in later summaries. Each cost and sample must count at most once, including after a client attaches again or a session ends. Shared panel cost records must follow **CV-COST-10**. Prefer a simple implementation over additional recovery behavior.
- **CV-COST-10**: The parent loop must pass its existing `CONVERGE_SESSION` and an explicit absolute `CONVERGE_COST_LEDGER` path to each vote panel. The panel must record each reviewer and merge invocation once under the shared ledger lock. The ledger must use the existing TSV fields: session, role, canonical profile, and cost. Panel reviewers use the reviewer cost role; merge invocations use a distinct merge cost role. Parent totals must include these records, not an additional panel total. Unknown costs must remain absent, not zero. Failed invocations must retain available costs. Hard stops may omit unfinished invocations. Standalone panels must use their own cost session and path, as `docs/review-panel-requirements.md` gives.
- **CV-COST-11**: Each started discovery invocation must record available cost once under the distinct `discovery` role. Its cost must follow the normal absent-cost and history rules. It must enter session totals, cumulative totals, and profile spend. It must not enter worker invocation averages.
- **CV-COST-12**: Each started fixer invocation must record available cost once under the distinct `fixer` cost role, whether the fixer list or the worker list supplied its profile. It must enter session totals, cumulative totals, and profile spend. It must not enter worker invocation averages. The cost table must hold a row for the average cost per fixer invocation after the coach row of **CV-COST-7.2**. A session with no fixer invocation shows `—` in that row, as **CV-COST-8** gives.

## Convergence and stopping

- **CV-CONV-1**: The worker prompt must instruct the worker: do not vote done while an open code bug or an open task exists. If you judge that the repository satisfies the requirements documents of the scope, no open code bug and no open task remain, and no work remains, write the exact token `CONVERGED` on a line of its own in your final message, and do no work.
- **CV-CONV-2**: The loop must read only the worker's final message to detect the token. This is a done vote.
- **CV-CONV-3**: The loop must count the token only when it is alone on a line. Space before or after the token does not matter. The loop must ignore the token inside a line of text. This lets a worker name the token, or quote this document, without a vote.
- **CV-CONV-4**: Retired. Required a pass after every done vote. See **CV-CONV-16**.
- **CV-CONV-5**: Retired. Reviewed only pending commits on a done vote. See **CV-REV-18** and **CV-CONV-16**.
- **CV-CONV-6**: Retired. Allowed consensus of one to bypass final review. **CV-CONV-14** replaces this behavior.
- **CV-CONV-7**: Retired. Read no signal from the bug database. See **CV-CONV-17**.
- **CV-CONV-8**: Retired. Required only consecutive votes for convergence. **CV-CONV-14** replaces this behavior.
- **CV-CONV-9**: Any iteration that does not produce a done vote must reset the done count to zero. This includes failures and timeouts.
- **CV-CONV-10**: The loop must exit with status `0` on convergence and with a non-zero status in all other cases.
- **CV-CONV-11**: Retired. Required pending commits for final review and bypassed it at consensus. **CV-CONV-16** replaces this behavior.
- **CV-CONV-12**: Retired. Relied on later workers to reset votes after review findings. **CV-CONV-33**, **CV-CONV-26**, and **CV-REF-22** define vote resets and a live-tree panel.
- **CV-CONV-13**: Retired. Forbade bug queries for decisions. **CV-CONV-31** now forbids blocking-bug checks.
- **CV-CONV-14**: Retired. Required votes, no open bugs, and HEAD approval. **CV-CONV-21** replaces this behavior.
- **CV-CONV-15**: Retired. Defined session approval of a directory HEAD. **CV-CONV-31** removes approval.
- **CV-CONV-16**: Retired. Scheduled final passes by HEAD approval. **CV-CONV-33** schedules vote panels.
- **CV-CONV-17**: Retired. Used bug counts and review failures to reset votes and block convergence. **CV-CONV-31** forbids these checks.
- **CV-CONV-18**: Retired. Defined agent order with approval checks and a limit on final passes. **CV-CONV-25** replaces this order.
- **CV-CONV-19**: Retired. Defined visibility for blocking-bug counts. **CV-CONV-31** removes these counts.
- **CV-CONV-20**: Retired. Refreshed blocking-bug counts after HEAD changes. **CV-CONV-31** removes these counts.
- **CV-CONV-21**: Retired. Reset the vote count on every failed worker invocation. **CV-CONV-26** replaces this behavior.
- **CV-CONV-22**: Retired. Required unchanged vote counts after all HEAD changes. **CV-CONV-31** replaces this rule.
- **CV-CONV-23**: Retired. Started the vote panel before Refactor. **CV-CONV-33** replaces this rule.
- **CV-CONV-24**: Retired. Defined startup order without discovery. **CV-CONV-25** replaces this order.
- **CV-CONV-25**: Retired. Defined the agent order without blocked votes, stalls, or fixers. **CV-CONV-34** replaces this order.
- **CV-CONV-26**: Convergence requires only `N` consecutive done votes from successful worker chains. The vote of a chain comes from its successful attempt. A failed attempt in a chain that later succeeds must not reset the count. A chain with no successful attempt, or a timed-out worker, cannot vote and must reset the count to zero. A worker non-vote must reset the count to zero. The default `N` is `2`. With `N` equal to `0`, the loop must converge without starting any agent.
- **CV-CONV-27**: The worker prompt must instruct the worker on the blocked vote. A worker that cannot vote done and cannot work has no honest answer without it, and it spins.
  - **CV-CONV-27.1**: Write the exact token `BLOCKED` on a line of its own in the final message only when no open code bug and no open task that the worker can do remain, and every remaining piece of work is stopped by a blocker.
  - **CV-CONV-27.2**: Before it reports a spec blocker, log the spec bug with `cbugs add --kind spec` when no open spec bug names it. A blocker that no record holds is a blocker that the operator cannot see.
  - **CV-CONV-27.3**: Name each blocker in the final message: the id of the spec bug, or the tool or resource that the worker cannot reach, and the work that it stops.
  - **CV-CONV-27.4**: Do no work in an iteration that votes blocked. A worker that did work reports the work; the next iteration finds what remains.
  - **CV-CONV-27.5**: Not vote blocked because the work is hard. A blocker is outside the worker; a hard task is not. The coach judges the difference, as **CV-COACH-14** gives.
- **CV-CONV-28**: The loop must read only the final message of a worker to detect the token `BLOCKED`, under the same line rule as **CV-CONV-3**. The vote of a chain comes from its successful attempt. A failed chain and a timed-out worker cannot vote blocked. A final message that holds both `CONVERGED` and `BLOCKED` alone on lines is a non-vote: it gives no done vote and no blocked vote. The loop must not query bugs to verify a blocked vote, as **CV-CONV-31** gives for done votes.
- **CV-CONV-29**: The loop must count consecutive blocked votes.
  - **CV-CONV-29.1**: A blocked vote adds one to the blocked count and resets the done count to zero.
  - **CV-CONV-29.2**: A done vote, a non-vote, a chain with no successful attempt, and a timed-out worker reset the blocked count to zero.
  - **CV-CONV-29.3**: A coach run, a cadence pass, and a vote panel must not change the blocked count. The count must survive the coach run that a blocked vote starts, or the stop of **CV-CONV-29.4** never fires.
  - **CV-CONV-29.4**: When the blocked count reaches `N` of `--blocked`, the loop must stop and exit with status `3`. This is a stop without convergence. Status `3` tells a script that the work waits on a decision of the operator, and not on more iterations.
  - **CV-CONV-29.5**: With `--no-coach`, blocked votes still count, and the stop still applies. No coach runs between them.
- **CV-CONV-30**: Retired. Defined the agent order without Refactor. **CV-CONV-34** replaces this order.
- **CV-CONV-31**: The loop must not query bugs to decide convergence or to change the done count or the blocked count. Bugs that a review files, review failures, merge failures, and coverage-record failures must not change the done count or the blocked count, or block convergence. HEAD changes must not change either count, except for tracked code changes made during a Refactor pass under **CV-REF-22**. The loop must require no HEAD or snapshot approval. Worker bug instructions and bug reporting still apply.
- **CV-CONV-32**: Retired. Defined Refactor scheduling by commit count only. **CV-CONV-34** replaces this order.
- **CV-CONV-33**: With review enabled, each change of the done count from zero to one must make one vote panel pending under `docs/review-panel-requirements.md`. The loop must first handle the done-vote Refactor trigger under **CV-REF-23**. If Refactor clears the done count, cancel the pending panel. Otherwise start it. A failure, timeout, or skipped Refactor pass with no tracked code change must not prevent the panel. The loop must start the panel in its run directory and pass its requirements scope and timeout. The panel must review the whole live working tree in parallel, then merge duplicate new bugs under the existing panel merge rules. It must skip the merge when it creates no new bug. The loop must wait for the panel and any merge before the next worker or a convergence exit. With `--consensus 1`, the panel must still run before success. Its result is advisory. With `--no-review`, neither a cadence pass nor a vote panel runs.
- **CV-CONV-34**: The loop must use this order:
  1. Before the first worker, stop on a signal, convergence, or a zero worker limit. Otherwise perform discovery when required. Stop if discovery fails. Then run any due startup cadence pass, followed by any due coach.
  2. After each worker chain, count its iteration. Apply **CV-CONV-26** to its done vote, **CV-CONV-29** to its blocked vote, and **CV-COACH-11** to its stall count.
  3. Stop on an operator signal. Otherwise handle each worker done vote with one Refactor pass under **CV-REF-23**. Then run any pending vote panel under **CV-CONV-33** if the vote still stands.
  4. Check signals again. Then stop with convergence if the done count is sufficient. Otherwise stop blocked if the blocked count is sufficient. Otherwise stop without convergence if the worker limit is reached.
  5. If not stopped, run a due cadence pass, then a due coach, then a due `stalled` notification under **CV-NOTIFY-11**, then a due cadence Refactor pass, then the next worker. Do not run a second Refactor pass here if step 3 already handled a Refactor trigger after this worker. After a Refactor pass, check for a due cadence pass again before the next worker. The coach is due by cadence, by a blocked vote, or by a stall, as **CV-COACH-11** through **CV-COACH-13** give. The next worker runs as a fixer when an escalation is pending, as **CV-COACH-15** gives. Check signals before each new invocation.
  The iteration limit counts workers only. A done vote on the last permitted worker iteration must still get its Refactor trigger before the limit check. If Refactor changes tracked code, clear the votes and stop at the worker limit without convergence. Otherwise a first done vote must still get its panel and any required merge. A blocked vote on the last permitted iteration gets no coach: the limit stops the loop at step 4. A stop request forbids all new invocations, including a merge that has not started. Review errors must not skip a due coach unless a stop condition holds.

## Reviewer

The worker builds. The reviewer reads what the worker built. One agent cannot do both well, because a worker that judges its own work is the author of that work.

- **CV-REV-1**: Retired. A pass ran after every `R` worker iterations. **CV-REV-19** replaces this behavior: the count of unreviewed commits starts a pass, and not a count of iterations.
- **CV-REV-2**: Retired. The loop ran no pass when no commit had arrived since the previous one. **CV-REV-19** replaces this behavior: a commit that no pass recorded is unreviewed, and no unreviewed commit means no cadence pass. **CV-CONV-33** governs vote panels.
- **CV-REV-3**: Retired. Every pass reset the count of iterations since the last pass. **CV-REV-19** replaces this behavior: no iteration count remains.
- **CV-REV-4**: The reviewer runs as a non-interactive harness invocation with permission prompts disabled, on the reviewer model.
- **CV-REV-5**: Retired. The state directory held the commit of the last pass, and the next pass read the range from it. **CV-REV-15** replaces this behavior: the bug database holds every commit that a pass covered, and it survives the death of the loop.
- **CV-REV-6**: Retired. The prompt gave the reviewer the range of the pass. **CV-REV-16** replaces this requirement, and **CV-REV-18** gives the range of a final pass.
- **CV-REV-7**: Retired. The first pass read the whole history. **CV-REV-17** replaces this requirement.
- **CV-REV-8**: The reviewer prompt must instruct the reviewer to:
  - **CV-REV-8.1**: Retired. Defined requirements reads without discovery. **CV-REV-8.8** replaces this requirement.
  - **CV-REV-8.2**: Run `cbugs search` before it logs a bug, and log nothing that an open bug already names.
  - **CV-REV-8.3**: Log a code bug with `cbugs add --kind code` for each defect in the code: a behavior that contradicts a requirement, a case that the code does not handle, or a change that broke something that worked.
  - **CV-REV-8.4**: Retired. Described citations with local path syntax only. **CV-REV-8.7** replaces this requirement.
  - **CV-REV-8.5**: Log a spec bug with `cbugs add --kind spec` when the changes reveal that a requirement is ambiguous, absent, or in conflict with another. The report must say what the reviewer could not decide, and why the changes raised the question. Cite each document and requirement that raised the question.
  - **CV-REV-8.6**: Log nothing when it finds nothing. A pass that finds no defect is a normal result, and an invented defect costs a worker a whole iteration.
  - **CV-REV-8.7**: Cite the violated requirement's original source on every code bug, under **CV-SCOPE-15**. If no requirement can be named, consider a spec bug instead of a code bug.
  - **CV-REV-8.8**: Read each relevant commit in full. Focus on changes in the run directory. Read current requirements through the explicit scope or accepted lookup text. Judge the code against those requirements. Apply **CV-SCOPE-10** through **CV-SCOPE-15**.
- **CV-REV-9**: The reviewer must log a defect that it finds, and must not fix it. A reviewer that edits code becomes a worker with no memory of the requirements it was reading.
- **CV-REV-10**: The reviewer must not edit code, must not edit requirements documents, must not write the guidance file, and must not stop the loop. It writes bugs, and nothing else.
- **CV-REV-11**: The reviewer must not close a bug. It did not do the work that a close records.
- **CV-REV-12**: The reviewer must not log a task. Only an operator directs that record. The command refuses one from an agent of the loop, and the prompt must say so.
- **CV-REV-13**: The loop must log reviewer output the same way it logs worker output.
- **CV-REV-14**: Retired. Defined cadence scheduling with a strict greater-than threshold. **CV-REV-19** and **CV-CONV-25** replace this behavior.
  - **CV-REV-14.1**: Retired. See **CV-REV-19** for count timing.
  - **CV-REV-14.2**: Retired. See **CV-INV-3.14** for the threshold.
  - **CV-REV-14.3**: Retired. See **CV-REV-19** for commit identity.
  - **CV-REV-14.4**: Retired. See **CV-CONV-25** for agent order.
- **CV-REV-15**: After a review pass ends with success, the loop must record, as reviewed commits, the unreviewed commits captured when this pass started. The bug tracker holds the reviewed commits, as `docs/cbugs-requirements.md` gives. The loop must record no commit that became relevant during the pass: a relevant commit that a second loop wrote while the pass ran stays unreviewed. The loop records, and the reviewer records none. The loop must read no file of the state directory to learn what a pass covered, and must ignore the file of the last pass that an earlier version of the script wrote.
- **CV-REV-16**: The prompt of a cadence pass must give the reviewer every unreviewed commit in the history that `cbugs reviewed pending` considers. The prompt must identify the run directory as the focus of the review. The threshold decides when a pass runs, and not how much of the considered history it reads. The reviewer needs no memory and no query to learn what it has already read.
- **CV-REV-17**: When the bug database records no reviewed commit, the range of a cadence pass is every relevant commit in the history that `cbugs reviewed pending` considers. The reviewer must judge how far back to read, and the prompt must tell it that the recent commits matter most. The pass records every commit that it covered, whatever the reviewer judged, as **CV-REV-15** gives.
- **CV-REV-18**: Retired. Required whole-code final review at the directory HEAD. **CV-CONV-33** requires a live-tree vote panel instead.

- **CV-REV-19**: With review enabled, the loop must count unreviewed commits before the first worker and after each worker. A cadence pass is due when the count is at least `--review-after`. It must run synchronously under **CV-CONV-34**. A startup pass follows iteration 0. Each commit in the history that `cbugs reviewed pending` considers is unreviewed when it has no coverage record, regardless of its author. A commit that changes no path in the run directory is not an unreviewed commit. A commit outside the considered history is not an unreviewed commit. A new hash after a rebase or amendment is a new commit when it is in the considered history. Any coverage record is sufficient; no profile-specific or multiple-review count is required. No unreviewed commit means no cadence pass, but does not prevent a vote panel. Panel and merge invocations must not advance the cadence. Panel coverage records remain subject to the panel coverage rules; a later unreviewed-commit count must use those records.
- **CV-REV-20**: For each successful pass, the loop must supply its selected canonical reviewer profile and one successful completion timestamp to the bug tracker's coverage-record operation. It must use that same profile and timestamp for all commits covered by the pass. Cadence passes must record only commits pending at pass start, as **CV-REV-15** gives. Vote panels must use the coverage rules in `docs/review-panel-requirements.md`. Coverage grants no approval. The record interface accepts profile and timestamp inputs as `docs/cbugs-requirements.md` defines. This adds no profile or timestamp provenance to bug revisions.
- **CV-REV-21**: Reviewer duplicate searches must use normal cbugs visibility at
  repository `HEAD`. A hidden historical bug must not prevent the reviewer from
  recording a defect that exists in the current code.
- **CV-REV-22**: Cadence counts and prompts must use the considered history
  selected under `docs/cbugs-requirements.md:CB-RVW-20` through `CB-RVW-24`.
  The prompt must identify this history as the review boundary. This rule must
  apply to the first pass and every later pass. The first-pass discretion of
  CV-REV-17 must not extend the review beyond this boundary. The first pass
  must receive the selected commit list under CV-REV-16. The loop must not
  count, request review of, or record coverage for commits outside the
  considered history captured at pass start. CV-REV-15 still governs coverage
  after a successful pass. Vote panels must continue to review the whole live
  working tree under CV-CONV-23.

## Refactor

- **CV-REF-1**: A new loop session must capture the repository HEAD as its session start commit before any agent starts. An attached client must keep that boundary. A new session must select a new boundary. The boundary and the Refactor commit count must not select work in a later session. Invocation logs may retain both boundaries. When no commit exists, Refactor must remain unavailable for that session. The loop must report why.
- **CV-REF-2**: Before each due Refactor pass, the loop must capture HEAD as the pass start commit. The session start commit must be an ancestor of that commit. If the loop cannot establish the range, it must skip the pass and report why. It must not select a replacement session start commit. Every fallback attempt must receive the same captured range.
- **CV-REF-3**: The Refactor count starts at zero. It must count distinct relevant commits after the session start commit. Include worker and fixer commits, commits from failed attempts, and commits from other processes. Exclude commits made during Refactor attempts. Count commits, not worker iterations. Count only commits reachable from the current HEAD. Do not use review coverage or the unreviewed commit count.
- **CV-REF-4**: An enabled Refactor pass is due when the count since the last successful pass reaches `--refactor-after`. Run at most one pass at each scheduling point. Only a successful attempt can complete a pass successfully. A skipped attempt is not a success. A successful pass must reset the count, including a pass that makes no changes. Commits already present at that successful pass must not count again. The scope must still include the whole session difference. A failed or skipped pass must keep Refactor due. Before another pass, the loop must let a worker chain run. Stop conditions still apply.
- **CV-REF-5**: Before each Refactor attempt, including fallback attempts, the loop must check for staged and unstaged changes to tracked files. If either exists, it must skip the attempt and end the chain. A failed check must also end the chain. The loop must log the reason. Untracked files must not prevent an attempt. Ignored files must not prevent an attempt. A skipped attempt must consume no profile turn. The check belongs to the loop; the prompt needs no duplicate check.
- **CV-REF-6**: Refactor must use the resolved worker profile list. It must have its own session rotation under **CV-HARN-23**. It must not advance the worker or fixer rotation. No separate Refactor profile setting is required. Refactor must use each supported harness and its normal model and effort settings.
- **CV-REF-7**: A Refactor pass must use the fallback, timeout, signal, and failure rules of **CV-HARN-24**, **CV-FAIL-16**, and **CV-FAIL-18**, subject to **CV-REF-5**. Each attempt must read the live tree. A failure must not stop the session by itself. Each attempt must preserve available logs, results, and costs, including on failure.
- **CV-REF-8**: Retired. Gave all stop conditions priority over Refactor. **CV-REF-21** replaces this rule.
- **CV-REF-9**: Refactor commits must enter normal review history. They must not receive automatic coverage. After a Refactor pass, the loop must check the normal review threshold again. `--no-review` still disables review.
- **CV-REF-10**: The loop must show whether Refactor is enabled, its threshold, and its full profile list at startup. Each pass must have a heading. Each started attempt must have the normal invocation line, transcript, prompt file, and invocation log. Logs and prompts must identify both commit boundaries. The loop must report the changes and commits of a pass, including changes left by a failed or timed-out attempt.
- **CV-REF-11**: Retired. Defined vote resets without cancellation of a pending panel. **CV-REF-22** replaces this rule.
- **CV-REF-12**: Each started Refactor invocation must record available cost once under the distinct `refactor` role. Apply the normal absent-cost and history rules. Include the cost in session totals, cumulative totals, and profile spend. Exclude it from worker averages. Add an average cost per Refactor invocation row after the fixer row. Show `—` when no cost sample exists.
- **CV-REF-13**: The prompt must identify the agent as the Refactor agent for one session. It must supply the session start commit and the pass start commit. It must instruct the agent to improve the structure of changed code, preserve project behavior, and make one small, useful refactor. It must permit a no-change result when no change is justified.
- **CV-REF-14**: The prompt must require the agent to read applicable project instructions and the current selected requirements. Apply **CV-SCOPE-5**, **CV-SCOPE-10**, **CV-SCOPE-13**, **CV-SCOPE-14**, and **CV-SCOPE-15** to Refactor. Supply explicit scope paths or the session's accepted lookup instructions. If a required source or the commit range is unavailable, the agent must report the problem and make no changes.
- **CV-REF-15**: The prompt must require the agent to select work from the net difference between the session start commit and the pass start commit. It must require reading the commit list for intent, including earlier Refactor commits. Select code added or changed in that range. Change surrounding code only when the selected refactor requires it. Leave unrelated code unchanged, even in the same file. Untracked files are not part of the committed difference. Do not include unrelated files in a commit.
- **CV-REF-16**: Retired. Permitted selection by documented project rules without limiting those rules to coding standards. **CV-REF-24** replaces this rule.
- **CV-REF-17**: The prompt must require preservation of public interfaces, outputs, errors, side effects, and supported inputs. Preserve ordering and resource use where the project depends on them. Before removing code, check external callers, public entry points, configuration references, and calls selected at runtime. Leave code unchanged when safe removal cannot be established.
- **CV-REF-18**: The prompt must forbid feature work, defect fixes that change behavior, dependency upgrades, and unrelated formatting changes. It must forbid edits to requirements, project instructions, and coach guidance. It must forbid plans and task lists. It must forbid reversing an earlier refactor without new evidence and require an explanation of that evidence. It must forbid commits made only to show progress.
- **CV-REF-19**: The prompt must require existing tests to check behavior preservation. Add or change tests only when needed to check behavior affected by the refactor. Do not weaken checks or change expected results to accept a behavior change. Run required project checks and checks needed for the change. Inspect the final difference. Remove unnecessary changes and changes outside the permitted scope. Commit logical changes with a clear message.
- **CV-REF-20**: The prompt must leave defects that require behavior changes for workers. Before recording a defect, search `cbugs` for duplicates. Cite the original requirements source. Do not create tasks or record review coverage. The final message must state the change, its concrete benefit, the session changes that justified it, each necessary change outside the session difference, check results, and commit identifiers. A no-change result must state why.

- **CV-REF-21**: The loop must run Refactor synchronously under **CV-CONV-34**. Signals take priority over every Refactor trigger. Convergence and the worker limit take priority over cadence Refactor passes. A worker done vote must trigger Refactor before convergence and worker-limit checks. Refactor must not count toward the worker limit, coach cadence, worker stall count, or stall streak. A Refactor result must never supply a done vote, a blocked vote, or a coach escalation.
- **CV-REF-22**: If any attempt changes tracked code, the loop must clear both the done count and the blocked count before the next worker. This rule includes committed changes and uncommitted changes left by a failed or timed-out attempt. A pass that makes no tracked code change must preserve both counts. The loop must not treat failure alone as a code change. When tracked code changes, cancel any pending vote panel for the discarded vote. Return to worker scheduling without running that vote panel. Normal cadence review still applies. If no tracked code changes, keep the vote even when Refactor fails, times out, or is skipped. A later change of the done count from zero to one must make a new vote panel pending under **CV-CONV-33**.
- **CV-REF-23**: Each done vote from a successful worker chain must trigger one enabled Refactor pass before any pending vote panel and before convergence or worker-limit checks. This trigger must not require the commit threshold. It applies to every done vote, including votes after the first, and with `--consensus 1` or `--no-review`. A pass handles both triggers when the cadence is also due. Its success resets the commit count under **CV-REF-4**. Failure or skipping must not create an immediate retry. With `--no-refactor`, keep the normal vote, panel, and stop behavior. No successful Refactor result is required for convergence. A failure, timeout, skipped pass, unavailable session boundary, or invalid range must not block a standing vote when Refactor made no tracked code change. Existing tracked changes that caused a skip must not be attributed to Refactor.

- **CV-REF-24**: The prompt must direct the agent to look for code that the session made unnecessary, structure or names that make changed code difficult to understand, and violations of documented coding standards. Coding standards cover naming, structure, style, and use of language features. Each change must have a concrete benefit. Personal preference alone is insufficient. Cite the documented coding standard that justifies the change. Product requirements and feature requests must not justify Refactor work. Project instructions and requirements constrain the work. They must not expand the role beyond refactoring code while preserving behavior.

## Coach

- **CV-COACH-1**: Retired. Required a coach after every `K` iterations without stop checks. **CV-COACH-8** replaces this behavior.
- **CV-COACH-2**: The coach runs as a non-interactive harness invocation with permission prompts disabled, on the coach model.
- **CV-COACH-3**: The coach prompt must give the coach the paths to the log directory, the journal, and the guidance file. It must also give the commit range since the coach's previous run: from the repository HEAD at the start of the previous coach chain, or the session start commit when no coach chain has started in this session, to the current HEAD. When the loop cannot read HEAD, the prompt must say so.
- **CV-COACH-4**: The coach prompt must instruct the coach to:
  - **CV-COACH-4.1**: Read the worker logs since its previous run.
  - **CV-COACH-4.2**: Identify recurring problems across iterations. Examples: a wrong tool call that every worker makes before it recovers, or a trap that a sequence of iterations circles without escaping.
  - **CV-COACH-4.3**: Review its journal and judge each earlier intervention: did it help, hurt, or do nothing? Remove guidance that hurt or did nothing.
  - **CV-COACH-4.4**: Rewrite the guidance file. Keep it short. Each entry must be a concrete, corrective instruction for future workers.
  - **CV-COACH-4.5**: Read the bug history with `cbugs list` and `cbugs search`, and look for a pattern in it: a defect that the workers keep making, or a bug that a worker closed and a later pass reopened. A pattern in the bugs is evidence about the process, which is what the coach writes about.
  - **CV-COACH-4.6**: Append one journal entry that records what it observed, what it changed, and what result it expects.
  - **CV-COACH-4.7**: Read the commit list of the range that **CV-COACH-3** gives, and read the diff of at least two of those commits. A run of commits with near-identical messages, each adding one check and one test, is a pattern. The coach must decide whether that pattern is required work or a trap that the iterations circle.
  - **CV-COACH-4.8**: For each open code bug that a worker worked on in that range, read the bug's first note and every requirement its citations name, in full, and judge whether the cited text requires the work that the commits did. A requirement means what it says. Work that a requirement does not name is not required by it. When workers extend a bug past its citations, the guidance must name the requirement that workers over-read, state what it does require, and tell workers to close the bug and to log each real remaining gap as a new bug with its own citation.
  - **CV-COACH-4.9**: Not copy a worker's list of remaining work into the guidance. A worker's list of remaining work is a claim, not a fact. The coach must check each item against the cited requirement before it repeats the item.
- **CV-COACH-5**: The coach prompt must tell the coach that it may log a bug with `cbugs add`, and must not urge it to. The coach reads logs and commits to judge the process. It does not hunt for defects in code; the reviewer is the role that looks for defects. The coach must not log a task, for the reason that the reviewer must not.
- **CV-COACH-6**: The coach must write only the guidance file, the journal, and a bug. The coach must not edit code, must not edit requirements documents, and must not stop the loop.
- **CV-COACH-7**: The loop must log coach output the same way it logs worker output.

- **CV-COACH-8**: Retired. Defined one period `K` for every coach run. **CV-COACH-10** replaces this behavior.
- **CV-COACH-9**: Normal cbugs list and search commands show the history visible
  at repository `HEAD`. The coach may use `cbugs list --visibility hidden` or
  `cbugs list --visibility all` when it needs to inspect hidden history.
- **CV-COACH-10**: The coach cadence must start at zero each session. Every started worker iteration must count toward the iteration limit and the coach cadence, including failures and timeouts. An enabled coach is due when no coach has run in the session and `F` iterations have started, where `F` is `--coach-first`. After that, the coach is due when `K` iterations have started since the last coach run of the session, where `K` is `--coach-every`. When `F` is `0`, the coach is due before the first worker iteration. A coach run that fails or times out still resets the cadence. The coach must run synchronously under **CV-CONV-34**, after any due review, even if the worker or reviewer failed or timed out. A stop condition takes priority.
- **CV-COACH-11**: The loop must count consecutive stalled chains. The count is the signal of a loop that spins: workers that give up do not always say so, and the cadence of **CV-COACH-10** can leave them to spin for many iterations.
  - **CV-COACH-11.1**: A chain is stalled when it produced output, left no new relevant commit between its start and its end, and gave no done vote and no blocked vote. Uncommitted changes are not progress. A failed chain that produced output is stalled; a timed-out worker that left no relevant commit is stalled.
  - **CV-COACH-11.2**: A stalled chain adds one to the stall count. A chain that left a new relevant commit, or that gave a vote, resets the count to zero. A chain that produced no output leaves the count unchanged: that chain is the signature of an exhausted quota, and the wait of **CV-FAIL-16** handles it.
  - **CV-COACH-11.3**: When the stall count reaches `K` of `--stall-after`, the coach is due before the next worker. The count resets to zero when a coach chain starts, whatever its result. With `--no-coach`, the loop keeps no stall count.
- **CV-COACH-12**: After a blocked vote, the coach is due before the next worker, whatever the cadence. With `--no-coach`, no coach runs.
- **CV-COACH-13**: A coach run that a blocked vote or a stall starts is a coach run under **CV-COACH-10**: it resets the cadence, and the next cadence run is due `K` iterations after it. A coach that is due by more than one trigger runs once. The coach prompt must name every trigger that made the run due. For a blocked vote, it must quote the final message of the blocked worker. For a stall, it must give the stall count.
- **CV-COACH-14**: When a blocked vote or a stall made the coach due, the coach prompt must instruct the coach to decide which case holds, and to answer it:
  - **CV-COACH-14.1**: No worker can resolve the block: an open spec bug waits on the operator, or a tool or resource is missing. Then write guidance that tells workers not to retry that work, and to report a blocked vote when no other work remains. Do not escalate.
  - **CV-COACH-14.2**: The work is doable, and the worker model cannot do it: workers gave up, circled, or claimed a spec bug that no record holds, or a tool or resource that no attempt in the log failed to reach. Then write guidance that names the task and what the workers got wrong, and escalate.
  - **CV-COACH-14.3**: Check with `cbugs show` that each spec bug a worker cited exists and is open. For each tool or resource that a worker cited, find the failed attempt to reach it in the worker log. A claimed spec bug with no open record, or a claimed tool or resource with no failed attempt in the log, is evidence for **CV-COACH-14.2**.
  - **CV-COACH-14.4**: The coach may also escalate on a cadence run when it finds the same evidence there.
- **CV-COACH-15**: The coach escalates with the exact token `ESCALATE` on a line of its own in its final message. The loop must read only the final message of a successful coach chain to detect it, under the same line rule as **CV-CONV-3**. A failed or timed-out coach chain cannot escalate. An escalation makes the next worker iteration a fixer, as **CV-ITER-10** and **CV-HARN-26** give. One escalation gives one fixer iteration, and a second escalation before that iteration runs gives no second fixer. The escalation does not survive the session. A stop condition takes priority over the fixer iteration. The coach prompt must say what the token does: it schedules one more capable worker iteration, and nothing else. This wording is required even when the fixer uses the worker list under **CV-HARN-26.2**. The coach still cannot stop the loop, as **CV-COACH-6** gives.

## Notification

The loop runs unattended, and the operator is away. The notification command is the operator's channel: a command that the operator chooses, that the loop runs with a message, and that the loop knows nothing else about. The loop does not know how to reach a chat service. The command does.

- **CV-NOTIFY-1**: The loop must read the notification command from `CONVERGE_NOTIFY`. The value is a shell command line. When the variable is unset or empty, the loop must send no notification and must report no error. An empty value means off.
- **CV-NOTIFY-2**: The loop must take a session snapshot of the notification command at session start, as **CV-HARN-13** gives for profile lists. An attached client must leave it unchanged, even if its environment differs. The startup panel must say whether a notification command is set. It must not print the value, which can hold a secret.
- **CV-NOTIFY-3**: The loop must send one notification for each of these events, and for no other event:
  - **CV-NOTIFY-3.1**: `converged`: the loop stops with convergence, status `0`.
  - **CV-NOTIFY-3.2**: `limit`: the loop stops at the worker limit without convergence, status `1`.
  - **CV-NOTIFY-3.3**: `discovery-failed`: the loop stops because requirements discovery failed under **CV-DISC-14**, status `2`.
  - **CV-NOTIFY-3.4**: `blocked`: the loop stops on blocked votes under **CV-CONV-29.4**, status `3`.
  - **CV-NOTIFY-3.5**: `stalled`: the stall streak reaches `N` of `--stall-notify`, as **CV-NOTIFY-11** gives.
  An operator stop under **CV-FAIL-1** or **CV-FAIL-9** sends no notification: the operator caused it.
- **CV-NOTIFY-4**: The loop must run the notification command as `sh -c "$CONVERGE_NOTIFY" converge-notify <event>`, so that the command line sees the event name as its first positional parameter. The loop must write the message to the standard input of the command and then close it. The working directory must be the run directory. The loop must export `CONVERGE_EVENT` with the event name, `CONVERGE_RUN_DIR`, `CONVERGE_STATE_DIR`, `CONVERGE_SESSION`, and `CONVERGE_ITERATION` with the current iteration number. For a terminal event it must also export `CONVERGE_EXIT` with the exit status of the session. A command that reads only standard input needs none of these.
- **CV-NOTIFY-5**: The loop must compose the message:
  - **CV-NOTIFY-5.1**: The first line must be `converge <project>: <summary>`. `<project>` is the repository name, followed by `/` and the path of the run directory within the repository when the run directory is not the repository root. The chat that receives the message names the host, not the project, so the message must name the project itself.
  - **CV-NOTIFY-5.2**: For a terminal event, `<summary>` is the closing text of the closing report. For `stalled`, `<summary>` gives the stall streak.
  - **CV-NOTIFY-5.3**: A blank line and details follow when the event has details. For `blocked`, the details are the final message of the last blocked worker, as **CV-OUT-17** shows it. For `stalled`, the details give the number of coach runs since the streak began, whether the last coach run escalated, and whether a fixer iteration ran during the streak. The other events have no details.
  - **CV-NOTIFY-5.4**: The message must hold at most 3,500 characters. The loop must cut the details, never the first line, and must end a cut message with a line that says it was cut.
- **CV-NOTIFY-6**: The loop must send a terminal notification after it prints the closing report and the cost summary of **CV-COST-6**, and before it exits. It must send the `stalled` notification at step 5 of **CV-CONV-34**, after any due coach run and before the next worker starts.
- **CV-NOTIFY-7**: The loop must wait for the notification command, with a time limit of 300 seconds. When the limit expires, the loop must kill the command and its child processes. A first SIGINT must let a running notification command finish, as **CV-FAIL-1** gives for an invocation. A second SIGINT or SIGTERM must terminate it, as **CV-FAIL-9** gives.
- **CV-NOTIFY-8**: A notification command that exits with a nonzero status, that the loop kills, or that the loop cannot start must not change the exit status of the session, any vote count, the stall streak, or the schedule of any agent. The loop must warn and continue. It must not run the command again for the same event. A command that exits without a delivery confirmation can duplicate a message when it is run again, so delivery belongs to the command.
- **CV-NOTIFY-9**: The loop must report each notification: one line in the transcript with the event name and the result, and in the run log the event name, the exit status of the command, and the message text. When the status is nonzero, the loop must show the last lines of the command's standard error, as **CV-OUT-8** gives for an invocation. The loop must not print or log the value of `CONVERGE_NOTIFY`.
- **CV-NOTIFY-10**: The loop must keep a stall streak. It must start at zero each session. The streak exists for the `stalled` notification, and the loop must keep it with or without `--no-coach`.
  - **CV-NOTIFY-10.1**: A stalled chain, as **CV-COACH-11.1** defines it, adds one. A fixer iteration and a timed-out worker count under the same rule.
  - **CV-NOTIFY-10.2**: A chain that left a new relevant commit, or that gave a done vote or a blocked vote, resets the streak to zero.
  - **CV-NOTIFY-10.3**: A chain that produced no output leaves the streak unchanged, as **CV-COACH-11.2** gives for the stall count.
  - **CV-NOTIFY-10.4**: A coach run, a cadence pass, and a vote panel must not change the streak. This is the difference from the stall count of **CV-COACH-11**, which a coach run resets: the streak records whether the coach's intervention worked.
- **CV-NOTIFY-11**: The `stalled` notification is due when the stall streak reaches `N` of `--stall-notify` and the loop has not sent `stalled` since the streak last left zero. One streak sends at most one `stalled` notification, whatever its final length. A reset to zero and a new rise to `N` make the notification due again. The loop must send it after any coach run that is due at the same point, so that the message can report the coach's decision. A stop condition takes priority: a session that stops at the same point sends its terminal notification only.

## State and logs

The loop keeps its files in two directories. The state directory is durable. The runtime directory is temporary.

- **CV-SL-1**: The loop must write nothing into the repository. This prevents interference with git.

### The state directory

- **CV-STATE-1**: Retired. The list named the commit of the last review pass, which lived in a file of the state directory. **CV-STATE-13** replaces this requirement: the bug database holds the reviewed commits.
- **CV-STATE-2**: The path must be `$XDG_STATE_HOME/converge/<name>`. When `XDG_STATE_HOME` is empty, the loop must use `$HOME/.local/state` in its place. This follows the XDG Base Directory Specification, which names logs and history as state.
- **CV-STATE-3**: `<name>` must derive from the path of the run directory and must be stable. A new run in the same run directory must find the state of prior runs. This makes a restart seamless: the guidance file and the journal carry over.
- **CV-STATE-4**: `<name>` must also contain the name of the repository and the path of the run directory within it, so that an operator can read the directory listing and tell the run directories of one repository apart.
- **CV-STATE-5**: The guidance file is `guidance.md`. The journal is `journal.md`. `docs/cbugs-requirements.md` names the bug database, which lives beside them.
- **CV-STATE-6**: Retired. Required every stored open bug to become work in the
  next run. **CV-STATE-14** replaces it.
- **CV-STATE-7**: Retired. Stored harness selection across runs. **CV-HARN-12** forbids new selection state.
- **CV-STATE-8**: The loop must write the full output of each worker, reviewer, and coach invocation to one log file per invocation, in a format that includes every message, tool call, and tool result. Name the files so that the order of invocations is obvious, and so that files from different runs do not collide.
- **CV-STATE-9**: The loop must write its output to one file per session. The client reads that file. Beside it, the loop must record, at the end of the session, the exit status. The loop must record which session is the newest.
- **CV-STATE-10**: The loop must not delete the files of an earlier session. No component removes old files. The operator deletes the state directory when the disk space matters.
- **CV-STATE-11**: The logs must be sufficient for another agent to diagnose problems with the loop after the fact.
- **CV-STATE-12**: Retired. Included stored harness selection in durable state. **CV-STATE-13** replaces this list.
- **CV-STATE-13**: The state directory must hold the guidance file, the journal, the bug database, the logs, and each session's output and status. The bug database holds coverage records. Logs and coverage records may identify profiles, but must not select profiles for a later session. Profile sequence positions must not survive a session. The loop must store no final approval.
- **CV-STATE-14**: Bugs carry over between sessions. At the new session's repository
  `HEAD`, a carried bug is current work only when it is visible and its current
  revision is open. A hidden bug remains in the database but does not enter the
  normal work list.

### The runtime directory

- **CV-RUN-1**: The runtime directory holds only the files that show that a process is alive now: the lock of the loop, the lock that gates the start of a loop, the process id of each session, and the pipes that the loop uses to read the output of a harness.
- **CV-RUN-2**: The path must be `$TMPDIR/converge/<name>`, with the same `<name>` as the state directory. When `TMPDIR` is empty, the loop must use `/tmp` in its place.
- **CV-RUN-3**: A pipe must stay in this directory. A home directory can be on a network file system, which does not support a pipe.
- **CV-RUN-4**: The system removes these files with the rest of the temporary directory. A lock or a process id that a dead loop leaves behind must not block a new session. The lock, and not a file, tells a client whether a loop runs.

### Identity of a run

- **CV-ID-1**: The loop must derive `<name>` from the absolute path of the run directory. A run directory that the operator moves or renames therefore gets a new state directory, and loses the guidance and the journal of the prior runs. The root of a repository and a subdirectory of it derive two names, and two run directories of one repository share no state.
- **CV-ID-2**: The loop must show at startup which state the session uses. The path of the run log is inside the state directory, and the panel gives that path, so the panel does not have to give the path of the state directory itself. The loop must not print the path of the runtime directory, which holds no file that a person reads.
- **CV-ID-3**: Each git worktree has its own path, and therefore its own state. This is correct: two worktrees hold different work, and need different guidance.
- **CV-ID-4**: If the guidance file exists and is not empty at startup, the loop must print its path. Guidance from an earlier session shapes every worker in this session, so the operator must see that it is there.
- **CV-ID-5**: The loop must create both directories when they do not exist.
- **CV-ID-6**: The startup panel must show the run directory. When the run directory is a subdirectory of the repository, the panel must show the subdirectory, and must not show the root of the repository in its place. The operator must see which directory the run works from.

## Signals, timeouts, and failures

- **CV-FAIL-1**: On the first SIGINT, the loop must let the running invocation finish, and must then stop. It must start no further invocation: no worker, no review pass, and no coach run. It must print that it stops on the request of the operator, show the closing report, and exit with status 130.
- **CV-FAIL-2**: Retired. Named only the Claude child for termination. **CV-FAIL-9** applies to every harness.
- **CV-FAIL-3**: Retired. Continued directly to the next iteration after a timeout. **CV-FAIL-15** preserves due scheduling.
- **CV-FAIL-4**: Retired. The next pass examined the same range, and the commit of the last pass did not move. **CV-FAIL-11** replaces this requirement.
- **CV-FAIL-5**: Retired. Continued directly to the next iteration after an error. **CV-FAIL-15** preserves due scheduling.
- **CV-FAIL-6**: Retired. Forbade stopping after any invocation failure. **CV-FAIL-14** replaces this behavior.
- **CV-FAIL-7**: Retired. Waited after each invocation that failed before output. **CV-FAIL-16** replaces this behavior.
- **CV-FAIL-8**: Retired. Defined failed review coverage without approval or vote rules. **CV-FAIL-11** replaces this behavior.
- **CV-FAIL-9**: On a second SIGINT or on SIGTERM, the loop must terminate the running invocation and all its child processes, for every supported harness, and exit promptly. The client must send the signal to the loop's process group.
- **CV-FAIL-10**: Retired. Applied continuation rules to every invocation failure. **CV-FAIL-15** replaces this behavior.
- **CV-FAIL-11**: Retired. Reset votes after failed review. **CV-FAIL-12** replaces this behavior.
- **CV-FAIL-12**: Retired. Defined failed review handling without a fallback chain. **CV-FAIL-17** replaces this behavior.
- **CV-FAIL-13**: On the first Ctrl-C, the loop must forward graceful `SIGUSR1` to an active panel controller. The controller must stop new launches and let all active invocations finish. It must not start a merge after this request. A second Ctrl-C must interrupt all owned descendants, including panel agents in separate process groups. SIGTERM must stop them immediately. Cleanup must follow process ownership and must not stop another session. An operator stop must remain distinct from an invocation error.
- **CV-FAIL-14**: Worker, reviewer, and coach failures must not stop the loop by themselves. Discovery failures must stop startup under **CV-DISC-14**.
- **CV-FAIL-15**: Retired. Forbade profile fallback after a failure. **CV-FAIL-18** replaces this behavior.
- **CV-FAIL-16**: If every attempt of a chain fails before it produces output, the loop must wait before it starts the next scheduled run. The wait must double with each consecutive chain of this kind, from 10 seconds up to a maximum of 15 minutes. The loop must not wait between the attempts of one chain. An attempt that produces output resets the wait to zero, whether it succeeds or fails. This keeps the loop alive when every configured subscription has exhausted its quota, and lets it resume when a quota period resets.
- **CV-FAIL-17**: A cadence pass whose chain has no successful attempt, or whose attempt timed out, must record no coverage. Unreviewed commits must remain unreviewed. Review and coverage-record failures must not change the done count or the blocked count, or block convergence. The next normally due cadence pass must use its normal range and must start at the next reviewer entry under **CV-HARN-23**. A failed panel must not trigger an immediate retry.
- **CV-FAIL-18**: On a timeout, the loop must kill the invocation, print a notice, log the event, and end the chain. On a nonzero exit, it must log the event and continue the chain under **CV-HARN-24**. Discovery must follow **CV-DISC-14**. Other roles must follow **CV-CONV-34**, including any due coach. Stop checks and the wait of **CV-FAIL-16** still apply.

## Out of scope

These are recorded decisions, not oversights.

- **CV-OOS-1** — **A task that an agent logs**: rejected. A task is a request from an operator. An agent that logs one invents work, and the next worker does it before the work that the requirements name. `cbugs` refuses `--kind task` when `CONVERGE_ROLE` is in the environment, so every agent of the loop is refused.
- **CV-OOS-2** — **A loop that reports the citations of a bug**: rejected for v1. The report of a review pass gives the id, the kind, and the title. A reader who wants the citation runs `cbugs show`.
- **CV-OOS-3** — **Loop-managed commits**: rejected. Workers commit as well as loop-enforced commits do, and the loop stays simpler.
- **CV-OOS-4** — **Worker notes between iterations**: rejected for v1. The guidance file and the bug database are the channels between iterations. A note that is not a defect and not process guidance has no channel, and needs none yet.
- **CV-OOS-5** — **Separate review agents**: rejected in v1, and adopted now. The earlier objection stands on its own terms: a review agent chases problems that the requirements do not name, and derails the project. The bug tracker answers it. A defect is now a durable record with a kind, not a message that pushes a worker off its work. A worker reads the open code bugs and decides; a finding that is wrong is dismissed and stays visible; and a finding that the requirements do not name has a place to go, as a spec bug that no agent acts on. What made a reviewer dangerous was that its output went straight into the next worker's head. It goes into a database instead.
- **CV-OOS-6** — **A reviewer that fixes what it finds**: rejected. The reviewer reads the code against the requirements. A reviewer that starts editing stops reading, and it becomes a worker that skipped the survey.
- **CV-OOS-7** — **A reviewer that closes a bug**: rejected. A close records that someone did the work. The reviewer did not.
- **CV-OOS-8**: Retired. Rejected bug queries for decisions. **CV-CONV-31** now forbids convergence checks of code-bug and task counts.
- **CV-OOS-9** — **A record of a review pass that found no defect**: rejected. The reviewed commits name the coverage of the passes, and the bug database holds defects. A pass that logs no bug needs no record of its own, and the logs of the loop show that it ran.
- **CV-OOS-10** — **Coach authority to halt the loop or edit the repository**: rejected for v1. A bad coach judgment must cost at most a few misguided iterations.
- **CV-OOS-11** — **Cost or token budgets**: rejected for v1. `--max-iterations` and the operator bound the session.
- **CV-OOS-12** — **Coach-selected cadence**: rejected for v1. A fixed first threshold and a fixed period are simpler and easier to reason about. The same holds for the review threshold of **CV-INV-3.14**. A cadence whose gaps grow, as a backoff factor, is rejected for the same reason.
- **CV-OOS-13** — **A key that detaches the client but keeps the loop**: rejected for v1. Ctrl-C stops the session. The state directory makes a restart cheap.
- **CV-OOS-14** — **`--status` and `--stop` commands**: rejected for v1. To see a loop, attach to it.
- **CV-OOS-15** — **Two clients on one loop**: not a supported case. It does no harm, and either client can stop the loop.
- **CV-OOS-16** — **Plain text output**: rejected. Every client is a terminal that accepts color.
- **CV-OOS-17**: Retired. Rejected automatic harness changes without distinguishing scheduled selection. **CV-OOS-30** defines the boundary.
- **CV-OOS-18** — **Removal of old logs**: rejected for v1. The state directory grows by one log file for each invocation. The operator deletes the directory. An automatic rule that removes the wrong file costs more than the disk space.
- **CV-OOS-19** — **`XDG_RUNTIME_DIR` for the locks and the pipes**: rejected. macOS supplies no such variable, so the script would need a second code path for the fallback. `TMPDIR` gives one code path on both platforms.
- **CV-OOS-20** — **`~/Library/Application Support` on macOS**: rejected. The XDG paths are usual for a command line tool on macOS, and they keep one code path.
- **CV-OOS-21** — **Migration of the state of an earlier version from the temporary directory**: rejected. The system removes that state on its own.
- **CV-OOS-22** — **Identity of a repository from the git remote**: rejected. A repository can have no remote, and two clones of one remote hold different work.
- **CV-OOS-23**: Retired. Rejected stored scope records. **CV-SCOPE-12** now permits session records and forbids their reuse to select requirements for later sessions.
- **CV-OOS-24** — **A scope that names a requirement identifier, as `docs/x.md:CV-INV-3`**: rejected for v1. A file or a directory is enough to point a session at part of the project. A citation names one requirement; a scope names a body of work.
- **CV-OOS-25** — **A state directory shared by the run directories of one repository**: rejected. The guidance, the journal, and the bugs describe the work of one run directory. A run in a second directory that shared them would act on guidance for work that it cannot see, and the two runs would write one bug list that neither one owns.
- **CV-OOS-26** — **An option or an environment variable of the client that points the run at another run directory**: rejected. The current directory names the run directory, and an operator who wants another one changes directory. A pointer that can disagree with the current directory is a second anchor, and a silent wrong anchor is the failure that the run-directory design removes. This rejects a pointer for the operator, not the variable that the loop exports for the bug tracker (**CV-ENV-6**): the loop sets that variable, and no option of the client sets it.
- **CV-OOS-27** — **A cadence of review passes by a count of iterations**: rejected. The count lived in the memory of the loop, and a Ctrl-C that stopped the session threw it away. A resume then reviewed work that a pass had already covered, or skipped work that no pass had covered. The count of the unreviewed commits is durable, in the bug database, and it survives the death of the loop.
- **CV-OOS-28** — **A reviewer that records the commits that it read**: rejected. The loop records the commits that it gave to the pass, after the pass ends with success (**CV-REV-15**). An agent that forgets to record leaves the work for the next pass to repeat, and an agent that records without reading hides code from every later pass. The bug tracker refuses the record from an agent of the loop, as it refuses a task.
- **CV-OOS-29**: Retired. Accepted convergence without whole-code approval. **CV-CONV-21** and **CV-CONV-31** now require vote-only convergence with no approval.
- **CV-OOS-30**: Retired. Rejected failure fallback. **CV-HARN-24** now requires a fallback chain, and **CV-OOS-33** through **CV-OOS-35** give its limits.
- **CV-OOS-31** — **Durable final approval**: rejected. Reviewed-commit records survive a restart. Neither session approval nor durable approval is required or granted under **CV-CONV-31**.
- **CV-OOS-32** — **Up-front harness availability checking**: rejected. The loop starts the harness command directly, so a missing harness fails on its first invocation. A pre-flight check must gather the harness names from the profile lists, and the PATH can still change between the check and the first invocation. The check also gives a disabled role power over a session: a missing coach harness would stop a session whose coach never runs.
- **CV-OOS-33** — **Profile health memory**: rejected. A record that a profile failed recently could skip that profile at the start of a later chain. The saving is one fast attempt per chain, and that attempt costs seconds and no tokens. The record is selection state that **CV-STATE-13** forbids, and a stale record skips a profile that has recovered.
- **CV-OOS-34** — **Fallback after a timeout**: rejected. A timeout means that the attempt worked for the full limit. A second attempt doubles the time of the chain, and the next profile faces the same work. The fallback chain targets a fast nonzero exit, which is the signature of an exhausted quota.
- **CV-OOS-35** — **Fallback inside a vote panel**: rejected for now. Panel reviewers run concurrently, and a failed reviewer makes the panel incomplete under `docs/review-panel-requirements.md:RP-REV-6`. The loop still converges, because **CV-CONV-31** lets no panel failure block it. The merge agent gets its own chain under `RP-PROF-13`, and an operator who wants a merge fallback sets a list in `CONVERGE_REVIEW_PANEL_MERGE_PROFILE`.
- **CV-OOS-36** — **A coach that stops the loop on a blocked vote**: rejected. **CV-OOS-10** holds: a bad coach judgment must cost at most a few iterations, and a wrong stop costs the session. The second blocked vote arrives one iteration later, and the counter of **CV-CONV-29** stops the loop then. The coach decides the response; the counter decides the exit.
- **CV-OOS-37** — **A fixer that the loop schedules on a stall without the coach**: rejected. It spends an expensive iteration on work that a spec bug blocks, with no diagnosis, and nobody writes the guidance that tells the fixer what to try. The coach invocation costs about the same and produces both.
- **CV-OOS-38** — **A coach that selects an entry of the worker list**: rejected. It mixes the fallback for an exhausted quota with the escalation for a hard task, and the worker rotation would then use the expensive profile on ordinary iterations. The fixer list of **CV-HARN-26** is separate.
- **CV-OOS-39** — **A blocked vote that the loop verifies against the bug database**: rejected, for the reason of **CV-CONV-31**. The loop counts votes; it does not judge them. The coach reads the record and judges, as **CV-COACH-14.3** gives.
- **CV-OOS-40** — **An escalation that lasts more than one iteration**: rejected. One iteration bounds the cost of a wrong escalation under **CV-OOS-10**. When the fixer makes partial progress and the workers stall again, the stall trigger brings the coach back, and the coach can escalate again.
- **CV-OOS-41** — **A file in the state directory as the channel from the coach to the loop**: rejected. A token in the final message uses the parser that the done vote uses, and leaves nothing to clean up. A file is selection state that **CV-STATE-13** forbids, and a stale file would select a fixer for a later session.
- **CV-OOS-42** — **A blocked vote after work in the same iteration**: rejected. A worker that did work reports the work. A blocked vote means that the iteration found nothing to do, as the done vote means. Two meanings in one token make the count mean nothing.
- **CV-OOS-43** — **An agent that sends the notification itself**: rejected. The trigger would be a model, with no limit on how often it fires and no record in the run log. No agent runs at the moments that matter most: the closing report, and a quota that every profile has exhausted, when the coach fails for the same reason as the workers. The loop sees every state change and owns the one trigger. A coach that wants the operator writes a spec bug or lets the counters speak.
- **CV-OOS-44** — **Notifications for a new spec bug, the quota wait, and its recovery**: rejected for v1. A spec bug that blocks all remaining work reaches the operator through the blocked stop, which names it. The quota wait resolves itself when the quota period resets, and the transcript reports it on attach. Each of these messages would arrive often and ask for nothing, and the operator would learn to ignore the channel.
- **CV-OOS-45** — **A retry or a queue for a failed notification**: rejected. The command owns delivery. A command that exits without confirmation may have delivered, and a second run duplicates the message. The run log records what the loop tried to send.
- **CV-OOS-46** — **A configuration file or a fixed hook path for the notification command**: rejected. Every other setting of the loop is an environment variable, and **CV-INV-11** refuses configuration files. A hidden file that changes behavior is a second anchor, and a stale one sends messages to the wrong place.
- **CV-OOS-47** — **An error for an empty `CONVERGE_NOTIFY`**: rejected. An empty profile list is an error because it hides a default. An empty command hides nothing: it means off, and it lets a shell that exports the variable turn notification off for one session.
- **CV-OOS-48** — **A stall notification by elapsed time**: rejected. Iterations last from minutes to the full timeout, and the wait of **CV-FAIL-16** pauses the loop for up to 15 minutes at a time. The loop counts chains everywhere else, as **CV-OOS-12** gives for cadences.
- **CV-OOS-49** — **A repeated `stalled` notification within one streak**: rejected for v1. After the message, the operator stops the loop, fixes something, or lets it run. A second message changes none of these. A fix that produces a commit ends the streak, and a later streak sends again. `--max-iterations` bounds a session that the operator ignores, and the `limit` notification then arrives.
