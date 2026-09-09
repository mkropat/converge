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
- One agent harness: `claude` or `opencode`.

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

## State

`converge` writes nothing into your repository. It keeps the guidance, the
journal, the bugs, and the logs in `~/.local/state/converge/`, and the locks in
the temporary directory. The state carries over from one run to the next, so a
restart keeps what the coach learned.

Nothing removes the old logs. Delete the directory of a repository when you no
longer need them.
