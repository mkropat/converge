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
| `PLAT` | Platform |
| `HARN` | Harness |
| `BG` | Background operation |
| `ITER` | Iteration behavior |
| `ENV` | The environment of an agent |
| `OUT` | Output |
| `CONV` | Convergence and stopping |
| `REV` | Reviewer |
| `COACH` | Coach |
| `SL` | State and logs |
| `STATE` | The state directory |
| `RUN` | The runtime directory |
| `ID` | Identity of a run |
| `FAIL` | Signals, timeouts, and failures |
| `OOS` | Out of scope |

## Terms

- **Run directory**: the current working directory when the operator starts the run. The root of the repository and any subdirectory of it can be the run directory.
- **Loop**: the `converge` script that runs the iterations, in the background.
- **Client**: the `converge` command that the operator runs. The client starts a loop, or attaches to the loop that runs.
- **Session**: one run of the loop, with its output file, its process id, and its result.
- **Harness**: the agent command that the loop starts for a worker, a reviewer, or a coach.
- **Worker**: one agent instance that the loop starts for one iteration.
- **Reviewer**: an agent that the loop starts on a fixed cadence to examine the code changes of recent iterations and to log bugs.
- **Review pass**: one run of the reviewer, over the commits that no reviewer has examined yet.
- **Coach**: an agent that the loop starts on a fixed cadence to review recent worker logs and to write guidance.
- **Bug tracker**: `bin/cbugs`, which keeps the bugs of the run directory in its state directory. See `docs/cbugs-requirements.md`.
- **Code bug**: a defect in the code. A worker fixes it.
- **Spec bug**: an ambiguity, a gap, or a contradiction in the requirements documents. The human user resolves it. No agent works on a spec bug, and no agent waits for one.
- **Task**: a punchlist item that a human user asked for. A worker does it. Only a human user directs the record of one.
- **Scope**: the set of requirements documents that the operator names on the command line. An empty scope means that the agent finds the requirements documents itself.
- **Citation**: a reference from a bug revision to a documented requirement. `cbugs` writes it from a `--cite` option.
- **Guidance file**: the file that the coach writes and that the loop injects into each worker prompt.
- **Journal**: the coach's private record of its observations and interventions.
- **State directory**: the durable directory that holds the guidance file, the journal, the bug database, and the logs of one run directory. It survives a restart of the machine.
- **Runtime directory**: the temporary directory that holds the locks and the pipes of one run directory. It holds nothing that must survive a restart of the machine.

## Design principles

These principles explain the intent behind the requirements. Apply them when a requirement is ambiguous.

- **CV-PRIN-1**: The goal is autonomous convergence on the documented requirements. Speed and token cost are secondary.
- **CV-PRIN-2**: Each worker starts with no memory of prior iterations. The worker re-orients from the repository state, the requirements documents, and the guidance file only. This prevents a worker from continuing a bad approach because a prior iteration recorded it as a plan.
- **CV-PRIN-3**: No component writes or follows an implementation plan. Requirements documents describe behavior. They do not describe implementation steps.
- **CV-PRIN-4**: A defect that one iteration finds must reach a later iteration. A worker has no memory, so a defect that nobody records is a defect that nobody fixes. The bug tracker is that channel, and the guidance file is not: the coach rewrites the guidance on each run, and keeps it short.
- **CV-PRIN-5**: Prefer too little process over too much. Add structure only where it changes outcomes.
- **CV-PRIN-6**: It is acceptable for the loop to stop before the requirements are fully met. It is not acceptable for the loop to add large amounts of code that the requirements do not need. The operator can clarify requirements and restart the loop.

## Invocation

- **CV-INV-1**: The script must live at `bin/converge`.
- **CV-INV-2**: The script must operate on the run directory: the current working directory when the operator starts the run. The run directory can be the root of the repository or any subdirectory of it.
- **CV-INV-3**: The script must accept these options:
  - **CV-INV-3.1**: `--harness <name>`: the harness. Default: see "Harness".
  - **CV-INV-3.2**: `--model <model>`: the worker model. Default: the worker model of the harness.
  - **CV-INV-3.3**: `--coach-model <model>`: the coach model. Default: the coach model of the harness.
  - **CV-INV-3.4**: `--review-model <model>`: the reviewer model. Default: the reviewer model of the harness.
  - **CV-INV-3.5**: `--consensus <N>`: the number of consecutive done votes that stop the loop. Default: `2`.
  - **CV-INV-3.6**: `--coach-every <K>`: the number of worker iterations between coach runs. The script sets the default.
  - **CV-INV-3.7**: `--no-coach`: disable the coach.
  - **CV-INV-3.8**: `--review-every <R>`: the number of worker iterations between review passes. The script sets the default. A reviewer that sees the work of several iterations together can find a defect that spans them.
  - **CV-INV-3.9**: `--no-review`: disable the reviewer.
  - **CV-INV-3.10**: `--timeout <seconds>`: the maximum duration of one worker, reviewer, or coach invocation. Default: `3600`.
  - **CV-INV-3.11**: `--max-iterations <N>`: the maximum number of worker iterations. Default: unbounded.
  - **CV-INV-3.12**: `--foreground`: run the loop in the terminal of the operator, and not in the background.
