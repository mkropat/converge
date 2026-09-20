# converge

Tools that run autonomous agent iterations against a repository.

## Commands

- `bin/converge` — run agent iterations until a project satisfies its
  requirements documents. See [docs/converge-requirements.md](docs/converge-requirements.md).
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
