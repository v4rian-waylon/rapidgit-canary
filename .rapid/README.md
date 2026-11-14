# rapid

A fast git flow for humans and AI agents prototyping fast without giving up
quality, control or traceability.

- **Branches in, one merge out.** Work happens on `pool/v<series>/n<N>.<kind>.<slug>`
  (`n<N>`: the branch's number, in creation order, never shared, online or
  offline); `rapid land --batch` merges it into dev once, locally, into the open
  batch, with its version tag and its requirement, and defers the close;
  `rapid land` without `--batch` lands the last branch and closes the batch:
  it tests the final tree once, every scenario at once, and publishes every
  merge in one atomic push. No test per land, no push per land, no push at
  all while a batch is open.
- **One requirements register.** `REQUIREMENTS.md` traces every requirement
  (status, priority, tests, source, code, protected rows, a graveyard) and is
  generated from `requirements/<slug>.md`, so it cannot drift.
- **Fork points stay forever.** `rapid branch` anchors every branch at the commit
  it forked from (the branch `safety/v<series>/<number>.<kind>.<slug>`) and `rapid land` records where
  it ended (`vault/v<series>/<number>.<kind>.<slug>`); every push of the branch carries its
  anchor, and nothing deletes or moves either.
- **Nothing is lost, nothing leaks.** Branches, dev and main are
  never deleted by hand, and no secret, key, build output or archive is ever
  committed (`pre-commit`, land, pre-push, the agent guard).
- **History is the database.** Versions, branch names and requirements are read
  from dev's first-parent line; nothing else stores them. Every point of
  progress can be rebuilt, blamed and bisected per commit and per concern.
- **One flow.** The same commands work alone or in a team, online or offline,
  with or without a forge.
- **main is production.** Publishing is a release reaching main, and only the
  owner promotes dev to main (`rapid release`; the owner is an admin listed
  in `.rapid/admins`). dev is integration; pushing dev, branches or tags to a remote is
  transport, never publishing. An agent never releases: it reports that dev
  is ready.

The words: the **pool** is every branch in flight in the repository, under
`pool/v<series>/`; a **branch** is one feature unit of it,
`pool/v<series>/n<N>.<kind>.<slug>`; a **batch** is the grouping one developer
lands with one test and one push (a batch ⊆ the pool).

## Quick start

```sh
cp -R path/to/rapidgit/.rapid .   # vendor the framework, then drop its own
rm -rf .rapid/tests .rapid/bench .rapid/FRAMEWORK .rapid/admins   # tests, bench, source marker, admins (setup --upgrade does this)
cat > .rapid/conf <<'CONF'            # your gates first: one shell command each, exit 0 passes
gates_fast=sh .rapid/lint/run.sh && sh login_test.sh
gates_full=sh .rapid/lint/run.sh && sh login_test.sh
gates_release=sh .rapid/lint/run.sh && sh login_test.sh
CONF
printf 'test -f login.sh\n' > login_test.sh # your project's own test
.rapid/rapid setup                      # hooks, the first admin, main and dev
.rapid/rapid branch feature login -r "Users sign in with a passkey; login_test.sh proves the entry point exists." --proof login_test.sh
echo 'echo signed in' > login.sh    # commit in atomic steps, a change and its test together
git add login.sh login_test.sh && git commit -q -m "[NEW] Add the login entry point" -m "Users sign in through login.sh; login_test.sh checks that it exists."
.rapid/rapid land                       # versioned, then the batch's one test and one atomic push
.rapid/rapid doctor --history           # invariants I1 to I9 hold
```

Set your gates in `.rapid/conf` first (`gates_fast`, `gates_full`,
`gates_release`: one shell command each, exit 0 passes), as the block does
before `rapid setup`: setup refuses a conf whose gates run framework tests the
vendor dropped, land refuses an unset `gates_full` (`gates_full=none` lands
without one, said out loud), and fresh-vendor runs this block as written. The
personal-data lint in those gates refuses a personal email in any tracked
file but `.rapid/admins`, the one place an address belongs: the admins, who
alone release and flip policy, are listed there, and the same address
anywhere else (a copy of the file included) is refused. An agent that
initializes the repository names its owner with
`rapid setup --owner <email>`.
After setup a conf change is a `[MODE]` commit.

## Commands

