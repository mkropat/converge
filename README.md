# converge

converge runs autonomous coding agents to bring a repository into agreement with
its requirements. Each worker iteration starts with a fresh context, reads the
requirements and current code, handles open code bugs and human-requested tasks,
and chooses one useful change. Workers commit logical changes; they do not keep
a stored implementation plan or edit the requirements.

A separate reviewer checks the code and files findings in `cbugs`. A coach reads
run history and writes guidance for later workers. Bugs, review coverage, coach
guidance, and logs persist between runs.

## Setup

Required tools:

- Bash 4.3 or later (macOS's bundled Bash 3.2 is too old).
- `git`, `jq`, and `sqlite3`.
- GNU coreutils, including `timeout`, `tail`, and `date`; util-linux
  `flock` and `setsid`.
- An installed, configured agent harness for the profiles you use: `claude`,
  `opencode`, or `codex`.

On macOS, install the dependencies with Homebrew:

```sh
brew install bash jq sqlite coreutils util-linux
```

Make sure the installed Bash is on your `PATH`. The scripts locate Homebrew's
GNU tools through `HOMEBREW_PREFIX`, `/opt/homebrew`, or `/usr/local` and add them
to their own `PATH`.

From this checkout, add the commands to your shell's `PATH`:

```sh
export PATH="$PWD/bin:$PATH"
```

Agents run directly with permission bypass or automatic approval. The commands
do not provide their own sandbox.

## Run the loop

Change to the repository or subdirectory you want the agents to work in:

```sh
cd /path/to/project
converge
```

With no scope arguments, agents find requirements documents under the directory
where you start the command. To select requirements explicitly, pass document
files or directories containing them:

```sh
converge docs/requirements.md docs/specs/
converge --foreground --max-iterations 10 docs/requirements.md
```

The default loop runs in the background and survives a lost terminal. Run
`converge` again in the same directory to attach to the existing loop. The
running loop keeps its original settings. `--foreground` runs it directly in
the terminal.

The first Ctrl-C requests a graceful stop: active agent calls finish, and no
new calls start. A second Ctrl-C, or SIGTERM, terminates active calls and their
children immediately. Ctrl-C returns status `130`. SIGTERM returns `143`.

### Review, coaching, and completion

By default, cadence reviews run when at least five unreviewed commits affect
the run directory. The pending count covers the 1,000 newest relevant commits
reachable from `HEAD`, including commits from before the session. A review can
run before the first worker. Successful reviews record coverage in `cbugs`, so
restarting does not discard it. A new commit hash after a rebase or amendment
needs new coverage.

The coach runs after five worker iterations, then every ten iterations. Failed
and timed-out workers count toward this schedule. A failed coach call also
resets its schedule. Stop conditions take priority over due reviews and coaching.

By default, the loop stops successfully after two consecutive successful
workers emit `CONVERGED` alone on a line in their final message. Workers are
instructed to vote only when no work, open code bugs, or open human tasks remain.
The controller counts the votes; it does not check bug counts or require
approval of a Git `HEAD`. A worker non-vote, failure, or timeout resets the count.

When the vote count first rises from zero to one, the loop runs a review panel
on the live working tree and waits for it, including any duplicate merge,
before proceeding. The panel is advisory: findings and review failures do not
reset votes or prevent convergence. It also runs with `--consensus 1`.

| Option | Default | Effect |
| --- | --- | --- |
| `--consensus N` | `2` | Consecutive worker votes required. `0` exits successfully without starting agents. |
| `--review-after N` | `5` | Positive number of unreviewed commits needed for a cadence review. |
| `--no-review` | Review enabled | Disable both cadence reviews and vote panels. |
| `--coach-first F` | `5` | Worker iterations before the first coach call; `0` runs it before the first worker. |
| `--coach-every K` | `10` | Positive number of worker iterations between coach calls. |
| `--no-coach` | Coach enabled | Disable coaching. |
| `--timeout seconds` | `3600` | Duration limit for each agent invocation. `0` disables the time limit. |
| `--max-iterations N` | Unbounded | Limit worker iterations, including failed or timed-out calls. `0` starts no agents. |
| `--foreground` | Background | Run in the current terminal. |
| `--init-state` | — | Create state and runtime directories, print the state path, and exit without agents. Combine only with `--help`; that prints help without creating state. |

Convergence returns status `0`; reaching the worker limit without convergence
returns `1`. Invalid setup or arguments return `2`. Agent failures are logged;
the loop continues with the next scheduled call. Calls with no agent output
cause a delay that doubles from 10 seconds to a maximum of 15 minutes. A call
with agent output resets the delay. A missing harness fails when its first call
starts; there is no advance harness availability check.

There is no mandatory test command. Verification follows the project
requirements and agent instructions.

## Configure agents

Profiles come from environment variables, using comma-separated entries of the
form `harness:model[:effort]`. Supported harnesses are `claude`, `opencode`, and
`codex`.

| Variable | Default | Use |
| --- | --- | --- |
| `CONVERGE_WORKER_PROFILE` | `claude:sonnet` | Worker profiles, rotated per invocation. |
| `CONVERGE_REVIEWER_PROFILE` | `claude:opus` | Cadence reviewer profiles, rotated per invocation; fallback for panels. |
| `CONVERGE_COACH_PROFILE` | `claude:opus` | Coach profiles, rotated per invocation. |
| `CONVERGE_REVIEW_PANEL_PROFILE` | Reviewer profile list | Panel reviewers, all run concurrently once per panel. |
| `CONVERGE_REVIEW_PANEL_MERGE_PROFILE` | First panel profile | One profile for combining duplicate findings. |

For example, to use two different reviewers in each panel:

```sh
export CONVERGE_REVIEW_PANEL_PROFILE='claude:opus,claude:sonnet'
converge docs/requirements.md
```

Role rotations restart with each loop session. Panel calls do not advance them.
Each list rejects duplicate profiles after trimming spaces around its entries.
Model and effort fields must be nonempty when supplied. They cannot contain
spaces, commas, or colons. Explicitly empty profile variables are errors.
`converge` validates all five variables at startup, even for disabled roles.

Model names are passed unchanged. Codex needs the full model ID accepted by
`codex exec`; short aliases are not expanded. Optional effort maps to Claude's
`--effort`, OpenCode's `--variant`, or Codex's `model_reasoning_effort`. Omitting
it leaves the harness default. The scripts accept Claude efforts `low`,
`medium`, `high`, `xhigh`, and `max`. OpenCode variants and Codex efforts pass
through without local value validation. Their harnesses decide which values
the selected model accepts.

The commands reject unknown options and do not pass arguments through to the
harness. The old `--harness`, `--model`, `--coach-model`, and `--review-model`
options are retired. New loops also reject `CONVERGE_HARNESS`,
`CONVERGE_CLAUDE_MODEL`, `CONVERGE_CLAUDE_REVIEW_MODEL`,
`CONVERGE_CLAUDE_COACH_MODEL`, `CONVERGE_OPENCODE_MODEL`,
`CONVERGE_OPENCODE_REVIEW_MODEL`, and `CONVERGE_OPENCODE_COACH_MODEL`, even when
empty. `review-panel` rejects the old `REVIEW_PANEL_PROFILES` and
`REVIEW_PANEL_MERGE_PROFILE` variables. Unset these retired variables before
starting a new run. Run `converge --help` for command help.

## Run a standalone review

`review-panel` reviews the live working tree, including uncommitted changes and
relevant untracked files. It uses the panel profile variables above, runs each
reviewer concurrently, then uses a separate merge agent to combine duplicate
findings when there are new findings. It files code and spec bugs in the same
tracker as `converge`, reports findings, and exits. A complete panel records
coverage for the commits pending at startup under each reviewer profile. A
failed reviewer, failed merge, or stopped run prevents this coverage step.
Panel calls get no retry or fallback profile. The merge still runs after a
reviewer failure if findings exist or the controller cannot read the findings.
An operator stop prevents a merge that has not started.

The panel does not run workers or repair iterations.

```sh
review-panel
review-panel --timeout 1800 docs/requirements.md
```

Exit status is `0` for a complete run with no retained new code bugs, `1` for a
complete run with retained new code bugs, and `2` for an invalid or incomplete
run. Existing bugs and new spec bugs alone do not cause status `1`. An operator
Ctrl-C stop returns `130`; SIGTERM returns `143`. Review coverage records what
was read. It does not approve a fixed snapshot or claim convergence.

## Track bugs and human tasks

`cbugs` stores three kinds of records: `code` defects, `spec` ambiguities or
contradictions for a human to resolve, and human-requested `task` records.

```sh
cbugs                                            # Open-bug summary
cbugs list --kind code --kind task --status open
task_id=$(cbugs add --kind task --title 'Add CSV export' \
  --note 'Include all visible rows.')
cbugs show "$task_id"
# After you implement and verify the task:
cbugs close "$task_id" --note 'Implemented and verified CSV export.'
cbugs reviewed pending
```

Use `search` to find existing findings, `note` to append context, `dismiss` to
mark a record `wontfix`, and `reopen` to reopen it. Every verb supports `--json`;
run `cbugs <verb> --help` for its options.

Bug changes append immutable revisions. Each revision uses the current commit
unless you supply `--commit`. The current state uses the newest revision whose
commit is reachable from Git `HEAD`. Revisions with no commit are always
visible. A bug with no visible revision is hidden; its history remains stored.
Use `cbugs list --visibility all` to inspect hidden records.

The controllers set these variables for agent calls:

| Variable | Value or purpose |
| --- | --- |
| `CONVERGE_ROLE` | `worker`, `reviewer`, `coach`, or panel `merge`. |
| `CONVERGE_ITERATION` | Worker iteration number for loop roles. Unset for panel agents. |
| `CONVERGE_RUN_DIR` | Absolute run path. `cbugs` uses it even after an agent changes directories. |
| `REVIEW_PANEL_RUN` | Panel run ID, set for panel agents. |
| `REVIEW_PANEL_PROFILE` | Full profile of the panel agent. |
| `REVIEW_PANEL_INVOCATION` | ID of that panel agent call. |

`cbugs` records this provenance. It rejects task creation and review-coverage
writes whenever `CONVERGE_ROLE` is set, including an empty value.

## State and logs

Controller state lives outside the repository, under
`${XDG_STATE_HOME:-$HOME/.local/state}/converge/<slug>/`. The slug includes the
repository name, run subdirectory, and a hash of the absolute run path. Starting
loops in different directories gives them separate state; moving a checkout
also changes its state path.

The state includes `cbugs.db`, `guidance.md`, `journal.md`, `converge.log`, agent
logs under `logs/`, terminal transcripts under `sessions/`, and
`cost-history.tsv`. Graceful closing reports show session and cumulative
recorded costs. Missing harness cost data remains unknown rather than counting
as zero.

`cbugs` and standalone `review-panel` use existing state for the current
directory, or the nearest ancestor with state up to the repository root. Use
`converge --init-state` in a subdirectory to give it its own state explicitly.

Other environment variables control paths and display:

| Variable | Default or purpose |
| --- | --- |
| `XDG_STATE_HOME` | Durable state root. Defaults to `$HOME/.local/state`. |
| `TMPDIR` | Temporary file root. Defaults to `/tmp`. Runtime files and locks use `converge/<slug>/` under it. |
| `HOMEBREW_PREFIX` | Additional location for Homebrew tool discovery. The scripts also check `/opt/homebrew` and `/usr/local`. `cbugs` looks for Homebrew SQLite too. |
| `HOME` | Supplies the default state root. `HOME` or `XDG_STATE_HOME` must be available. |
| `CONVERGE_COLS` | Optional output width in columns. Otherwise the scripts use terminal width, limited to 40–96 columns, or `80` if unavailable. The override is used as supplied. |

The background launcher sets `CONVERGE_DAEMON` and `CONVERGE_SESSION` itself.
The parent loop passes `CONVERGE_SESSION` and an absolute
`CONVERGE_COST_LEDGER` path to panels so they share its cost records. A standalone
panel creates its own cost session when both variables are unset or both are
empty. A partial pair, or a nonempty relative ledger path, is an error. Leave
these controller variables unset for normal command use.

Logs are not automatically pruned. Remove a run directory's state when you no
longer need its history.

## Behavior specifications

- [converge requirements](docs/converge-requirements.md)
- [review-panel requirements](docs/review-panel-requirements.md)
- [cbugs requirements](docs/cbugs-requirements.md)
- [cbugs database schema](docs/cbugs-schema.sql)