- **CV-INV-4**: Retired. A run passed every option that it did not consume through to the harness. **CV-INV-6** replaces this behavior.
- **CV-INV-5**: Retired. A run took no positional argument. **CV-INV-8** replaces this behavior.
- **CV-INV-6**: The script must pass every argument after the first `--` through to the harness, unchanged. It must consume none of them, and it must read none of them as an option of its own.
- **CV-INV-7**: The script must stop with an error when an argument before `--` starts with `-` and is not an option of **CV-INV-3**. The error must name the argument. A typo must not become a harness option.
- **CV-INV-8**: The script must accept positional arguments before `--`. Each one names a requirements document file, or a directory that holds requirements documents. "Requirements scope" gives the behavior.
- **CV-INV-9**: The run directory anchors the run. The state directory, the bug database, the resolution of every scope path, and the working directory of every agent derive from the run directory, as the sections that govern them give. Two run directories share no state and no bug database. A subdirectory of a repository is therefore a place to run the command in its own right, with the same behavior as the root. The repository that contains the run directory supplies the git state of the run: the commits, and the history that a review pass reads.
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
  - **CV-INV-10.5**: A run tests the harness command, as CV-HARN-4 gives. The
    init operation must test none, because it makes directories and runs no
    agent.

## Requirements scope

The operator can point a run at part of the project. The scope says which
requirements documents the agents work on.

- **CV-SCOPE-1**: The scope of a run is the list of positional arguments, in the order that the operator gave them. A run with no positional argument has an empty scope.
- **CV-SCOPE-2**: The script must resolve each path of the scope against the run directory, and must stop with an error when the path does not exist. The error must name the path. A typo must not become a run that ignores the scope.
- **CV-SCOPE-3**: The loop must give each path to an agent as the operator wrote it. An agent runs in the run directory, so a relative path names the same document for the agent as it named for the operator.
- **CV-SCOPE-4**: When the scope is empty, the worker prompt and the reviewer prompt must name the requirements documents in general terms, and must instruct the agent to find them under the run directory. This is the behavior of a run with no positional argument.
- **CV-SCOPE-5**: When the scope is not empty, the worker prompt and the reviewer prompt must give the paths of the scope, and must instruct the agent to work on those requirements documents only. A path that is a directory names every requirements document under it.
- **CV-SCOPE-6**: A scope says what to build and what to judge. It does not remove the other requirements documents of the repository. A change that contradicts a document outside the scope is still a spec bug, as **CV-ITER-3.7** gives.
- **CV-SCOPE-7**: The coach prompt must not carry the scope. The coach reads the logs and the process, and not the requirements documents.
- **CV-SCOPE-8**: The startup panel must show the scope, and must show that the scope is empty when it is. The operator must see which documents the run works on.
- **CV-SCOPE-9**: The scope belongs to the session. The loop must not record it in the state directory, and a later run with no positional argument has an empty scope. A client that gives a scope to a loop that runs keeps the scope of that loop, as **CV-BG-6** gives for every other option.

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

The loop starts each worker, each reviewer, and each coach through a harness. The supported
harnesses are `claude` and `opencode`. One run uses one harness.

- **CV-HARN-1**: The script must select the harness from the first of these that it finds:
  1. The `--harness` option.
  2. The harness that the state directory records for the run directory.
  3. The `CONVERGE_HARNESS` environment variable.
  4. `claude`.
- **CV-HARN-2**: A client that attaches to a loop that runs keeps the harness of
  that loop, as it keeps every other option.
- **CV-HARN-3**: Before the first iteration, the loop must record its harness in
  the state directory.
- **CV-HARN-4**: The script must stop with an error when the name is not a
  supported harness, or when the command of the harness is not on PATH.
