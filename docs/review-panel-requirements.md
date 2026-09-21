# Requirements: review-panel

`review-panel` checks the current code against requirements documents. It runs a panel of reviewer profiles once. Reviewers file code bugs and spec bugs through `cbugs`. A separate agent then combines duplicate findings. The command reports the result and exits. It does not run a converge loop.

This document defines behavior, not an implementation plan.

## Requirement identifiers

Each requirement has a stable identifier of the form `RP-<SECTION>-<number>`. A citation can name a requirement as `docs/review-panel-requirements.md:RP-REV-1`.

An identifier must not change its meaning. Removed requirements leave their identifiers unused. New requirements use the next free number in their section. Section introductions and terms provide context. Required behavior belongs in identified items.

## Terms

- **Run directory**: the current working directory when the operator starts the command.
- **Panel run**: one command invocation, including its reviewers, duplicate merge pass, and closing report.
- **Profile**: a harness, model, and optional effort setting in the form `harness:model[:effort]`.
- **Reviewer**: an agent that checks the code against the requirements and files bugs.
- **Merge agent**: the agent that combines duplicate bugs after the reviewers finish.
- **New bug**: a bug created by a reviewer in this panel run. A bug from an overlapping run is not a new bug of this run.
- **Retained new bug**: a new bug that the merge pass does not close as a duplicate. A new duplicate combined into an existing bug is not a retained new bug.
- **Complete run**: a run in which every configured reviewer and the required merge pass finish successfully, and required result recording succeeds.
- **Scope**: the requirements files or directories named by the operator. An empty scope lets reviewers find the requirements.

## Relationship to existing commands

- **RP-REL-1**: `review-panel` must be a separate command at `bin/review-panel`.
- **RP-REL-2**: The command must use the run directory rules and requirements scope rules of `docs/converge-requirements.md:CV-INV-9` and `CV-SCOPE-1` through `CV-SCOPE-6`.
- **RP-REL-3**: The command must share the run directory's existing `cbugs` database with converge. It must use the same database selection and state directory rules. It must not create a separate bug store for the panel.
- **RP-REL-4**: The command must reuse applicable converge harness, timeout, log, and agent-output conventions. This document takes priority for panel scheduling, concurrent operation, attribution, coverage, summaries, and exit status. Reuse does not require converge's worker loop, coach, voting, background attachment, or single-loop lock.

## Invocation and scope

- **RP-INV-1**: The command must accept positional requirements file or directory paths. It must resolve them against the run directory. A missing path must cause an error that names the path before any agent starts.
- **RP-INV-2**: With no scope paths, each reviewer must find requirements documents under the run directory. With scope paths, each reviewer must judge the requirements in those paths. A directory includes requirements documents below it.
- **RP-INV-3**: The scope must not restrict review to a diff or commit range. Each reviewer must check the current code relevant to the scope, including uncommitted changes and relevant untracked files.
- **RP-INV-4**: The command must accept `--timeout <seconds>` with the same validation as converge. The default must be 3600 seconds for each agent invocation, including the merge pass.
- **RP-INV-5**: Profile selection must use environment variables only. The command must reject unknown options and must not pass them to a harness.
- **RP-INV-6**: The run directory must be the initial working directory of each agent. Each agent must have access to `cbugs` on PATH. Database selection must remain anchored to the run directory if an agent changes its working directory.

## Profiles

- **RP-PROF-1**: `REVIEW_PANEL_PROFILES` must select an ordered, comma-separated list of reviewer profiles. If it is unset, the command must use `CONVERGE_REVIEWER_PROFILE`. If both are unset, it must use the converge reviewer default, currently `claude:opus`.
- **RP-PROF-2**: An explicitly empty selected variable must be an error, not a request for fallback.
- **RP-PROF-3**: Profiles must follow the syntax, canonical form, supported harnesses, and effort rules of `docs/converge-requirements.md:CV-HARN-9` and `CV-HARN-10`. Duplicate canonical reviewer profiles must be rejected.
- **RP-PROF-4**: `REVIEW_PANEL_MERGE_PROFILE` must select exactly one merge profile. If it is unset, the command must use the first resolved reviewer profile. An empty or invalid value must be an error.
- **RP-PROF-5**: The command must validate the resolved reviewer list and merge profile before it starts any agent. It must not require valid worker or coach profiles. A missing harness must fail its invocation under the converge harness convention.
- **RP-PROF-6**: The command must resolve profiles once at startup. It must not rotate profiles between runs or store a profile selection for later runs.

## Reviewer execution

- **RP-REV-1**: The command must start one review invocation for each configured reviewer profile. It must run the reviewers concurrently, without waiting for one reviewer to finish before starting another. An operator stop can prevent invocations that have not started.
- **RP-REV-2**: Each reviewer must independently check the code against the selected requirements. Review must not stop because another reviewer found no bugs or filed bugs.
- **RP-REV-3**: Reviewer prompts must apply the converge reviewer rules. Reviewers must search existing bugs before filing findings. They must file code defects as code bugs and unclear, missing, or contradictory requirements as spec bugs. They must cite the relevant requirements for code bugs.
- **RP-REV-4**: Reviewers must file findings directly through `cbugs`. They must not fix code, edit requirements or guidance, close bugs, create tasks, or create commits. Finding no defect is a valid result.
- **RP-REV-5**: Reviewers must read the live working tree. The command must not require a clean tree or create a fixed review snapshot. Changes to code, requirements, or HEAD during the run must not by themselves fail the run. The result must not claim that every reviewer examined identical content.
- **RP-REV-6**: A failed or timed-out reviewer must not cause a retry or fallback invocation. Other reviewers must be allowed to finish. The run must remain incomplete even if later steps succeed.
- **RP-REV-7**: The command must not repeat review to seek agreement, fix findings, or reach convergence. The merge pass is a separate role, not another code review.