| Command | Does |
|---|---|
| `rapid setup` | hooks, the first admin, seed main and dev; `--owner` names the first admin at the first setup, never its runner; `--agent` guard (`--uninstall`, `--prefix`); `--remote` rulesets and CI (`--repo`, `--dry-run`); `--upgrade` the vendored `.rapid` |
| `rapid branch` | start a branch (`-r`, `--proof`, `--ticket`); `--rename`, `--delete-landed`; a reviewer closes the PR of the branch as a rejection, the branch kept (`--reject --reason`, `--mention`, `--dry-run`) |
| `rapid check` | a gate on the work tree (`--gate`); `--each` the commit audit and the fast gate on every branch commit; `--audit` the deterministic commit audit on the branch or a merge's branch; `--reqs` REQUIREMENTS.md against the register `requirements/` generates (`--write` regenerates it); `--merge` the forge's proof of a `land --pr` candidate; `--judge` an advisory review (`--strict` fails on a finding); `--land` every static land check of each named branch, all branches at once |
| `rapid commit` | opt-in `--smart`: a fresh model context composes the message for the staged diff, the hooks judge it (`--message-only` prints it) |
| `rapid land` | merge once into dev, tagged, into the open batch (`-F` body, `--dry-run`), then close the batch: its one test (`gates_each` on every merge's own tree, `gates_full` on dev's final tree) and one atomic push of every merge, tag and ref; with no batch open, a batch of one. `--batch` lands and defers the close: local, offline, no gate, no push. Run again it never redoes what is done: a close still owed (a push origin refused, a failed close once its fix landed) runs, from the landed branch or from dev, and a tree that passed is not tested again. `--failed-gates-only` runs again only the gates the previous close of this batch failed, refused when none failed (the default runs every gate); `--halt` stops the close under test and keeps the batch; `--prune` puts dev back where the batch began and drops the batch, the branches unchanged; `--pr` through review, gated and pushed at once |
| `rapid sync` | rebase the branch onto dev, locally, never pushing (`--push` then lease-pushes the branch); `--dev` reconcile dev with origin after offline work (`--continue`, `--abort` a stopped re-land) |
| `rapid release` | an admin only (main is production): release gate, `release/<v>` listing the branches still open, a `--no-ff` release merge on main, so its first-parent line lists the releases; with `release_build` the artifacts built on the tag, audited, gated and listed with their checksums in it, then shipped (`--dry-run`; `--publish` ships them again); with `signed=required` the tag is signed by an admin's key; the release that first shipped a commit (`--of`) |
| `rapid changelog` | the changelog generated from history, up to a hash (default dev's tip) and after `--from` a hash: landed merges grouped by release, one line each with version, kind/slug and requirement; no CHANGELOG.md is kept |
| `rapid bisect` | find the branch, then the commit, that broke a command |
| `rapid version` | the last version on dev; the version the next land takes (`--next`); the version of the land that brought a commit into dev (`--at`) |
| `rapid queue` | the open branches in landing order, read-only (`--json` for tools): commits, how far behind dev, a clean or conflicting merge into dev with the files named, the branches that change the same files |
| `rapid status`, `rapid doctor` | where you are (`--json`); the install (`--fix`), the history invariants (`--history`, from the last merge this clone verified; `--all`, `--since`, `--history-only`), what the receipt of each merge names, run again on its own tree beside its stored gate log (`--prove`); the doctor and then the scenarios the install carries (`--deep`) |

Thirteen verbs, one CLI. The docs are checked against the code by `.rapid/lint/docs.sh`.

## Read next

- [RULES.md](RULES.md): branches, commits, merges, versions, invariants, policy.
- [FLOWS.md](FLOWS.md): every flow as steps, for humans and agents.
- [DESIGN.md](DESIGN.md): why it is built this way and what it gives up.
- [tests/SCENARIOS.md](tests/SCENARIOS.md): the scenario matrix that proves it.
- `bench/` (framework source only): `speed.sh` and `loadbytes.py` measure
  rapidgit's speed and read budget against neo-git (DESIGN.md, Measured).
- [skill/SKILL.md](skill/SKILL.md): the loader for AI agents, with its lens
  files (`skill/lenses/`) read one per task, and the map of every neo-git
  lens rule to its home (`skill/lenses/RULE-MAP.md`).
