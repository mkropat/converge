# converge

converge runs autonomous coding agents to bring a repository into agreement
with its requirements. Each worker iteration starts with a fresh context, reads
the requirements and current code, handles open code bugs and
operator-requested tasks, and chooses one useful change. Workers commit logical
changes; they do not keep a stored implementation plan or edit the
requirements.

A separate reviewer checks the code and files bugs in `cbugs`. A coach reads
session history and writes guidance for later workers. Bugs, coverage, coach
guidance, and logs persist between sessions.

## Setup

Required tools:

- Bash 4.3 or later (macOS's bundled Bash 3.2 is too old).
- `git`, `jq`, and `sqlite3`.
- Python 3 for `cbugs search`.
- GNU coreutils, including `timeout`, `tail`, and `date`; util-linux
  `flock` and `setsid`.
- An installed, configured agent harness for the profiles you use: `claude`,
  `opencode`, or `codex`.

On macOS, install the dependencies with Homebrew:

```sh
brew install bash jq sqlite coreutils util-linux python
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

With no scope arguments, a discovery agent selects requirements sources once
per session. It follows the project instructions. If those instructions give
no discovery rule, it finds requirements documents under the run directory.
Sources can be local files or external sources that the harness can read.
Later agents use the accepted lookup instructions to read the current sources.
The loop repeats discovery for each new session. Discovery failure stops
startup with status `2`.

To select requirements directly, pass document files or directories that
contain them. An explicit scope skips discovery:

```sh
converge docs/requirements.md docs/specs/
converge --foreground --max-iterations 10 docs/requirements.md
```

The default loop runs in the background and survives a lost terminal. Run
`converge` again in the same directory to attach to the existing loop. The
running loop keeps its original settings. `--foreground` runs it directly in
the terminal.

The first Ctrl-C requests a graceful stop: active invocations finish, and no
new invocations start. A second Ctrl-C, or SIGTERM, terminates active
invocations and their children immediately. Ctrl-C returns status `130`.
SIGTERM returns `143`.

### Review, coaching, refactoring, and stop conditions

The requirements now specify a Refactor agent. The code does not implement
this role yet. The required default is one pass after five new commits that
change paths in the run directory. `--refactor-after N` sets the threshold.
`--no-refactor` disables the role. These options are not implemented yet.

Refactor uses the worker profiles with a separate session rotation. It selects
work from the net difference between the session start commit and the commit
captured before the pass. Earlier session changes remain eligible on later
passes. Each pass must preserve project behavior and leave unrelated code
unchanged, including unrelated code in the same file.

The loop must skip Refactor when tracked files have staged or unstaged
changes. Untracked files do not prevent a pass. A skipped or failed pass stays
due, but a worker runs before the next pass. A successful pass resets the
commit count even when it makes no changes. Refactor commits do not count
toward the next pass. A new session starts a new scope and count.

Due review and coach work run before cadence Refactor passes. Stop conditions
take priority over those passes.

Each worker done vote also triggers Refactor before the vote panel and before
convergence or the worker-limit check. This applies even below the commit
threshold and with review disabled. Run one pass when both triggers are due.
If Refactor changes tracked code, clear done and blocked counts and cancel the
pending vote panel. This includes uncommitted changes left after a failure or
timeout. Return to a worker if the worker limit permits it.

If Refactor makes no tracked code changes, keep the vote. Run the vote panel
if due, then apply normal stop rules. Refactor failure, timeout, or skipping
does not block this path. With `--no-refactor`, use the existing vote and panel
behavior. Refactor commits enter normal review history. Refactor does not
count as a worker iteration or supply votes.

By default, cadence passes run when at least five unreviewed commits affect
the run directory. `cbugs reviewed pending` selects these commits from the
current local history.

On a feature branch, review history contains commits reachable from `HEAD` that
neither local `main` nor locally stored `origin/main` reaches. This includes
commits introduced through merges. Queries for unreviewed commits use current
local references and perform no fetch.

On local `main`, review history contains all commits reachable from `HEAD`.
The same fallback applies when neither base reference has a common ancestor
with `HEAD`. Missing base references cause no error. An empty feature-branch
selection does not trigger the fallback.

Both selections consider only the 1,000 newest commits that affect the run
directory. The limit applies before commits with coverage records are removed.
Commits from before the session can qualify. A cadence pass can run before the
first worker. Successful passes record coverage in `cbugs`, so restarting does
not discard it. A new commit hash after a rebase or amendment needs new
coverage. The first cadence pass uses the same commit boundary as later passes.
Vote panels continue to review the whole live working tree.

The coach runs after five worker iterations, then every ten iterations. Failed
and timed-out workers count toward this schedule. The coach also runs after a
blocked vote or three consecutive stalled chains. A chain is stalled when it
produces agent output, makes no new commit that affects the run directory, and
gives no done vote or blocked vote. Changes without a commit do not count as
progress. Failed chains with output can count as stalled. A chain without
output leaves the stall count unchanged. A new relevant commit or a worker
vote resets the stall count.

One coach chain handles all due triggers. A started coach chain resets the
stall count and the coach schedule, even if it fails or times out. The next
scheduled coach is due after ten more worker iterations. Stop conditions take
priority over due cadence passes and coaching.

By default, the loop stops successfully after two consecutive successful
worker chains emit `CONVERGED` alone on a line in their final message. Workers
are instructed to vote done only when no work, open code bugs, or open tasks
remain. The controller counts the votes; it does not check bug counts or require
approval of a Git `HEAD`. Only the successful attempt of a chain supplies its
vote. A failed attempt before that success does not reset the count. A worker
non-vote, failed chain, or timeout resets the count.

A worker can emit `BLOCKED` alone on a line in its final message when every
remaining piece of work has a blocker. No open code bug or task that the
worker can do may remain. The worker must name each blocker and the work that
it stops. It must record a spec blocker as a spec bug if no open spec bug
names it. It must do no work in an iteration that votes blocked. Hard work
alone is not a blocker.

By default, two consecutive blocked votes stop the loop with status `3`.
The closing report includes the last blocked worker message. A blocked vote
resets the done count. A done vote, non-vote, failed chain, or timeout resets
the blocked count. A final message with both vote tokens gives no vote.
Reviews and coaching do not change either count. With `--no-coach`, blocked
votes still stop the loop.

The coach checks whether a blocker needs operator action or whether a worker
can do the work with better guidance. A successful coach chain can emit
`ESCALATE` alone on a line in its final message. This schedules one fixer
iteration on `CONVERGE_FIXER_PROFILE`, or on the worker list if that variable
is unset.
A fixer follows the worker rules and counts toward the iteration limit,
coach schedule, and worker votes. Later iterations return to the worker list.
A pending fixer does not survive the session.

When the done count first rises from zero to one, the loop runs a vote panel
on the live working tree and waits for it, including any duplicate merge,
before proceeding. The panel is advisory: new bugs and review failures do not
change the done count or prevent convergence. It also runs with `--consensus 1`.

| Option | Default | Effect |
| --- | --- | --- |
| `--consensus N` | `2` | Consecutive worker done votes required. `0` exits successfully without starting agents. |
| `--blocked N` | `2` | Positive number of consecutive blocked votes that stops the loop with status `3`. |
| `--stall-after K` | `3` | Positive number of consecutive stalled chains that makes the coach due. |
| `--stall-notify N` | `6` | Positive stall streak that sends the `stalled` notification. See "Notify the operator". |
| `--review-after N` | `5` | Positive number of unreviewed commits needed for a cadence pass. |
| `--no-review` | Review enabled | Disable both cadence passes and vote panels. |
| `--coach-first F` | `5` | Worker iterations before the first coach invocation; `0` runs it before the first worker. |
| `--coach-every K` | `10` | Positive number of worker iterations between coach invocations. |
| `--no-coach` | Coach enabled | Disable coaching and stall checks. Blocked votes still count. |
| `--timeout seconds` | `3600` | Duration limit for each agent invocation. `0` disables the time limit. |
| `--max-iterations N` | Unbounded | Limit worker iterations, including failed or timed-out invocations. `0` starts no agents. |
| `--foreground` | Background | Run in the current terminal. |
| `--init-state` | — | Create state and runtime directories, print the state path, and exit without agents. Combine only with `--help`; that prints help without creating state. |
| `--state-dir` | — | Print the state path for the current directory and exit. Create nothing. Combine only with `--help`. |

Convergence returns status `0`; reaching the worker limit without convergence
returns `1`. Invalid setup, invalid arguments, or failed requirements discovery
return `2`. Reaching the blocked-vote limit returns `3`.

Worker, reviewer, and coach failures are logged. The loop continues after
their fallback chains end. A chain without agent output causes a delay that
doubles from 10 seconds to a maximum of 15 minutes. Agent output from any
attempt resets the delay. There is no delay between attempts of one chain.
A missing harness fails when its first invocation starts. The commands do
not check harness availability in advance.

There is no mandatory test command for the projects that converge works on.
Verification follows the project requirements and agent instructions.

## Configure agents

Profiles come from environment variables, using comma-separated entries of the
form `harness:model[:effort]`. Supported harnesses are `claude`, `opencode`, and
`codex`.

| Variable | Default | Use |
| --- | --- | --- |
| `CONVERGE_WORKER_PROFILE` | `claude:sonnet` | Worker profiles, rotated per chain, with fallback. |
| `CONVERGE_FIXER_PROFILE` | Worker profile list | Profiles for one fixer iteration after coach escalation. |
| `CONVERGE_REVIEWER_PROFILE` | `claude:opus` | Cadence reviewer profiles, rotated per chain, with fallback; default for panels. |
| `CONVERGE_COACH_PROFILE` | `claude:opus` | Coach profiles, rotated per chain, with fallback. |
| `CONVERGE_REVIEW_PANEL_PROFILE` | Reviewer profile list | Panel reviewers, all run concurrently once per panel. |
| `CONVERGE_REVIEW_PANEL_MERGE_PROFILE` | First panel profile | Merge profiles, tried in order until one succeeds. |

For example, to use two different reviewers in each panel:

```sh
export CONVERGE_REVIEW_PANEL_PROFILE='claude:opus,claude:sonnet'
converge docs/requirements.md
```

To use a separate profile for fixer iterations:

```sh
export CONVERGE_FIXER_PROFILE='claude:opus'
converge docs/requirements.md
```

Each worker chain, cadence pass, and coach run starts with the next profile in
its rotation. If an attempt exits with a nonzero status, the chain tries the
next profile at once. It stops at the first success, or after it has tried
every profile once. A timeout does
not trigger a fallback. The next chain of a role starts after the last profile
that the role tried. Put profiles from more than one subscription in a list to
keep the loop running when one subscription hits its quota:

```sh
export CONVERGE_WORKER_PROFILE='claude:sonnet,codex:gpt-5-codex'
export CONVERGE_REVIEWER_PROFILE='claude:opus,codex:gpt-5-codex:high'
export CONVERGE_COACH_PROFILE='claude:opus,codex:gpt-5-codex'
```

When `CONVERGE_FIXER_PROFILE` is set, fixers use a separate rotation. They do
not advance the worker rotation. When it is unset, fixers use and advance the
worker rotation. Discovery starts at the first worker profile and does not
advance that rotation.

Role rotations restart with each loop session. Panel invocations do not advance
them. Each list rejects duplicate profiles after trimming spaces around its
entries. Model and effort fields must be nonempty when supplied. They cannot
contain spaces, commas, or colons. Explicitly empty profile variables are
errors. `converge` validates all six profile variables at startup, even for
disabled roles.

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
starting a new session. Run `converge --help` for command help.

## Notify the operator

The loop can run a command of your choice when it needs you. Set
`CONVERGE_NOTIFY` to a shell command line. The loop runs it with the message
on standard input. It does not know how to reach a chat service. The command
does.

```sh
export CONVERGE_NOTIFY='holler'
converge docs/requirements.md
```

The loop runs the command as `sh -c "$CONVERGE_NOTIFY" converge-notify <event>`.
A command that reads standard input, such as `holler`, needs nothing else. A
script can read the event name from its first argument or from
`CONVERGE_EVENT`. The loop also exports `CONVERGE_RUN_DIR`,
`CONVERGE_STATE_DIR`, `CONVERGE_SESSION`, `CONVERGE_ITERATION`, and, for a
session stop, `CONVERGE_EXIT`. For example, a script that posts to a Slack
webhook:

```sh
#!/bin/sh
# notify-slack: $1 is the event; the message arrives on stdin.
text=$(cat)
curl -sS --max-time 30 -X POST -H 'Content-type: application/json' \
  --data "$(jq -n --arg t "$text" '{text: $t}')" "$SLACK_WEBHOOK_URL"
```

The loop sends these events, and no others:

| Event | When |
| --- | --- |
| `converged` | The session converged. Status `0`. |
| `limit` | The session reached the worker limit without convergence. Status `1`. |
| `discovery-failed` | Requirements discovery failed. Status `2`. |
| `blocked` | The session stopped on blocked votes. Status `3`. The message holds the last blocked worker message. |
| `stalled` | Six consecutive worker chains made no commit and gave no vote, across coach runs. One message per streak. `--stall-notify` sets the count. |

An operator stop sends nothing. The first line of each message is
`converge <project>: <summary>`, so one chat can carry messages from several
projects. Messages hold at most 3,500 characters.

The loop reads the variable once, when the session starts. An attached client
does not change it. An unset or empty variable turns notification off. The loop
waits up to 300 seconds for the command. A failed or killed command is logged
and does not change the session result. The loop does not retry. The run log
records each event and the message text, never the command itself.

## Run a standalone review

`review-panel` reviews the live working tree, including uncommitted changes and
relevant untracked files. It uses the panel profile variables above, runs each
reviewer concurrently, then uses a separate merge agent to combine duplicate
new bugs when there are new bugs. The merge agent keeps the visible open bug
with the smallest numeric ID for each duplicate set. A closed or `wontfix`
bug cannot replace a new open bug. The merge agent can dismiss only bugs
created by its panel run. Panel reviewers file code and spec bugs in the same
tracker as `converge`. The panel reports the new bugs and exits. A complete
panel records coverage for the commits unreviewed at startup under each
reviewer profile. A failed reviewer, failed merge, or stopped panel run prevents
this coverage step.
Panel reviewers get no retry or fallback profile. The merge agent tries each
profile in its list in order until one succeeds. The merge still runs after a
reviewer failure if new bugs exist or the controller cannot read them.
An operator stop prevents a merge that has not started.

The panel does not run worker or fixer iterations.

```sh
review-panel
review-panel --timeout 1800 docs/requirements.md
```

Without an explicit scope, a standalone panel uses discovery through the
worker profile list. A vote panel uses the lookup instructions of its loop.
Failed discovery prevents reviewer and merge invocations.

Exit status is `0` for a complete run with no retained new code bugs, `1` for a
complete run with retained new code bugs, and `2` for an invalid or incomplete
run. Existing bugs and new spec bugs alone do not cause status `1`. An operator
Ctrl-C stop returns `130`; SIGTERM returns `143`. Review coverage records what
was read. It does not approve a fixed snapshot or claim convergence.

## Track bugs and tasks

`cbugs` stores three kinds of bug: `code` defects, `spec` ambiguities or
contradictions for the operator to resolve, and `task` requests from the
operator.

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

Use `search` to find existing bugs, `note` to append context, `dismiss` to
mark a bug `wontfix`, and `reopen` to reopen it. Every verb supports `--json`;
run `cbugs <verb> --help` for its options.

Search ignores letter case. It checks titles, notes, and citations in visible
revisions. `cbugs search -h` searches for the text `-h`. Use
`cbugs search --help` for search help. Use `cbugs search -- --help` to search
for the text `--help`.

Bug changes append immutable revisions. Each revision uses the current commit
unless you supply `--commit`. The current state uses the newest revision whose
commit is reachable from Git `HEAD`. Revisions with no commit are always
visible. A bug with no visible revision is hidden; its history remains stored.
Use `cbugs list --visibility all` to inspect hidden bugs.

The controllers set these variables for agent invocations:

| Variable | Value or purpose |
| --- | --- |
| `CONVERGE_ROLE` | `worker` (also for fixers), `reviewer`, `coach`, `discovery`, or panel `merge`. |
| `CONVERGE_ITERATION` | Worker iteration number for loop workers, fixers, reviewers, and coaches. Unset for discovery and panel agents. |
| `CONVERGE_RUN_DIR` | Absolute run path. `cbugs` uses it even after an agent changes directories. |
| `CONVERGE_REVIEW_PASS` | Cadence pass ID, set only for the reviewers of a cadence pass. `cbugs list --review-pass <id>` shows the bugs that the pass created. |
| `REVIEW_PANEL_RUN` | Panel run ID, set for panel agents. |
| `REVIEW_PANEL_PROFILE` | Full profile of the panel agent. |
| `REVIEW_PANEL_INVOCATION` | ID of that panel agent invocation. |

`cbugs` records this provenance. It rejects task creation and coverage
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
| `PATH` | Search path for tools and harness commands. The scripts add their own `bin` directory for agents and available Homebrew tool directories. |
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

For a session without explicit scope, the loop also sets
`CONVERGE_REQUIREMENTS_LOOKUP_REQUIRED=1` for vote panels. It passes the path
of the accepted lookup instructions in `CONVERGE_REQUIREMENTS_LOOKUP_FILE`.
The panel must read that file instead of repeating discovery. A missing or
invalid file stops the panel. Leave these internal variables unset for normal
command use.

Logs are not automatically pruned. Remove a run directory's state when you no
longer need its history.

## Tests

The tests check `converge`. They do not start a real agent. A fake harness
in `test/fake-harness` replaces `claude`, `opencode`, and `codex`. Each test
uses its own temporary home, state, and Git repository. The tests do not
change your own state.

The tests need the tools from "Setup" and no network.

To run all tests, run this command from the checkout:

```sh
test/run
```

To run one test file, give its path:

```sh
test/run test/test_votes.sh
```

To run only the tests whose names contain a word, use `-k`:

```sh
test/run -k timeout
```

To show the output of each test, use `-v`. To set the number of tests that
run at the same time, use `-j`.

The runner shows `ok`, `FAIL`, `skip`, or `xfail` for each test. `xfail`
identifies a known bug. When a fix makes that test pass, the runner shows
`FAIL`. Then remove the known-failure mark from the test.

To add a test, add a function with a name that starts with `test_` to a
`test/test_*.sh` file. Use the helpers in `test/lib.sh`.

## Behavior specifications

- [converge requirements](docs/converge-requirements.md)
- [review-panel requirements](docs/review-panel-requirements.md)
- [cbugs requirements](docs/cbugs-requirements.md)
- [cbugs database schema](docs/cbugs-schema.sql)
