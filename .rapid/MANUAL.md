# rapid: developer manual

This manual is the reference for people who work in a repository that vendors
`.rapid/`. It states what the code does: every command and flag, every conf key,
the environment knobs, the hooks, the invariants, what to do when something is
refused, the test suite and the tools shipped beside the CLI.

The rules and their reasons are in [RULES.md](RULES.md), the flows step by step
in [FLOWS.md](FLOWS.md), the decisions in [DESIGN.md](DESIGN.md), the short
introduction in [README.md](README.md). Agents read [skill/SKILL.md](skill/SKILL.md).
Every scenario of the suite is listed in [tests/SCENARIOS.md](tests/SCENARIOS.md).

The words: the **pool** is every branch in flight, under `pool/v<series>/`; a
**branch** is one feature unit, `pool/v<series>/n<N>.<kind>.<slug>`; a **batch**
is the set of branches one developer lands, tested once and pushed once. dev is
integration. main is production: only a release moves it.

## 1. Install and first setup

rapid is a directory, `.rapid/`, copied into the repository. It needs git and
bash 3.2 or later; python3 runs the lints and the agent guard, and `gh` is
needed only for the forge commands. Nothing is installed on the machine unless
you ask for the agent guard (`rapid setup --agent`, which writes into the
Claude Code directory, section 9). The framework's scripts are bash scripts:
run them with `bash`, since `sh` is not bash on every system.

```sh
cp -R path/to/rapidgit/.rapid .
rm -rf .rapid/tests .rapid/bench .rapid/FRAMEWORK .rapid/admins
cat > .rapid/conf <<'CONF'
gates_fast=bash .rapid/lint/run.sh && sh login_test.sh
gates_full=bash .rapid/lint/run.sh && sh login_test.sh
gates_release=bash .rapid/lint/run.sh && sh login_test.sh
CONF
.rapid/rapid setup
```

Set the gates before the first setup: `rapid setup` refuses a conf whose gates
name a `.rapid/tests` or `.rapid/lint` script the repository does not have, and
a land refuses an unset `gates_full` (write `gates_full=none` to land without a
full gate). `login_test.sh` stands for the project's own test, committed by the
first branch (section 2, branch): a gate runs in a private work tree of the
committed tree, so a test file that is not committed fails the close.

| Command | What it does |
|---|---|
| `rapid setup` | sets `core.hooksPath` to `.rapid/hooks`, sets the REQUIREMENTS.md merge driver, and in a repository with no commit writes the root commit `[NEW] Seed the rapid workflow` holding `.rapid/`, as main, with dev beside it. With an origin that lacks main or dev it pushes them, dev with its tags. It never advances main afterwards. |
| `rapid setup --owner EMAIL` | at the first setup only: writes EMAIL as the first admin in `.rapid/admins`, in place of the one who runs setup. Refused in a repository that already has a commit, and when `.rapid/admins` already names an admin. |
| `rapid setup --agent [claude] [--uninstall] [--dry-run] [--prefix DIR]` | installs, or removes, the agent guard for Claude Code (section 9). `--dry-run` names each file it would write and writes nothing. |
| `rapid setup --remote [--repo OWNER/REPO] [--dry-run]` | applies the forge rulesets through `gh` and writes `.github/workflows/rapid-check.yml` for a branch to commit. `--dry-run` names each ruleset it would create or update and writes nothing. |
| `rapid setup --upgrade SOURCE [REV]` | on a branch: replaces the vendored `.rapid` with SOURCE's at REV (default dev) and stages it; `.rapid/conf`, `.rapid/admins` and `requirements/` are kept, the framework's tests, bench and source marker are not vendored. Commit the result and land the branch. |

Who becomes the first admin: without `--owner`, a human who runs the first
setup is written into `.rapid/admins`; an agent session writes none and says so.
The admins are the owner's file: they alone change policy and promote dev to
main (section 3). An agent that initializes a repository runs
`rapid setup --owner owner@team.test` in place of the plain `rapid setup` above;
in a repository that is already seeded it is refused, exit 1. With a forge as
origin and `gh` signed in, `rapid setup --remote --dry-run` shows the forge
rules before applying them.

## 2. Command reference

Exit codes are the same for every command: `0` done; `1` refused or failed, the
reason printed; `2` usage; `3` `land --pr` is waiting for approvals, or the forge
has not accepted a release merge yet; `4` a land met a conflict rebasing the
branch onto dev, and the branch is left as it was. `rapid -h` (or `--help`) prints the whole
usage, `rapid <verb> -h` the lines of one verb.

The commands that write (`branch`, `land`, `sync`, `release`, `commit`) refuse in
a clone where `rapid setup` never ran, naming it.

### branch

| Form | Effect |
|---|---|
| `rapid branch <kind> <slug> [-r TEXT] [--proof PATH] [--ticket ID]` | starts `pool/v<series>/n<N>.<kind>.<slug>` at dev and stages `requirements/<slug>.md` for the first commit. `-r` is the requirement text, `--proof` the test file or scenario slug written as its `Proof:` line, `--ticket` a tracker id (`CODE-123`) recorded in it. It writes the safety anchor `safety/v<series>/n<N>.<kind>.<slug>` on the fork point; nothing is pushed. |
| `rapid branch --rename NEW_SLUG` | gives the current branch a new slug; the requirement file follows through every commit of the branch. |
| `rapid branch --delete-landed [BRANCH...]` | deletes, on origin, landed branches that are still there (each named one, or all). A branch dev does not hold is never deleted. On a forge only an admin may. |
| `rapid branch --reject [BRANCH] --reason TEXT [--mention LOGIN] [--dry-run]` | closes the open pull request of the branch as a rejection: one `## REJECTION` comment with the reason, the reviewer and a record line. The branch and its safety anchor are kept. Needs `gh`. |