- **CV-HARN-5**: The script must select each model from the first of these that it finds:
  1. The option for the role: `--model`, `--coach-model`, or `--review-model`.
  2. The environment variable for the selected harness and role. Its name is `CONVERGE_<HARNESS>_MODEL`, `CONVERGE_<HARNESS>_COACH_MODEL`, or `CONVERGE_<HARNESS>_REVIEW_MODEL`, where `<HARNESS>` is the uppercase harness name. For example, `CONVERGE_CLAUDE_MODEL` sets the worker model for `claude`, and `CONVERGE_OPENCODE_REVIEW_MODEL` sets the reviewer model for `opencode`.
  3. The built-in default for the selected harness and role.
  - **CV-HARN-5.1**: The built-in defaults for `claude` are `sonnet` for the worker, and `opus` for the reviewer and for the coach. A reviewer reads a diff and judges it against the requirements, which is the work that a stronger model does better.
  - **CV-HARN-5.2**: The built-in defaults for `opencode` are `opencode/gpt-5.6-luna` for the worker, and `opencode/gpt-5.6-sol` for the reviewer and for the coach.
- **CV-HARN-6**: The loop must print its harness and all three models at startup.
- **CV-HARN-7**: Each harness reports its work in a different form. The loop must
  give the operator the same information from both:
  - **CV-HARN-7.1**: The final message of an agent. `claude` reports it in one result message. For `opencode`, the final message is the text of the last assistant message.
  - **CV-HARN-7.2**: The number of turns, the duration, and the cost. When the harness reports no totals, the loop must compute them from the message stream.
  - **CV-HARN-7.3**: A tool call that fails, when the harness reports the failure. `opencode` reports a shell command that exits with an error as a normal result, so the loop cannot show that command as a failure.

## Background operation

The operator starts a run over a connection that can break, and the run survives the loss of the terminal.

- **CV-BG-1**: The client must run the loop in a process that has no controlling terminal and its own process group. A closed terminal or a lost connection must not stop the loop.
- **CV-BG-2**: The client must start a loop only when no loop runs for the run directory. In all other cases it must attach to the loop that runs.
- **CV-BG-3**: To attach again, the operator runs `converge` again in the same run directory. The client must need no argument for this.
- **CV-BG-4**: One run directory must never have two loops. The test for a running loop must be a lock that the operating system releases when the loop dies. A file that a dead loop leaves behind must not block a new run.
- **CV-BG-5**: The client must write the output of the loop to the terminal:
  - **CV-BG-5.1**: When the client starts the loop, it must show the output from the first line.
  - **CV-BG-5.2**: When the client attaches to a loop that runs, it must first show the last screen of earlier output, then a rule that gives the start time of the loop and the current iteration, then the new output.
- **CV-BG-6**: When the operator gives options to a client that attaches, the client must keep the options of the running loop and must print a warning that it ignored the options.
- **CV-BG-7**: Before the client starts a new loop, it must give one line about the result of the last run, when a last run exists.
- **CV-BG-8**: Ctrl-C must stop the run in two steps, so that one keypress does not throw away the work of an iteration:
  - **CV-BG-8.1**: The first Ctrl-C must ask the loop to stop at the end of the current iteration. The client must print one prominent message in bold white text. The message must say that the loop stops at the end of the current iteration, and that a second Ctrl-C stops the run at once.
  - **CV-BG-8.2**: The second Ctrl-C must stop the loop and every agent below it at once.
  - **CV-BG-8.3**: In both cases the client must show the closing report of the loop and exit with status 130.
- **CV-BG-9**: The client must exit with the status of the loop.
- **CV-BG-10**: `--foreground` must run the loop in the terminal, for a person who debugs the loop. The lock still applies.
- **CV-BG-11**: Two loops may run at the same time in two run directories of one repository. Each loop commits to the shared repository, and no lock of the loop spans the repository. A worker of one loop can therefore meet an error from git when a worker of the other loop holds a lock of the repository. The worker prompt tells the worker to wait and to try the commit again, as **CV-ITER-3.13** gives.

## Iteration behavior

