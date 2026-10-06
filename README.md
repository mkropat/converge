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
- GNU `timeout`, `tail`, `flock`, and `setsid`.
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
children immediately. An operator stop returns status `130`.

### Review, coaching, and completion

Cadence reviews run when at least five unreviewed commits affect the run
directory, including commits from before the session. Successful reviews
record coverage in `cbugs`, so restarting does not discard it. The coach runs
after five worker iterations, then every ten iterations.

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
| `--timeout seconds` | `3600` | Duration limit for each agent invocation. |
| `--max-iterations N` | Unbounded | Limit worker iterations, including failed or timed-out calls. |
| `--foreground` | Background | Run in the current terminal. |
| `--init-state` | — | Create state and runtime directories, print the state path, and exit without agents. Use alone or with `--help`. |

Convergence returns status `0`; reaching the worker limit without convergence
returns `1`. Agent failures are logged and retried by the loop rather than
ending it. There is no mandatory test command: verification follows the project
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
Explicitly empty profile variables are errors; panels also reject duplicate
canonical reviewer profiles.

Model names are passed unchanged. Codex needs the full model ID accepted by
`codex exec`; short aliases are not expanded. Optional effort maps to Claude's
`--effort`, OpenCode's `--variant`, or Codex's `model_reasoning_effort`. Omitting
it leaves the harness default.

The commands reject unknown options and do not pass arguments through to the
harness. The old `--harness`, `--model`, `--coach-model`, and `--review-model`
options are retired. Run `converge --help` for command help.

## Run a standalone review

`review-panel` reviews the live working tree, including uncommitted changes and
relevant untracked files. It uses the panel profile variables above, runs each
reviewer concurrently, then uses a separate merge agent to combine duplicate
findings when there are new findings. It files code and spec bugs in the same
tracker as `converge`, records completed coverage, reports findings, and exits.
It does not run workers or repair iterations.

```sh
review-panel
review-panel --timeout 1800 docs/requirements.md
```

Exit status is `0` for a complete run with no retained new code bugs, `1` for a
complete run with retained new code bugs, and `2` for an invalid or incomplete
run. Existing bugs and new spec bugs alone do not cause status `1`. An operator
stop returns `130`. Review coverage records what was read; it does not approve
a fixed snapshot or claim convergence.

## Track bugs and human tasks

`cbugs` stores three kinds of records: `code` defects, `spec` ambiguities or
contradictions for a human to resolve, and human-requested `task` records.

```sh
cbugs                                            # Open-bug summary
cbugs list --kind code --kind task --status open
cbugs add --kind task --title 'Add CSV export' --note 'Include all visible rows.'
cbugs show 1
cbugs close 1 --note 'Implemented and verified CSV export.'
cbugs reviewed pending
```

Use `search` to find existing findings, `note` to append context, `dismiss` to
mark a record `wontfix`, and `reopen` to reopen it. Every verb supports `--json`;
run `cbugs <verb> --help` for its options.

Bug revisions are tied to commits. The current state uses the newest revision
reachable from the current Git `HEAD`; unreachable records are hidden rather
than deleted. Use `cbugs list --visibility all` to inspect them.

Agents receive `CONVERGE_ROLE`, `CONVERGE_ITERATION`, and `CONVERGE_RUN_DIR` for
provenance and database lookup, including after changing directories. `cbugs`
rejects task creation and review-coverage writes when `CONVERGE_ROLE` is set.

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

Runtime files and locks live under `${TMPDIR:-/tmp}/converge/<slug>/`. Set
`XDG_STATE_HOME` to choose a different durable state root. `HOME` or
`XDG_STATE_HOME` must be available. Logs are not automatically pruned; remove a
run directory's state when you no longer need its history.

## Behavior specifications

- [converge requirements](docs/converge-requirements.md)
- [review-panel requirements](docs/review-panel-requirements.md)
- [cbugs requirements](docs/cbugs-requirements.md)
- [cbugs database schema](docs/cbugs-schema.sql)