## Concurrent runs and attribution

- **RP-RUN-1**: A panel run must be allowed to overlap with converge and other panel runs in the same run directory. It must not attach to, stop, or take ownership of another run.
- **RP-RUN-2**: Each panel run must have a distinct identity. Each bug created by its reviewers must be attributable to that run and to the reviewer invocation and profile that created it. Attribution must remain correct when processes write to the database concurrently.
- **RP-RUN-3**: The command must use run attribution to select findings for its merge pass and summary. A database-wide count difference or time interval alone must not define the run's findings.
- **RP-RUN-4**: Concurrent runs must not overwrite each other's logs, output, or result records. Stopping a panel must not stop agents from another run.
- **RP-RUN-5**: Reviewers must retain the normal cbugs agent authorship rules. Panel identity and profile attribution must supplement those rules, not impersonate a human caller. The required attribution is a shared cbugs integration contract; this document does not prescribe its storage format.

## Duplicate merge pass

- **RP-MERGE-1**: After all started reviewers finish or fail, the command must run one merge-agent invocation when this panel created bugs. If the panel created no bugs, it must skip the merge invocation.
- **RP-MERGE-2**: The merge pass must still run on available findings after a reviewer failure. It must not clear the failed run status.
- **RP-MERGE-3**: The merge agent must compare this run's new bugs with each other and with existing bugs, including bugs from overlapping runs. It must combine bugs only when they describe the same defect. It must preserve distinct findings.
- **RP-MERGE-4**: The merge agent may update a retained bug, including an existing bug, to preserve unique evidence and requirement citations from a duplicate. It may close only bugs created by this panel run. A duplicate closure must identify the retained bug and explain the duplicate relationship.
- **RP-MERGE-5**: Combining duplicates must preserve useful details and revision history. The merge agent must not delete bugs, fix code or requirements, create tasks, file unrelated findings, or close a bug as fixed. Combining spec duplicates does not resolve the underlying spec issue.
- **RP-MERGE-6**: The merge agent must account for current bug state before changing it. Concurrent merging must not leave a duplicate set with no retained bug or with circular duplicate references. It must not discard changes made by other writers.
- **RP-MERGE-7**: A failed or timed-out merge pass must make the run incomplete. The command must not retry it automatically. It must preserve findings and completed revisions and identify the summary as incomplete.

## Review coverage

- **RP-COV-1**: At startup, the controller must capture the commits pending review for the run directory under the existing cbugs coverage rules.
- **RP-COV-2**: After a complete review and merge phase, the controller must record coverage for the captured commits through the existing cbugs review-record mechanism. Agents must not record coverage themselves.
- **RP-COV-3**: Coverage records must identify the successful reviewer profiles under the cbugs profile-record rules. The merge profile must not count as a reviewer. Coverage must not imply that defects were absent.
- **RP-COV-4**: The controller must record only commits captured at startup. It must record them even if HEAD changed during the run. Commits added after startup must not receive coverage from this run.
- **RP-COV-5**: A reviewer failure, merge failure, or interrupted run must prevent coverage recording. Failure to record required coverage must make the run incomplete.
- **RP-COV-6**: Coverage must not grant converge final approval, supply a done vote, or claim convergence. It records completion of this live-tree review, not approval of a fixed snapshot.

## Output and result

- **RP-OUT-1**: Startup output must show the requirements scope, reviewer profiles, merge profile, timeout, and relevant state and log paths. It must say that the panel reviews the live working tree.
- **RP-OUT-2**: Progress and agent output must follow converge's applicable display conventions. Each invocation and its output must identify its role and full canonical profile. Concurrent output must remain attributable to its source.
- **RP-OUT-3**: The closing report must show separate counts for retained new spec bugs and retained new code bugs. It must list their IDs and titles. It must exclude new bugs closed as duplicates and bugs created by other runs.
- **RP-OUT-4**: If a complete run retains no new bugs, the command must print a brief success message, such as `Review complete. No new bugs found.` This message must not claim that no existing bugs remain.
- **RP-OUT-5**: A run that retains only spec bugs must show the spec findings, not the no-new-bugs message.
- **RP-OUT-6**: An incomplete run must identify failed profiles and failed phases. It must show the available findings and state that the summary is incomplete. It must not print an unqualified success message.
- **RP-OUT-7**: Exit status must be `0` for a complete run with no retained new code bugs, `1` for a complete run with retained new code bugs, and `2` for an invalid or incomplete run. Errors take priority over finding counts. Existing bugs and new spec bugs alone must not cause status `1`.
- **RP-OUT-8**: Signal handling must follow the applicable converge stop conventions, including status `130` for an operator Ctrl-C stop. An interrupted panel must not claim completion. Any cleanup must be limited to this panel's processes.
- **RP-OUT-9**: The closing report must include total run duration. Logs must identify the panel run, each agent profile, and each invocation result under the applicable converge log conventions.

## Out of scope

- **RP-OOS-1**: The command must not run workers, a coach, repair iterations, or a reviewer consensus loop.
- **RP-OOS-2**: The command must not require a vote from reviewers or require them to agree on findings.
- **RP-OOS-3**: The command must not replace cbugs with a separate report store or hide findings until all reviewers finish.