- **CV-ITER-1**: Before each iteration, the loop must print one line to stdout with the iteration number and the current time.
- **CV-ITER-2**: Each iteration runs one worker as a non-interactive harness invocation with permission prompts disabled.
- **CV-ITER-3**: The worker prompt must instruct the worker to:
  - **CV-ITER-3.1**: Survey the current repository state with fresh eyes.
  - **CV-ITER-3.2**: Read the requirements documents of the scope, as "Requirements scope" gives. With an empty scope, find and read the requirements documents under the run directory.
  - **CV-ITER-3.3**: Run `cbugs list --kind code --kind task --status open` and read the open code bugs and the open tasks.
  - **CV-ITER-3.4**: Fix these bugs before it starts work that the requirements name but no bug names. A defect in the code that exists is worth more than a feature that does not, and a task is work that a human user asked for.
  - **CV-ITER-3.5**: Read the citations of a bug with `cbugs show`, and read the requirement that a citation names. The citation says which requirement the fix must meet.
  - **CV-ITER-3.6**: Close each bug that it fixes, with `cbugs close`, and say in the note what it changed.
  - **CV-ITER-3.7**: Do a task in a way that no requirements document contradicts. A change that contradicts a document is a spec bug: log it, and do not make the change.
  - **CV-ITER-3.8**: Select one chunk of work that moves the project toward the requirements, when no open code bug and no open task remain. The chunk must be small enough to complete in one iteration. The chunk must be large enough to be a meaningful step, not a myopic one.
  - **CV-ITER-3.9**: Implement the chunk.
  - **CV-ITER-3.10**: Commit logical changes with clear messages.
  - **CV-ITER-3.11**: Not create plan documents, roadmap documents, or task lists that persist between iterations.
  - **CV-ITER-3.12**: Not work on a spec bug, and not wait for one. The human user resolves a spec bug.
  - **CV-ITER-3.13**: When a commit fails because another process holds a lock of git, wait and try the commit again. A second loop can run in a second run directory of the same repository, as **CV-BG-11** gives.
- **CV-ITER-4**: The worker prompt must tell the worker that it may log a bug with `cbugs add`, and must not urge it to. A worker that finds a defect it will not fix in this iteration has somewhere to put it. A worker that hunts for defects is not doing the work of a worker.
- **CV-ITER-5**: The worker prompt must instruct the worker to cite the requirement that a bug it logs is about, with `cbugs add --cite <path>[:<id>]`.
- **CV-ITER-6**: If the guidance file exists and is not empty, the loop must include its content in the worker prompt.
- **CV-ITER-7**: The loop must not change git state. Workers own all commits. The loop may read git state to report what an iteration changed.

## The environment of an agent

- **CV-ENV-1**: The loop must export `CONVERGE_ROLE` into the environment of every agent that it starts. The value is `worker`, `reviewer`, or `coach`.
- **CV-ENV-2**: The loop must export `CONVERGE_ITERATION` into the environment of every agent that it starts. The value is the number of the current worker iteration. A reviewer and a coach get the number of the iteration that they follow.
- **CV-ENV-3**: The bug tracker reads both variables and records them on each revision that an agent writes. An agent therefore cannot record the wrong role, and a prompt does not have to carry the values.
- **CV-ENV-4**: The loop must put `bin/cbugs` on the PATH of every agent that it starts. A worker that cannot run the command cannot fix a bug.
- **CV-ENV-5**: The loop must start every agent with the run directory as its working directory. A scope path, a requirements document, and the bug database therefore resolve for the agent as they resolved for the operator.
- **CV-ENV-6**: The loop must export `CONVERGE_RUN_DIR` into the environment of every agent that it starts. The value is the absolute path of the run directory. An agent that changes its own working directory therefore still reads and writes the bugs of its own run, and never the bugs of another run directory that it moved into. The bug tracker reads the variable, as `docs/cbugs-requirements.md` gives.

## Output

- **CV-OUT-1**: The loop must print its progress in a form that an operator can scan:
  - **CV-OUT-1.1**: A panel at startup with the run settings and the paths that an operator reads. A path inside the home directory appears as a `~/` path.
  - **CV-OUT-1.2**: A heading for each iteration, for each review pass, and for each coach run.
  - **CV-OUT-1.3**: One line for each invocation that starts, with the role and the model. For a worker, this line also gives the log file.
  - **CV-OUT-1.4**: One line for each result: the duration, a done vote with its count, a timeout, an error, or a wait.
  - **CV-OUT-1.5**: A closing report with the result and the total duration of the run.
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
- **CV-OUT-6**: The loop must find the bugs of a pass by reading the list of bugs before the pass and after it. The bug tracker gives no filter on the role or the iteration, and needs none for this. The loop reads the list. It makes no decision from what it reads.
- **CV-OUT-7**: After each coach run, the loop must report whether the coach changed the guidance. If the coach changed it, the loop must show the new guidance in full. In both cases the loop must give the path of the guidance file. The loop must not give the path of the coach log, which a person cannot read.
- **CV-OUT-8**: If an invocation fails, the loop must show the last lines that it wrote to stderr. A failure with no messages puts its cause there.
- **CV-OUT-9**: The loop must always use color, bold, and box characters. It writes to a file that a client shows in a terminal, so it cannot ask what reads it.
- **CV-OUT-10**: The loop has no terminal of its own. The client must give it the width of the terminal.
- **CV-OUT-11**: Style must not remove information. Each message that the loop prints must also go to the run log, as plain text.