Kinds: `feature fix refactor docs test chore`. Slugs: a-z, 0-9 and `-`, 2 to 48
characters, unique across landed branches and branches not landed yet. `n<N>` is
the number of the branch, in creation order, never shared; the land keeps it as
the ref `safety/numbers/n<N>` and pushes it with the batch.

```sh
.rapid/rapid branch feature login -r "Users sign in with a passkey; login_test.sh proves the entry point exists." --proof login_test.sh
echo 'echo signed in' > login.sh
printf 'test -f login.sh\n' > login_test.sh
git add login.sh login_test.sh && git commit -m "[NEW] Add the login entry point" -m "Users sign in through login.sh; login_test.sh checks that it exists."
```

The requirement file `requirements/<slug>.md` holds the requirement text and
its `Key: value` lines (`Proof:`, `Untested:`, `Status:`, `Pri:`, `Tests:`,
`Source:`, `Code:` and the others); RULES.md, Requirements register, lists
every key, its default and what the land refuses.

### check

| Form | Effect |
|---|---|
| `rapid check [--gate NAME]` | runs one gate of the conf on the work tree (default `fast`) and prints `gate NAME: <result>`. |
| `rapid check --each` | the commit audit, then the fast gate on every commit of the branch (a commit marked `Red:` is expected to fail it). |
| `rapid check --reqs [--write]` | compares REQUIREMENTS.md with the register `requirements/` generates; `--write` regenerates and stages it. |
| `rapid check --audit [REV]` | the commit audit on the branch, or on the branch of a merge. |
| `rapid check --merge REV` | the forge's proof of a `land --pr` candidate: shape, gates, approvals. |
| `rapid check --judge [--strict]` | an advisory review of the branch commits by the `claude` CLI; it is skipped, with exit 0, when the CLI or a credential (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`) is missing. `--strict` fails on a finding, on a missing verdict and when the CLI exits non-zero. |
| `rapid check --land BRANCH...` | every static land check of each named branch or slug, all at once, every violation in one list; read-only. |

### commit

`rapid commit --smart [--message-only]` composes the message of the staged
change in a fresh model context (the `claude` CLI in print mode, or the conf
key `smart_commit_cmd`), prints it and commits it through the hooks, which
judge it like any message. `--message-only` prints the message and commits
nothing. Without `--smart` the command refuses: commit by hand with `git commit`.

### land

Every land merges the branch into dev once, locally, with its version tag and
its receipt, into the open batch. No gate runs at the merge and nothing is
pushed until the batch closes.

| Form | Effect |
|---|---|
| `rapid land --batch [-F BODY] [--dry-run]` | lands the current branch into the open batch and defers the close: local, no gate, no push. Repeat it for every branch but the last. |
| `rapid land [-F BODY] [--dry-run] [--failed-gates-only]` | lands the current branch, then closes the batch: `gates_each` runs on the own tree of every merge of the batch, all at once; `gates_full` runs once on the final tree; one atomic push carries dev, the version tags, the gate log and the safety and vault branches origin lacks. With no batch open it is a batch of one. |
| `rapid land [FLAGS] BRANCH...` | lands each named branch in order; a conflicting one is skipped and named, the others still land. `-F` goes with one branch only. Without `--batch` the batch closes only when every named branch landed. When one was skipped on a conflict (exit 4) or refused (exit 1), the others stay landed in the open batch: run `rapid land` again to close it. |
| `rapid land --halt` | stops the close under test and keeps the batch. |
| `rapid land --prune` | puts dev back where the batch began, drops the version tags and vault branches of the batch, and drops the batch; the branches are unchanged and can land again. |
| `rapid land --pr [-F BODY]` | opens or updates the pull request of the branch (the body is the merge body); once it has `land_approvals` approvals and its checks, lands it through the forge, gated at the land and pushed at once. Exit 3 while it waits. It joins no batch. |

`-F BODY` is a file holding the merge body: a paragraph, then a list. A final
paragraph of `Key: value` lines joins the trailers of the merge; a trailer rapid
writes itself (`Branch-Base`, `Requirement`, `Gates`, `Tested-Tree`,
`Branch-Number`, `Ticket`, `Proof`, `Docs`, `Untested`) is refused there.
`--dry-run` prints what would land and changes nothing. A branch behind dev is
rebased onto dev by the land itself, behind a preflight ref; a dry run on such
a branch is refused, exit 1 (`rapid land rebases it (a dry run writes nothing)`).

The open batch is the file `<git dir>/rapid/batch`, holding the dev commit where
it began; `rapid status` does not name it. On dev, `rapid land --dry-run`
answers `would close the batch open since dev <sha>` when one is open, and
`rapid status` then shows origin/dev behind local dev.

A passed close deletes each landed branch locally (its tip stays in `vault/`)
and on origin when origin still holds the landed tip; otherwise it stays there
for an admin's `rapid branch --delete-landed`. Until the close the branches are
kept.

`rapid land` never redoes what is done. Run again after a refused push or a
failed close, it finishes only what is owed: from a branch the batch already
holds, or from dev with the batch open, it runs the close alone, and a final
tree that already passed is published without a second test.

`--failed-gates-only` runs again only the gates the previous close of this batch
failed: a merge that close proved on its own tree is not proven again, a merge
landed since is, and the gate of the final tree runs. It is refused, before
anything lands, when no close of this batch failed a gate, and it does not
combine with `--batch` or `--pr`.

```sh
.rapid/rapid land --batch        # every branch but the last: into the batch
.rapid/rapid land                # the last branch: lands, tests the final tree once, pushes once
```

Run one after the other on the same branch, as here, the second finds the
branch already in the batch and runs the close alone.

While a close is under test, a branch that lands into the same batch stops that
close: the batch has a new final tree, which the next close tests.

### sync

| Form | Effect |
|---|---|
| `rapid sync` | rebases the current branch onto dev (dev first fast-forwarded from origin). The previous tip is kept under `refs/rapid/preflight/<slug>/...`. It never pushes. |
| `rapid sync --push` | the same, then sends the branch to origin with a lease on the copy origin held, together with its safety anchor and its number, in one push. |
| `rapid sync --dev` | reconciles local dev with origin after working offline: behind, it fast-forwards; ahead, it publishes the local lands in one push; diverged, it re-lands each local-only merge on top of origin's dev. |
| `rapid sync --dev --continue` | resumes a re-land that stopped on a conflict. |
| `rapid sync --dev --abort` | ends a stopped re-land and keeps the rest as branches not landed yet. |

### release

| Form | Effect |
|---|---|
| `rapid release [VERSION] [--dry-run]` | releases dev's tip: the release gate runs on that tree, `release/<version>` is tagged on it, and main takes it by one `--no-ff` merge `[MERGE] dev into main: <version>`, pushed atomically when there is a remote. VERSION, when given, must be dev's own. With `release_build` the artifacts are built on the tag, audited, gated and listed in it. |
| `rapid release --publish [VERSION]` | ships the gated artifacts of a release again (`release_publish`). The artifacts are kept in `<git dir>/rapid-artifacts/<version>`, so they ship only from the clone that gated them; with `gh` present the release object of the forge is created or updated even without `release_publish`. |
| `rapid release --of REV` | prints the release that first shipped REV, or `unreleased`; read-only. |

Only an admin releases (`release_who`), and never an agent session. The next
land after a release opens the next series.

### changelog, version, queue, bisect, status

| Form | Effect |
|---|---|
| `rapid changelog [--from REV] [TO]` | the changelog from history up to TO (default dev's tip), after REV: each landed merge by release, version, kind/slug and its requirement. |
| `rapid version [--next] [--at REV]` | the last version on dev; `--next` the one the next land takes; `--at` the version of the land that brought REV into dev. |
| `rapid queue [--json]` | open branches in landing order, read-only: commits, how far behind dev, whether each merges into dev cleanly (conflicting files named), branches sharing files. |
| `rapid bisect GOOD BAD -- CMD...` | finds the landed branch, then the commit, that broke CMD. Commits marked `Red:` are skipped; CMD exit 125 skips a commit it cannot test. |
| `rapid status [--json]` | where you are, dev and its last version, origin's dev as last fetched, open branches, branches not landed yet. |

Versions are `vYYYY.S.N`: the landing year, the series (releases so far that
year), the land within the series. No counter is stored: the tags on dev's
first-parent line answer.

### doctor

| Form | Effect |
|---|---|
| `rapid doctor` | checks the install: hooks path, hooks executable, conf keys set once, gates that can run, main and dev present, a re-land left half done, an agent session without the guard. |
| `rapid doctor --fix` | repairs the hooks path, the merge driver and the executable bits. |
| `rapid doctor --history` | the install, then invariants I1 to I9. Merges are checked in full only after the last merge this clone verified; a moved dev, changed tags or a changed verifier walk all of them. |
| `rapid doctor --history --all` | every merge in full. `--all` follows `--history`; before it, exit 2. |
| `rapid doctor --history --since REV` | full merge checks only after REV. |
| `rapid doctor --history-only` | I1 to I9 alone, for a CI runner that has no hooks. |
| `rapid doctor --prove [SINCE]` | runs again, on the own tree of each merge, what its receipt names. |
| `rapid doctor --deep [DOCTOR FLAGS]` | the doctor, then this install's own scenarios (`.rapid/tests/run.sh`): minutes. Framework repository only: a vendored install dropped `.rapid/tests`, and there `--deep` says so and exits 1. |

## 3. Configuration

`.rapid/conf` holds one `key=value` per line; a key set twice is refused. A land
always applies the conf committed on dev, never the branch's own copy, so a
change reaches every branch only after it lands through a branch of its own.

| Key | Default | Effect |
|---|---|---|
| `land_who` | `anyone` | who may land: `anyone`, or `list` |
| `land_list` | empty | the lander emails when `land_who=list` |
| `max_commits` | 20 | most commits one branch may carry |
| `max_commit_lines` | 800 | most lines one branch commit may change, added plus deleted |
| `commit_body` | `required` | a NEW, FIX, REFACTOR, REVERT or HOTFIX commit carries a body line of five words or more |
| `requirement_proof` | `required` | a requirement states eight words or more and a `Proof:` line naming a path or scenario of the branch tip, or a line `Untested: <reason, five words or more>` |
| `docs_rules` | unset | pairs `<code glob>=<doc glob>`: a branch changing matching code changes a matching doc, or its requirement says `Docs: none (<reason>)` |
| `test_paths` | built-in list | shell patterns of test paths; a NEW, FIX or HOTFIX commit that changes behaviour touches one. Exempt: the commit right after a `Red:` commit, and a FIX or HOTFIX that names an existing test with a `Proof:` trailer |
| `signed` | `optional` | `required`: every branch commit, merge, version tag and release tag is signed and verifies; the release tag's signer is checked against `.rapid/signers` at main (git's allowed signers format) when that file exists |
| `land_pr` | `optional` | `required`: a land goes through review (`rapid land --pr`) |
| `land_approvals` | 1 | approving reviews `land --pr` waits for |
| `agent_env` | unset | more environment variables that mark an agent session, besides `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` and `CODEX_*` |
| `smart_commit_cmd` | the claude CLI | the command `rapid commit --smart` feeds the prompt and reads the message from |
| `forge_repo` | from origin | OWNER/REPO when origin's URL does not name it |
| `tracker` | `none` | the committed conf may only say `none`; a tracker comes from operator settings (section 9) |
| `reqs_id` | `REQ` | the token of REQUIREMENTS.md ids, `<TOKEN>-R-<slug>` |
| `release_who` | `owner` | who may promote dev to main: the admins of `.rapid/admins`, or `list` |
| `release_list` | empty | the releaser emails when `release_who=list` |
| `gates_commit` | none | run by pre-commit on the staged tree of every branch commit |
| `gates_fast` | none | run on every branch commit by `check --each`; by `land --pr` on every branch commit and on the merge tree; by pre-push on a dev merge this clone neither gated nor closed |
| `gates_full` | must be set | run by the close on the final tree of the batch, and on a `land --pr` merge tree |
| `gates_each` | none | run by the close on the own tree of every merge of the batch, all at once, before `gates_full` |
| `gates_release` | none | run on dev before a release |
| `test_on_fail` | none | started in the background the moment a scenario fails during a gate run (arguments: scenario name, its output file) |
| `land_on_conflict` | none | started in the background when a land meets a rebase conflict (arguments: the branch, the file listing the conflicting paths) |
| `release_build` | none | builds the release artifacts on the released tree into `$RAPID_ARTIFACTS`, each named with `$RAPID_LABEL`; it runs with `BUILD_TYPE=release` |
| `gates_artifact` | none | run on those artifacts after rapid's own audit for debug output |
| `release_publish` | none | ships the gated artifacts after the release push |

A gate is one shell command run from the root of the tree it tests; exit 0
passes. An empty gate, or the value `none`, passes and is reported as `none`.

### Policy files, admins and [MODE] commits

`.rapid/conf` and `.rapid/admins` are the policy files. `.rapid/admins` lists the
admins, one email per line (`#` comments allowed). A commit that changes a
policy file is a policy flip:

- its subject is tagged `[MODE]`, and it changes only policy files (the
  requirement file of the branch and the regenerated register may ride along);
- its author and its committer are admins as listed on dev, so a branch never
  makes itself an admin;
- under `signed=required` it is signed by an admin (keys from `.rapid/signers` on
  dev); without it the rule rests on the email the committer's git reports;
- with no admin listed, the one flip allowed is the `[MODE]` commit that creates
  `.rapid/admins`.

commit-msg, the land, pre-push and I4 all judge it.

```sh
.rapid/rapid branch chore raise-cap -r "The branch size cap rises to forty commits for the migration work."
echo 'Untested: a policy value carries no test of its own.' >> requirements/raise-cap.md
echo 'max_commits=40' >> .rapid/conf
git add .rapid/conf requirements/raise-cap.md && git commit -m "[MODE] Raise the branch size cap to forty"
.rapid/rapid land
```

The `echo` adds a key the conf does not set yet; a key it already sets is
edited in place, since a key set twice is refused.

## 4. Environment

| Variable | Use |
|---|---|
| `TMPDIR` | where rapid makes its private work trees and temporary files |
| `RAPID_TEST_JOBS` | the number of scenarios `tests/run.sh` runs at once (default: all of them) |
| `RAPID_TEST_ONLY` | space separated scenario names: `tests/run.sh` runs only those |
| `RAPID_TEST_ON_FAIL` | a command started on each failing scenario; overrides conf `test_on_fail` |
| `RAPID_TEST_FAIL_DIR` | where the output of a failing scenario is copied for that command (default `TMPDIR`) |
| `RAPID_LAND_ON_CONFLICT` | overrides conf `land_on_conflict` |
| `RAPID_HISTORY_JOBS` | workers of the history check (default: one per core) |
| `RAPID_BUSY_EVERY` | seconds between two touches of a private work tree in use (default 240) |
| `RAPID_TRACKER` | the tracker, operator side: `none` or `command:<path>`; else `git config rapid.tracker` |
| `RAPID_GITHUB_REPO` | the issues repository of the github tracker adapter when it is not origin |
| `RAPID_JIRA_URL`, `RAPID_JIRA_TOKEN`, `RAPID_JIRA_USER` | the credentials of the jira adapter |
| `RAPID_JIRA_STATUS_DONE`, `RAPID_JIRA_STATUS_IN_PROGRESS`, `RAPID_JIRA_STATUS_IN_REVIEW` | the status names of the jira adapter |
| `RAPID_MCP_SERVER`, `RAPID_MCP_LOGIN` | the server of the mcp adapter, and `stored` to use the login claude keeps |
| `RAPID_MCP_CMD` | the Claude Code executable of the mcp adapter (default `claude`) |
| `GH_TOKEN`, `GITHUB_TOKEN` | the credential of the github adapter; else the login `gh` keeps |
| `CLAUDE_CONFIG_DIR` | the Claude Code directory the agent guard is installed in (default `~/.claude`) |
| `RAPID_BAKS_DIR` | where the preflight writes its zips (default `$HOME/.rapid/baks`; `RAPID_GIT_BAKS_DIR` is read as a fallback) |
| `RAPID_BAKS_MIRROR` | a second directory that takes a copy of every preflight zip (off by default) |
| `RAPID_TRASH_DIR` | where the preflight moves the zips past its retention |
| `PREFLIGHT_MAX_AGE_H`, `PREFLIGHT_KEEP` | hours a preflight is reused (default 12), zips kept per repository (default 5) |
| `RAPID_CANARY_URL` | the repository URL of the live canary, for its own test |
| `RAPID_GIT_SRC` | a neo-git checkout the bench compares with, like `--neo-git` |
| `RAPID_YEAR` | the landing year, for tests |
| `RAPID_ARTIFACTS`, `RAPID_LABEL`, `RAPID_VERSION`, `RAPID_SHA` | set by rapid for `release_build`, `gates_artifact` and `release_publish` |
| `BUILD_TYPE` | set to `release` by rapid for `release_build` |

Set by rapid for its own processes, not for users: `RAPID_CONF_REV`,
`RAPID_OFFLINE`, `RAPID_JUDGED`, `RAPID_RELAND_STEP`, `RAPID_BATCH_CLOSE_PUSH`,
`RAPID_GATE_REC`, `RAPID_DRY`, `RAPID_RC`, `RAPID_TEST_FIXTURE`,
`RAPID_HISTORY_SINCE`, and `RAPID_SRC` in the bench and the canary.

## 5. Hooks

`rapid setup` points `core.hooksPath` at `.rapid/hooks`. commit-msg, pre-push and
the land run the framework committed on dev, never the copy a branch carries,
so a branch cannot loosen the checks that judge it.

| Hook | What it enforces |
|---|---|
| `pre-commit` | no banned file is added (secrets and keys, `.env`, build output, `node_modules`, archives, backups); on a branch, the first commit does not carry the placeholder requirement, REQUIREMENTS.md is regenerated from the staged requirement files and staged, and `gates_commit`, when set, passes on the staged tree |
| `prepare-commit-msg` | the commit that would take a branch past `max_commits` is refused before it is written; an amend passes |
| `commit-msg` | the message rules (below); no commit on dev or main; a policy flip is an admin's `[MODE]` commit |
| `pre-push` | what reaches a remote, below |

The message rules: the subject is `[TAG] Capitalised summary`, 12 to 72
characters, no final period, with TAG one of `NEW FIX REFACTOR DOCS TEST REVERT
HOTFIX MODE`; the summary may start with a digit; the second line is blank; no
em or en dash; a subject joined by `and`, `with`, `plus`, `or`, `then`,
`beside`, `+` or `,` is refused as two concerns; no `Co-Authored-By:` trailer; a
change commit carries a body line of five words or more (`commit_body`); a FIX
or HOTFIX body says `Cause:` then `Fix:`; a test-first commit that fails its
test on purpose carries one trailer `Red: <test name>`, on a `[TEST]` commit
only.
The commit audit also reads the diff: one concern per commit, a behaviour
change with its test, `max_commit_lines`.

pre-push keeps honest pushes inside the rules the forge rulesets enforce:

- only dev, main, `pool/...`, `safety/...` and `vault/...` branches go to a remote;
- dev and main are never deleted or rewritten; every new first-parent commit of
  dev is a landed merge that passes I1 to I4 and I8, pushed with its version
  tag; a dev merge this clone neither gated nor closed has `gates_fast` run on
  it again;
- main moves only by release merges made by `rapid release`, each with an
  annotated `release/<version>` tag whose tagger is an admin;
- version and release tags are created once, never moved or deleted;
- branch commits carry ruled messages, add no banned file, and flip policy only
  in an admin's `[MODE]` commit; a branch holds at most `max_commits` commits;
- a branch is deleted on a remote only once dev holds it;
- safety anchors and vault branches are never moved or deleted;
- while a batch is open nothing is pushed but the push of its close.

A branch push runs no gate: it is transport, and the close tests the tree it
pushes. A plain `git push origin <branch>` just works: when origin lacks the
safety anchor or the number of the branch, the hook sends them in one push
right after the push that carries the branch. What that push answered is kept
in `.git/rapid/log`; an anchor origin still lacks goes with the next push of the
branch, and `rapid sync --push` and the close carry it themselves.

## 6. Invariants and the doctor

`rapid doctor --history` checks nine invariants on history; pre-push checks the
per-merge ones on every merge it sends. Each violation prints `<Id> <sha> <why>`.

| Id | Holds when |
|---|---|
| I1 | every first-parent commit of dev after the root is a two-parent merge whose branch range is linear |
| I2 | every such merge carries exactly one version tag, the next version after the previous one |
| I3 | the merge subject is `[MERGE] pool/v<series>/<number>.<kind>.<slug> into dev: <version>` and its trailers `Branch-Base`, `Branch-Number`, `Gates`, `Requirement` and the tree trailer are present and true; a merge whose gates were deferred belongs to a batch whose close left its record |
| I4 | the branch holds 1 to `max_commits` commits, each with a ruled subject and no commit-audit smell, at most one `Red:` commit that neither ends the branch nor follows another, and policy flips only as an admin's `[MODE]` commits |
| I5 | main holds nothing dev lacks: its first-parent line is release merges of released dev commits, each release tag annotated and tagged by an admin |
| I6 | every version tag and release tag sits on dev's first-parent line |
| I7 | branch slugs are unique across landed merges and branches not landed yet, and so are branch numbers |
| I8 | `requirements/<slug>.md` exists at every merge of that branch and at dev's tip, and REQUIREMENTS.md at each merge is the register its requirement files generate |
| I9 | every merge a re-land replaced is re-landed on dev or kept as a branch not landed yet, and no re-land is left half done |

A merge landed into a batch says `Gates: deferred to the close of batch <id>` and
names its tree as `Merge-Tree`. The close writes what its gates did into the
gate log of the merges (`git notes --ref=gates show <merge>`): one record per
merge for `gates_each`, and the record of the final tree on the last merge.

A clean run may print `doctor: exceptions: <kind>: N merge(s): <versions>`
lines. They are a report, not a failure: they count the merges that landed
under an exception the rules allow. The kinds: `untested` (the requirement
says `Untested:`), `docs-none` (it says `Docs: none`), `batch-close` (gated by
the close of its batch, not at the merge) and `no-gate` (no gate ran).

```sh
.rapid/rapid doctor --history          # the everyday check
.rapid/rapid doctor --prove            # run the receipts again on each merge tree
```

## 7. Failure modes and recovery

Each entry: what you see, what rapid did, what to run.

**The close fails its gate.** The land prints `the batch gate full fails on the
final tree; nothing was pushed and the batch stays open` and, above it,
`broke the close: <branch> (<version>, merge <sha>) is the first batch merge
whose tree fails the gate`. dev, the tags and the branches are kept. Land the
fix as one more branch, then close again (here the repair is made in
`totals.sh` and its test `totals_test.sh` before the commit):

```sh
.rapid/rapid branch fix repair-totals -r "Totals round half up again; totals_test.sh covers the boundary." --proof totals_test.sh
git add totals.sh totals_test.sh && git commit -m "[FIX] Round totals half up" -m "Cause: the rounding truncated where half up was expected." -m "Fix: round half up, as the totals did before."
.rapid/rapid land                         # lands the fix and closes: every gate
```

`rapid land --failed-gates-only` in place of that last line runs only what the
failed close did not prove.

**A merge fails `gates_each` on its own tree.** The land names the versions and
says the record is in the gate log of that merge. That tree cannot change, so
drop the batch and land the branches again once repaired: `rapid land --prune`.

**Origin refuses the push of the close.** `origin refused the batch push;
nothing was published, nothing changed locally`. Fix the reason (it is printed
above), then run `rapid land` again, from dev or from the landed branch: the
tree that passed is published without a second test.

**Origin is unreachable at the close.** `origin unreachable, landed locally;
'rapid sync --dev' publishes it when origin is back`. The gates passed and the
batch is closed locally; run `rapid sync --dev` once origin answers.

**The batch changed under its test.** `a branch joined the batch during its
test, or a newer close took the batch; run rapid land again for the new final
tree`, or `dev moved while the batch was tested; run rapid land again`. Nothing
was pushed; run `rapid land` again.

**A branch number was taken meanwhile.** `branch number nN was published by
another clone since this batch took it; nothing was pushed and the batch
stays`. Run `rapid land --prune`, then land the branches again: the land gives
that branch the next free number.

**Origin holds commits of the branch this clone lacks.** `origin's <branch>
holds commits this clone lacks (<sha>)`. Fetch them with
`git pull --rebase origin <branch>` and land again.

**A land is refused for several reasons.** `land refused for N reason(s); fix
them all, then land again:` and the list: every static violation of the branch
at once, before any gate. `rapid check --land BRANCH...` prints the same list
without landing.

**Origin's dev moved during the batch.** Local dev is put back at the start of
the batch and nothing is pushed. Run `rapid sync` in each branch, then land
them again.

**A conflict at the land (exit 4).** The branch is left as it was, the
conflicting files are named, and `land_on_conflict` is started when set.
Resolve it on the branch, then land again:

```sh
.rapid/rapid sync            # stops on the conflict, exit 1: resolve, git add, git rebase --continue
.rapid/rapid land
```

**A close that should not finish.** `rapid land --halt` stops the close under
test and keeps the batch; the next `rapid land` closes it. With no close under
test it says so and changes nothing.

**A batch to drop.** `rapid land --prune` puts dev back where the batch began;
nothing was pushed, and the branches are unchanged and ready to land again.

**Lands made offline, origin's dev moved meanwhile.** `rapid sync --dev`
re-lands each local-only merge, in order, on top of origin's dev, each taking
the next version; one close then tests and publishes them. The dev it replaced
is kept whole in a snapshot branch `safety/dev-<timestamp>`. A conflict stops
the re-land with its plan kept: resolve it and run `rapid sync --dev
--continue`, or `rapid sync --dev --abort` to keep the rest as branches not
landed yet. While a re-land is in progress a hand `rapid land` is refused.

**A commit message is refused.** commit-msg lists every rule the commit breaks
and restates the subject shape. Nothing was committed; fix the message, or the
staged set when the audit names it, and commit again.

**A banned file is staged.** pre-commit names it. Unstage it
(`git restore --staged <path>`); secrets, keys, build output, `.env` and archives
never enter history.

**A policy flip is refused.** The reason names what is missing: the `[MODE]` tag,
other files mixed in, or an author or committer who is not an admin on dev. An
admin makes the `[MODE]` commit.

**A release is refused.** `policy: ...` names why: the releaser is not listed in
`.rapid/admins` at main, no admin is listed, or this is an agent session. A dry
run still runs the release gate and ends by saying the release itself would be
refused, exit 0.

**`a batch is open ...` on a push.** While a batch is open only its close
pushes. Close it with `rapid land`, or drop it with `rapid land --prune`.

**git cannot read HEAD.** rapid stops on git's own error. It is never read as a
detached HEAD; run the command again once git answers.

**After a land HEAD is detached at the merge.** The land could not check dev
out; why is in `.git/rapid/log`. The land itself is complete.

`.git/rapid/log` is rapid's own log in the git directory: the answer of the
push that follows a branch push, and the error of a failed checkout of dev.
Nothing in it is shown at the time; read it when something looks wrong.

## 8. The test suite

The suite lives in `.rapid/tests/` of the framework repository; a vendored copy
does not carry it. Each scenario is a shell script that builds scratch
repositories under its own temporary directory, drives the real CLI and hooks,
and asserts the end state.

```sh
bash .rapid/tests/run.sh               # every scenario at once
bash .rapid/tests/run.sh -j 8          # eight at a time
bash .rapid/tests/run.sh --fast        # the scenarios marked fast
bash .rapid/tests/run.sh batch         # the scenarios whose name contains "batch"
RAPID_TEST_ONLY="batch-join land-local" bash .rapid/tests/run.sh
bash .rapid/tests/smoke.sh             # parse every shell file, print the help, run the lints
```

By default every selected scenario starts at once; `-j N` or `RAPID_TEST_JOBS`
lowers that. The runner prints one `PASS` or `FAIL` line per scenario with its
time, in file order, then `---- N passed, M failed in Ts (J at once)` with the
failed names. A failure is also printed the moment it happens, and when
`RAPID_TEST_ON_FAIL` (or conf `test_on_fail` during a gate) is set, that command
is started on it at once with the scenario name and a copy of its output. Each
scenario gets its own `TMPDIR`, removed with the run, and repositories that
`rapid setup` made are built once per run and copied.

The runner refuses to start when `tests/SCENARIOS.md` is stale.

### Writing a scenario

```sh
#!/usr/bin/env bash
# what this scenario proves, in a sentence or two: this header is the row of
# tests/SCENARIOS.md. A second line reading "# fast" puts it in the fast subset.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature hello >/dev/null; commit hello.txt
rapid land >/dev/null || fail "the land"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "dev was not published"
history_clean
```

| Helper of `tests/lib.sh` | Use |
|---|---|
| `mkrepo DIR [origin]` | a repository `rapid setup` made, with a project test `check.sh` as every gate; with `origin`, a bare remote at `$T/origin.git` |
| `actor NAME EMAIL` | every later git call authors and commits as this actor |
| `commit FILE [CONTENT] [SUBJECT] [TRAILER]` | one ruled commit on the current branch |
| `rapid ...` | the CLI of the scratch repository; `rapid branch` without `-r` states a scenario requirement, and a bare `rapid land` whose close fails is pruned when that land opened the batch |
| `refused CMD...` | the command must fail; its output is in `$T/out`, its error in `$T/err` |
| `fail TEXT` | print the reason and fail the scenario |
| `lname SLUG`, `lref SLUG [NS]` | the branch rapid named for a slug, here |
| `rbranch REMOTE SLUG [NS]` | the same on a remote |
| `settle` | wait until the anchors a branch push queued have reached origin |
| `history_clean` | `rapid doctor --history` passes |
| `mkremote NAME` | a bare repository under `$T` |

To add a scenario: write `tests/scenarios/<slug>.sh` with its header, run
`bash .rapid/tests/gen-scenarios.sh` to regenerate the matrix, run it alone
(`bash .rapid/tests/run.sh <slug>`), and commit both files with the change they
prove. Name it as the `--proof` of the branch.

## 9. The toolset

### Lints

`bash .rapid/lint/run.sh` runs every lint on the tracked files of the tree; any
finding fails. The shipped gates run it before the scenarios.

| Lint | Finds |
|---|---|
| `lint/docs.sh` | docs that drifted from the code: verbs and their flags, the invariant list, conf keys and defaults, kinds and tags, scenario names, the statement that main is production |
| `lint/dup.sh` | a line a conflict resolution doubled: a variable assigned twice, a doubled help line, a doubled doc line |
| `lint/personal.sh` | personal data in tracked files: a home or session path, an email address outside the reserved domains; `.rapid/admins` is the one file where an address belongs |
| `lint/quiet-grep.py` | a pipeline that ends in a quiet grep, which under `pipefail` reports a miss on a hit |

### Bench

The bench is framework-only; a vendored repository never carries it.

| Tool | Measures |
|---|---|
| `bench/speed.sh [--runs N] [--neo-git PATH]` | the framework's own time per flow, on scratch repositories with gates that pass at once |
| `bench/multiplier.sh [--branches N] [--baseline FILE] [--gate CMD] [--runs N]` | how many times faster each flow is than the baseline rows of `bench/lean-baseline.md`, like with like; the baseline side is never run. The rows of the shipped baseline are recorded (read from the development record of lean, never timed by a bench); the tool refuses a baseline with no row |
| `bench/loadbytes.py [--neo-git PATH] [--ref REV]` | the bytes an agent is told to read per task: the skill plus the lenses its task table names |

### Trackers

A ticket travels through one contract. The tracker is an operator setting,
`RAPID_TRACKER` or `git config rapid.tracker`, with the value `none` or
`command:<path>`; the committed conf may only say `none`, so a branch never
picks an executable by committing it. For the same reason the adapter must sit
outside the repository: a command that is a file the repository tracks is
refused, so the shipped adapters are copied out before use. An adapter answers
one JSON object on stdout, exit 0:

| Operation | Answer |
|---|---|
| `get <ID>` | `{"key": "<ID>", "title": "...", ...}` |
| `link <ID> --branch <branch>` | `{"ok": true}` |
| `transition <ID> --to done --ref <version>` | `{"ok": true}` |

`rapid branch --ticket ID` reads the ticket and links the branch; the merge
carries the ticket; the land moves it to done. A failed link or transition is
reported and never undoes a branch or a land. Three adapters ship in
`.rapid/trackers/`: `github` (issues through `gh`, ids `GH-<number>`), `jira`
(REST through curl, credentials from the environment only) and `mcp` (any MCP
tracker server through Claude Code).

```sh
mkdir -p "$HOME/rapid-adapters" && cp .rapid/trackers/github .rapid/trackers/common.sh "$HOME/rapid-adapters/"
git config rapid.tracker "command:$HOME/rapid-adapters/github"
.rapid/rapid branch fix export-crlf --ticket GH-7
```

The github adapter needs `gh` and an origin on GitHub (or `RAPID_GITHUB_REPO`).

### The forge side

`rapid setup --remote` applies the rulesets of `.rapid/remote/` through `gh` and
writes the `rapid-check` workflow (`remote/check.yml`), which runs the checks on
a pushed branch with the framework of dev, never the branch's own.

| Ruleset file | Protects |
|---|---|
| `protected.json`, `review.json` | dev and main: no deletion, no rewrite; with `land_pr=required`, the review rule and the check statuses |
| `main.json` | main: only repository admins (the forge role, not `.rapid/admins`) update it |
| `tags.json`, `release-tags.json` | version tags never move; only repository admins (the forge role, not `.rapid/admins`) create `release/*` tags |
| `safety-lockdown.json`, `vault-readonly.json` | safety anchors and vault branches: created once; moved or deleted only by a repository admin |
| `branch-deletions.json` | branches of the pool: only a repository admin (the forge role, not `.rapid/admins`) deletes one |

The rulesets are the authority on a forge; the hooks keep honest pushes inside
the same rules everywhere else.

### The agent guard

`rapid setup --agent` installs hooks into Claude Code that catch, before any git
hook runs, what an agent can break by accident: destructive git without a
fresh preflight backup, a push to main and a release, a bare force push,
`git add -A`, deleting or renaming dev, main, a branch, a safety anchor or a
vault branch, a remote repository deletion, `rm` outside temporary roots,
printing credential files, and edits to a vendored `.rapid` copy (`.rapid/conf`
and `.rapid/admins` stay editable). It matches known command shapes and allows
unknown ones: a guard against accidents, not a sandbox. `--uninstall` removes
it, `--dry-run` names what it would write, `--prefix DIR` installs under
another Claude directory. `rapid doctor` names `rapid setup --agent` in an
agent session that lacks it.

#### Preflight backup

`<claude>/hooks/rapid/git-preflight.sh <repo> ["reason"]` (the source is
`.rapid/agent/git-preflight.sh`) is the backup the guard asks for before
destructive git. It touches neither the current branch nor the index and
writes two copies of the work tree, untracked files included, secrets, build
output and `node_modules` left out: a local branch `preflight-bak-<date>/NN`,
never pushed (only dev, main, `pool/`, `safety/` and `vault/` branches go to a
remote), and a zip in `RAPID_BAKS_DIR` (default `$HOME/.rapid/baks`). A preflight younger than 12 hours for the same HEAD and
the same work tree is reused; the five newest zips of a repository are kept,
older ones go to the Trash.

### The live canary

`bash .rapid/tests/canary/live.sh [--repo OWNER/NAME] [--dry-run]` is a hand-run
test tool, not part of the gates: it drives the flows against a real forge in
one persistent public repository (created when missing, never deleted) and
prints `PASS` or `FAIL` for checks C0 to C9: the repair of a canary a stopped
run left under required review (C0), setup and the rulesets, the forge
refusing a rewrite of dev and of a version tag, a branch not landed yet, the
forge jobs, a release, a land through a pull request (C7) and a release (C8)
under `land_pr=required`, and the return to optional review. It needs `gh` signed in with the `repo` and `workflow` scopes.
`--cleanup RUN` removes the branches a run pushed and did not land.
