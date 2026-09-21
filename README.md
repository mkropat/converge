# converge

converge runs autonomous coding agents to bring a repository into agreement with
its requirements. Each iteration starts with a fresh worker. The worker reads
the requirements, inspects the current code and open bugs, and chooses one
useful change. It decides what to do next from the current state, not from a
stored implementation plan.

Three roles keep the work directed: the worker changes the code, a separate
reviewer checks it against the requirements, and a coach uses run history to
correct recurring process failures. Bug history and coach guidance carry over
between iterations and runs.

By default, the loop finishes only after two consecutive worker votes that the
work is complete, no open code bugs or human-requested tasks, and a successful
final review of the current Git `HEAD`. These checks do not prove correctness
or require automated tests.

## Commands

- `bin/converge` — run agent iterations until a project satisfies its
  requirements documents. See [docs/converge-requirements.md](docs/converge-requirements.md).
- `bin/review-panel` — run a panel of reviewers once over the live working
  tree, merge their duplicate findings, and report. It files the findings
  into the same bug tracker as `converge` and does not run a loop.
- `bin/cbugs` — track the bugs of a converge project. The reviewer logs a bug,
  and a later worker fixes it. See
  [docs/cbugs-requirements.md](docs/cbugs-requirements.md) and
  [docs/cbugs-schema.sql](docs/cbugs-schema.sql).

## Requirements

- Bash 4 or later. macOS supplies bash 3.2, which is too old.
- `jq`.
- `sqlite3`, for `bin/cbugs`.
- The GNU versions of `timeout`, `tail`, `flock`, and `setsid`.
- An agent harness for each enabled role: `claude` or `opencode`.

Linux supplies the GNU tools. On macOS, install them with Homebrew:

```sh
brew install bash jq sqlite coreutils util-linux
```

`converge` finds the Homebrew versions. Your `PATH` does not change.

## Install

Add `bin` to your `PATH`:

```sh
export PATH="$PWD/bin:$PATH"
```

## Use

Go to the repository that you want to work on. Then run the command:

```sh
converge
```

The loop runs in the background. Run `converge` again in the same directory to
attach to the loop. Press Ctrl-C to stop the loop.

Run `converge --help` to see all options.

To review the current code once, with several reviewer agents at the same
time, run `review-panel` in the same directory:

```sh
review-panel [requirements-scope ...]
```

The panel reviews the live working tree, records the coverage it read in the
same bug database, and exits with status `0` when it retained no new code
bug, `1` when it did, and `2` when the run was invalid or incomplete.

## Environment variables

You set these variables to configure `converge`. Each holds a comma-separated
list of profiles of the form `harness:model[:effort]`, where harness is
`claude` or `opencode`. The role steps through its list in round-robin order,
one entry per invocation. `converge` accepts no `--harness`, `--model`,
`--coach-model`, or `--review-model` option.

| Variable | Meaning |
| --- | --- |
| `CONVERGE_WORKER_PROFILE` | Worker profile list. Default: `claude:sonnet`. |
| `CONVERGE_REVIEWER_PROFILE` | Reviewer profile list. Default: `claude:opus`. |
| `CONVERGE_COACH_PROFILE` | Coach profile list. Default: `claude:opus`. |

You set these variables to configure `review-panel`:

| Variable | Meaning |
| --- | --- |
| `REVIEW_PANEL_PROFILES` | Ordered, comma-separated reviewer profile list. Unset, the panel uses `CONVERGE_REVIEWER_PROFILE`. Unset, that defaults to `claude:opus`. |
| `REVIEW_PANEL_MERGE_PROFILE` | The single merge profile. Unset, the panel uses the first reviewer profile. |

`converge` also reads the standard variables `XDG_STATE_HOME`, `TMPDIR`,
`HOMEBREW_PREFIX`, and `HOME`:

- `XDG_STATE_HOME` — base of the state directory. Default: `$HOME/.local/state`.
- `TMPDIR` — base of the runtime directory. Default: `/tmp`.
- `HOMEBREW_PREFIX` — optional. On macOS, `converge` looks here first for the
  GNU tools, then in `/opt/homebrew` and `/usr/local`.
- `HOME` — `converge` needs `HOME` or `XDG_STATE_HOME` to find its state.

Each agent that the loop starts gets three variables in its environment:

- `CONVERGE_ROLE` — the role of the agent: `worker`, `reviewer`, or `coach`.
- `CONVERGE_ITERATION` — the number of the current iteration.
- `CONVERGE_RUN_DIR` — the absolute path of the run directory.

`cbugs` reads all three. It records the role and the iteration as the
provenance of each bug, and it uses the run directory to find the right bug
database even after an agent changes its own working directory. When
`CONVERGE_ROLE` is set, `cbugs add --kind task` fails, because a task is a
request from a human.

## State

`converge` writes nothing into your repository. It keeps the guidance, the
journal, the bugs, and the logs in `~/.local/state/converge/`, and the locks in
the temporary directory. The state carries over from one run to the next, so a
restart keeps what the coach learned.

Nothing removes the old logs. Delete the directory of a repository when you no
longer need them.

## Comparison with Ralph

Both loops use fresh agent contexts and saved state. The table compares
converge's implementation with Ralph's documented behavior, not an audit of
Ralph's source.

| Area | converge | Ralph |
| --- | --- | --- |
| Work selection | Each worker chooses one useful change from requirements, current code, and open bugs. No stored implementation plan. | Each iteration selects one incomplete task from a prepared task plan. |
| Review and guidance | Separate reviewer and coach roles check the code and correct recurring process failures. | Separate review is optional. A human supplies steering instructions. |
| Completion | By default, two consecutive worker votes, no open code bugs or tasks, and final review approval of the current `HEAD`. | The agent updates task status, runs checks, and emits a completion signal that the runner accepts. |
| Scope and history | Tracks code defects, requirements problems, and human-requested tasks separately, with revision history. Requirements problems do not block completion. | Stores task specifications, acceptance criteria, progress flags, and a journal. |
| State location | Keeps loop state outside the repository. | Keeps loop state in the project's `.agent/` directory. |
| Execution isolation | Launches agents directly with permission bypass or automatic approval. No built-in sandbox. | Runs agents in Docker Sandbox microVMs with filesystem and network controls. |
| Verification workflow | Leaves test procedures to project requirements and the agent harness. No mandatory test command. | Supplies testing and UI workflow instructions and skills. These are not independently enforced checks. |
| Agent selection | Supports Claude and OpenCode, with separate model rotation for each role. | Documents six agent backends, with operator-selected agents and models. |
| Run limits and human decisions | No worker-iteration limit by default. No dedicated signal to stop for a human decision. | Defaults to 10 iterations. Separate signals stop for a blocker or a human decision. |