## Convergence and stopping

- **CV-CONV-1**: The worker prompt must instruct the worker: do not vote while an open code bug or an open task exists. If you judge that the repository satisfies the requirements documents of the scope, no open code bug and no open task remain, and no work remains, write the exact token `CONVERGED` on a line of its own in your final message, and do no work.
- **CV-CONV-2**: The loop must read only the worker's final message to detect the token. This is a done vote.
- **CV-CONV-3**: The loop must count the token only when it is alone on a line. Space before or after the token does not matter. The loop must ignore the token inside a line of text. This lets a worker name the token, or quote this document, without a vote.
- **CV-CONV-4**: After a done vote, and before the next worker starts, the loop must run a review pass, unless the consensus is now complete or the reviewer is disabled. This is true whether or not a pass is due on the normal cadence.
- **CV-CONV-5**: A worker that votes has done no work, so the pass examines the commits that no reviewer has examined yet. A pass that finds a defect logs a code bug, the next worker fixes it instead of voting, and the count of consecutive votes returns to zero. The loop therefore cannot converge on code that no reviewer has seen.
- **CV-CONV-6**: With `--consensus 1`, a done vote completes the consensus at once, and no pass precedes it. An operator who wants every commit reviewed before convergence uses a consensus of `2` or more, which is the default.
- **CV-CONV-7**: The loop must not query the bug database to decide anything. The done vote is the only signal it reads. The worker prompt holds the rule that an open code bug or an open task prevents a vote.
- **CV-CONV-8**: When the loop counts `N` consecutive done votes from different worker invocations, it must stop and report convergence.
- **CV-CONV-9**: Any iteration that does not produce a done vote must reset the consecutive count to zero. This includes failures and timeouts.
- **CV-CONV-10**: The loop must exit with status `0` on convergence and with a non-zero status in all other cases.

## Reviewer

The worker builds. The reviewer reads what the worker built. One agent cannot do both well, because a worker that judges its own work is the author of that work.

- **CV-REV-1**: After every `R` worker iterations, the loop must run the reviewer synchronously before the next worker starts. The loop must also run it after a done vote, as "Convergence and stopping" gives.
- **CV-REV-2**: The loop must not run a review pass when no commit has arrived since the previous pass. There is nothing to read, and a pass that reads nothing costs a full agent invocation.
- **CV-REV-3**: Every review pass must reset the count of iterations since the last pass, whatever started the pass.
- **CV-REV-4**: The reviewer runs as a non-interactive harness invocation with permission prompts disabled, on the reviewer model.
- **CV-REV-5**: The loop must record, in the state directory, the commit at the end of each review pass. The next pass examines the range from that commit to HEAD.
- **CV-REV-6**: The reviewer prompt must give the reviewer that range. The reviewer needs no memory and no query to learn what it has already read.
- **CV-REV-7**: On the first pass of a run directory, the range is the whole history of the repository. The reviewer must judge how far back to read, and the prompt must tell it that the recent commits matter most.
- **CV-REV-8**: The reviewer prompt must instruct the reviewer to:
  - **CV-REV-8.1**: Read the changes in the range, and read the requirements documents that they touch. With a scope, judge the changes against the requirements documents of the scope.
  - **CV-REV-8.2**: Run `cbugs search` before it logs a bug, and log nothing that an open bug already names.
  - **CV-REV-8.3**: Log a code bug with `cbugs add --kind code` for each defect in the code: a behavior that contradicts a requirement, a case that the code does not handle, or a change that broke something that worked.
  - **CV-REV-8.4**: Cite the requirement that the code violates, with `--cite <path>[:<id>]`, on every code bug. A reviewer that cannot name the requirement has found no defect in the code, and must consider whether it has found a spec bug instead.
  - **CV-REV-8.5**: Log a spec bug with `cbugs add --kind spec` when the changes reveal that a requirement is ambiguous, absent, or in conflict with another. The report must say what the reviewer could not decide, and why the changes raised the question. Cite each document and requirement that raised the question.
  - **CV-REV-8.6**: Log nothing when it finds nothing. A pass that finds no defect is a normal result, and an invented defect costs a worker a whole iteration.
- **CV-REV-9**: The reviewer must log a defect that it finds, and must not fix it. A reviewer that edits code becomes a worker with no memory of the requirements it was reading.
- **CV-REV-10**: The reviewer must not edit code, must not edit requirements documents, must not write the guidance file, and must not stop the loop. It writes bugs, and nothing else.
- **CV-REV-11**: The reviewer must not close a bug. It did not do the work that a close records.
- **CV-REV-12**: The reviewer must not log a task. Only a human user directs that record. The command refuses one from an agent of the loop, and the prompt must say so.
- **CV-REV-13**: The loop must log reviewer output the same way it logs worker output.

## Coach

- **CV-COACH-1**: After every `K` worker iterations, the loop must run the coach synchronously before the next worker starts.
- **CV-COACH-2**: The coach runs as a non-interactive harness invocation with permission prompts disabled, on the coach model.
- **CV-COACH-3**: The coach prompt must give the coach the paths to the log directory, the journal, and the guidance file.
- **CV-COACH-4**: The coach prompt must instruct the coach to:
  - **CV-COACH-4.1**: Read the worker logs since its previous run.
  - **CV-COACH-4.2**: Identify recurring problems across iterations. Examples: a wrong tool call that every worker makes before it recovers, or a trap that a sequence of iterations circles without escaping.
  - **CV-COACH-4.3**: Review its journal and judge each earlier intervention: did it help, hurt, or do nothing? Remove guidance that hurt or did nothing.
  - **CV-COACH-4.4**: Rewrite the guidance file. Keep it short. Each entry must be a concrete, corrective instruction for future workers.
  - **CV-COACH-4.5**: Read the bug history with `cbugs list` and `cbugs search`, and look for a pattern in it: a defect that the workers keep making, or a bug that a worker closed and a later pass reopened. A pattern in the bugs is evidence about the process, which is what the coach writes about.
  - **CV-COACH-4.6**: Append one journal entry that records what it observed, what it changed, and what result it expects.
- **CV-COACH-5**: The coach prompt must tell the coach that it may log a bug with `cbugs add`, and must not urge it to. The coach reads logs, not code, and the reviewer is the role that looks for defects. The coach must not log a task, for the reason that the reviewer must not.
- **CV-COACH-6**: The coach must write only the guidance file, the journal, and a bug. The coach must not edit code, must not edit requirements documents, and must not stop the loop.
- **CV-COACH-7**: The loop must log coach output the same way it logs worker output.

## State and logs

The loop keeps its files in two directories. The state directory is durable. The runtime directory is temporary.

- **CV-SL-1**: The loop must write nothing into the repository. This prevents interference with git.

### The state directory

- **CV-STATE-1**: The state directory holds everything that must survive a restart of the machine: the guidance file, the journal, the bug database, the commit of the last review pass, the harness of the last run, the logs, and the output of each session.
- **CV-STATE-2**: The path must be `$XDG_STATE_HOME/converge/<name>`. When `XDG_STATE_HOME` is empty, the loop must use `$HOME/.local/state` in its place. This follows the XDG Base Directory Specification, which names logs and history as state.
- **CV-STATE-3**: `<name>` must derive from the path of the run directory and must be stable. A new run in the same run directory must find the state of prior runs. This makes a restart seamless: the guidance file and the journal carry over.
- **CV-STATE-4**: `<name>` must also contain the name of the repository and the path of the run directory within it, so that an operator can read the directory listing and tell the run directories of one repository apart.
- **CV-STATE-5**: The guidance file is `guidance.md`. The journal is `journal.md`. `docs/cbugs-requirements.md` names the bug database, which lives beside them.
- **CV-STATE-6**: The bugs carry over from one run to the next, as the guidance and the journal do. An open code bug that a run did not fix is the first work of the next run.
- **CV-STATE-7**: The state directory must record the harness of the last run. A later run in the same run directory uses that harness when the operator gives no `--harness` option.
- **CV-STATE-8**: The loop must write the full output of each worker, reviewer, and coach invocation to one log file per invocation, in a format that includes every message, tool call, and tool result. Name the files so that the order of invocations is obvious, and so that files from different runs do not collide.
- **CV-STATE-9**: The loop must write its output to one file per session. The client reads that file. Beside it, the loop must record, at the end of the session, the exit status. The loop must record which session is the newest.
- **CV-STATE-10**: The loop must not delete the files of an earlier session. No component removes old files. The operator deletes the state directory when the disk space matters.
- **CV-STATE-11**: The logs must be sufficient for another agent to diagnose problems with the loop after the fact.

### The runtime directory

- **CV-RUN-1**: The runtime directory holds only the files that show that a process is alive now: the lock of the loop, the lock that gates the start of a loop, the process id of each session, and the pipes that the loop uses to read the output of a harness.
- **CV-RUN-2**: The path must be `$TMPDIR/converge/<name>`, with the same `<name>` as the state directory. When `TMPDIR` is empty, the loop must use `/tmp` in its place.
- **CV-RUN-3**: A pipe must stay in this directory. A home directory can be on a network file system, which does not support a pipe.
- **CV-RUN-4**: The system removes these files with the rest of the temporary directory. A lock or a process id that a dead loop leaves behind must not block a new run. The lock, and not a file, tells a client whether a loop runs.

### Identity of a run

- **CV-ID-1**: The loop must derive `<name>` from the absolute path of the run directory. A run directory that the operator moves or renames therefore gets a new state directory, and loses the guidance and the journal of the prior runs. The root of a repository and a subdirectory of it derive two names, and two run directories of one repository share no state.
- **CV-ID-2**: The loop must show at startup which state the run uses. The path of the run log is inside the state directory, and the panel gives that path, so the panel does not have to give the path of the state directory itself. The loop must not print the path of the runtime directory, which holds no file that a person reads.
- **CV-ID-3**: Each git worktree has its own path, and therefore its own state. This is correct: two worktrees hold different work, and need different guidance.
- **CV-ID-4**: If the guidance file exists and is not empty at startup, the loop must print its path. Guidance from an earlier run shapes every worker in this run, so the operator must see that it is there.
- **CV-ID-5**: The loop must create both directories when they do not exist.
- **CV-ID-6**: The startup panel must show the run directory. When the run directory is a subdirectory of the repository, the panel must show the subdirectory, and must not show the root of the repository in its place. The operator must see which directory the run works from.

## Signals, timeouts, and failures

- **CV-FAIL-1**: On the first SIGINT, the loop must let the running invocation finish, and must then stop. It must start no further invocation: no worker, no review pass, and no coach run. It must print that it stops on the request of the operator, show the closing report, and exit with status 130.
- **CV-FAIL-2**: On a second SIGINT, or on SIGTERM, the loop must terminate the running `claude` child process and exit promptly. The client sends the signal to the process group of the loop, so the signal reaches every agent below it.
- **CV-FAIL-3**: If an invocation exceeds the timeout, the loop must kill it, print a notice, log the event, and continue with the next iteration.
- **CV-FAIL-4**: A review pass that fails or that exceeds the timeout must not stop the loop, and must not count as a pass. The next pass examines the same range, and the commit of the last pass does not move.
- **CV-FAIL-5**: If an invocation exits with an error, the loop must log the event and continue with the next iteration.
- **CV-FAIL-6**: The loop must never stop because of failures.
- **CV-FAIL-7**: If an invocation fails before it produces output, the loop must wait before it starts the next iteration. The wait must double with each consecutive fast failure, from 10 seconds up to a maximum of 15 minutes. An invocation that produces output resets the wait to zero, whether it succeeds or fails. This keeps the loop alive when the token quota is exhausted, and lets it resume when the quota period resets.

## Out of scope

These are recorded decisions, not oversights.

- **CV-OOS-1** — **A task that an agent logs**: rejected. A task is a request from a human user. An agent that logs one invents work, and the next worker does it before the work that the requirements name. `cbugs` refuses `--kind task` when `CONVERGE_ROLE` is in the environment, so every agent of the loop is refused.
- **CV-OOS-2** — **A loop that reports the citations of a bug**: rejected for v1. The report of a review pass gives the id, the kind, and the title. A reader who wants the citation runs `cbugs show`.
- **CV-OOS-3** — **Loop-managed commits**: rejected. Workers commit as well as loop-enforced commits do, and the loop stays simpler.
- **CV-OOS-4** — **Worker notes between iterations**: rejected for v1. The guidance file and the bug database are the channels between iterations. A note that is not a defect and not process guidance has no channel, and needs none yet.
- **CV-OOS-5** — **Separate review agents**: rejected in v1, and adopted now. The earlier objection stands on its own terms: a review agent chases problems that the requirements do not name, and derails the project. The bug tracker answers it. A finding is now a durable record with a kind, not a message that pushes a worker off its work. A worker reads the open code bugs and decides; a finding that is wrong is dismissed and stays visible; and a finding that the requirements do not name has a place to go, as a spec bug that no agent acts on. What made a reviewer dangerous was that its output went straight into the next worker's head. It goes into a database instead.
- **CV-OOS-6** — **A reviewer that fixes what it finds**: rejected. The reviewer reads the code against the requirements. A reviewer that starts editing stops reading, and it becomes a worker that skipped the survey.
- **CV-OOS-7** — **A reviewer that closes a bug**: rejected. A close records that someone did the work. The reviewer did not.
- **CV-OOS-8** — **A loop that queries the bug database to decide**: rejected. The done vote is the only signal the loop reads. A done vote makes the loop schedule a review pass, and the pass and the worker settle the rest between them. The loop reads the bug list only to report what a pass logged.
- **CV-OOS-9** — **A record of a review pass that found no defect**: rejected. The loop records the commit of the last pass, which is what the next pass needs. The bug database holds defects.
- **CV-OOS-10** — **Coach authority to halt the loop or edit the repository**: rejected for v1. A bad coach judgment must cost at most a few misguided iterations.
- **CV-OOS-11** — **Cost or token budgets**: rejected for v1. `--max-iterations` and the operator bound the run.
- **CV-OOS-12** — **Coach-selected cadence**: rejected for v1. A fixed `K` is simpler and easier to reason about. The same holds for `R`.
- **CV-OOS-13** — **A key that detaches the client but keeps the loop**: rejected for v1. Ctrl-C stops the run. The state directory makes a restart cheap.
- **CV-OOS-14** — **`--status` and `--stop` commands**: rejected for v1. To see a loop, attach to it.
- **CV-OOS-15** — **Two clients on one loop**: not a supported case. It does no harm, and either client can stop the loop.
- **CV-OOS-16** — **Plain text output**: rejected. Every client is a terminal that accepts color.
- **CV-OOS-17** — **Automatic fallback from one harness to another**: rejected for v1. A run that fails on one harness tells the operator something. A run that changes harness on its own hides it.
- **CV-OOS-18** — **Removal of old logs**: rejected for v1. The state directory grows by one log file for each invocation. The operator deletes the directory. An automatic rule that removes the wrong file costs more than the disk space.
- **CV-OOS-19** — **`XDG_RUNTIME_DIR` for the locks and the pipes**: rejected. macOS supplies no such variable, so the script would need a second code path for the fallback. `TMPDIR` gives one code path on both platforms.
- **CV-OOS-20** — **`~/Library/Application Support` on macOS**: rejected. The XDG paths are usual for a command line tool on macOS, and they keep one code path.
- **CV-OOS-21** — **Migration of the state of an earlier version from the temporary directory**: rejected. The system removes that state on its own.
- **CV-OOS-22** — **Identity of a repository from the git remote**: rejected. A repository can have no remote, and two clones of one remote hold different work.
- **CV-OOS-23** — **A scope that the state directory records**: rejected. The harness is a property of a run directory, and carries over. A scope is the answer to "what do I work on now", which changes from one run to the next. A run with no positional argument therefore works on the whole run directory, and never on a scope that an earlier run left behind.
- **CV-OOS-24** — **A scope that names a requirement identifier, as `docs/x.md:CV-INV-3`**: rejected for v1. A file or a directory is enough to point a run at part of the project. A citation names one requirement; a scope names a body of work.
- **CV-OOS-25** — **A state directory shared by the run directories of one repository**: rejected. The guidance, the journal, and the bugs describe the work of one run directory. A run in a second directory that shared them would act on guidance for work that it cannot see, and the two runs would write one bug list that neither one owns.
- **CV-OOS-26** — **An option or an environment variable of the client that points the run at another run directory**: rejected. The current directory names the run directory, and an operator who wants another one changes directory. A pointer that can disagree with the current directory is a second anchor, and a silent wrong anchor is the failure that the run-directory design removes. This rejects a pointer for the operator, not the variable that the loop exports for the bug tracker (**CV-ENV-6**): the loop sets that variable, and no option of the client sets it.
