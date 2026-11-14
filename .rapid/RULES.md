# rapid rules

Each rule below is either enforced, with its enforcement point named, or a
convention, marked as one. The enforcement points are the `pre-commit`,
`prepare-commit-msg`, `commit-msg` and `pre-push` hooks, `rapid land` and
`rapid release`; the history checks are
`rapid doctor --history` (invariants I1 to I9 in `.rapid/lib/history.sh`) and
`rapid doctor --prove` (every merge's gates rerun on its own tree, and every
release's gate rerun on the released tree). Client
hooks are a guard rail for honest work: anyone with a clone can skip them
(`--no-verify`, a hand-written proof note, `core.hooksPath` pointed away from
`.rapid/hooks`), and the agent guard denies all three to agents, as it denies a
moved version tag (`git tag -f`, `update-ref` of a `v<year>.<n>.<n>` tag). On a forge the authority is the server: the rulesets from
`rapid setup --remote` (no deletion or rewrite of dev and main, no branch deletion except by
the admins, no
moved or deleted tag, no update of main and no new `release/*` tag except by
the repository's admins) and, with `land_pr=required`, GitHub's own review
rule on dev only, never on main (`land_approvals` approvals given after the
last push) plus the rapid-check and commit-audit statuses, which the workflow computes with dev's checker, never the
candidate's. A candidate's gates are its own tests and it can edit the
workflow file, so review, not the status, is what a hostile change meets.

## Vocabulary

- The **pool** is the active development of the whole repository: every
  branch in flight, of every developer, all under `pool/v<series>/`.
- A **branch** is one feature unit in the pool,
  `pool/v<series>/n<N>.<kind>.<slug>`, landed as its own merge. `rapid branch`
  opens one; `safety/` keeps its start and `vault/` its landed end.
- A **batch** is the grouping one developer makes of their own branches,
  landed together with one test of the final tree and one push, to cut test
  and network overhead. A batch ⊆ the pool: it is always one developer's, and
  it equals the pool when one developer holds every branch in flight and
  batches them all.
- **dev** is integration and **main** is production.

## Branches

| Branch | Moves by | Never |
|---|---|---|
| `dev` | `rapid land` only: one merge per branch | a direct commit, a rewrite, a deletion |
| `main` | `rapid release` by the owner only: fast-forward to a released dev commit | a commit dev lacks, a rewrite, a deletion, a release by anyone but the owner |
| `pool/v<series>/<number>.<kind>.<slug>` | your commits; `rapid sync` rebases it onto dev | landing without `rapid land` |
| `main` | `rapid release` by the owner only: a `--no-ff` release merge `[MERGE] dev into main: <v>` of a released dev commit, so `git log --first-parent main` lists the releases | a tree dev lacks, a fast-forward to dev, a rewrite, a deletion, a release by anyone but the owner |
| `main` | `rapid release` by the owner only: a `--no-ff` release merge `[MERGE] dev into main: <v>` of a released dev commit, so `git log --first-parent main` lists the releases; written here and pushed, or, when the forge's main ruleset requires a pull request, merged through the dev to main PR by the forge's API and checked before the tag | a tree dev lacks, a fast-forward to dev, a rewrite, a deletion, a release by anyone but the owner |
| `pool/v<series>/<kind>.<slug>` | your commits; `rapid sync` rebases it onto dev | landing without `rapid land` |
| `safety/v<series>/<number>.<kind>.<slug>` | written once by `rapid branch`: an anchor commit on the fork point | deletion, a move, a hand-written anchor: pre-push, the agent guard and the `rapid-safety-lockdown` ruleset refuse them |
| `vault/v<series>/<number>.<kind>.<slug>` | written once by `rapid land` at the landed branch tip | deletion, a move, a hand-written vault branch: pre-push, the agent guard and the `rapid-vault-readonly` ruleset refuse them |

Kinds: `feature fix refactor docs test chore`. Slugs: `a-z`, `0-9`, `-`, 2 to
48 chars, unique for the life of the repository (I7). The anchor keeps the
branch's full name, number included.

These are neo-git's words: a working branch is a branch, a landed tip sits in
the vault and a fork point under safety. A branch never landed simply stays a
branch, its anchor kept forever; `rapid status` and `rapid doctor` list the
branches not landed yet. No other branch prefix is a branch.

## Branch numbers

Every branch gets a number in its name, `pool/v<series>/<number>.<kind>.<slug>`
(`v<series>` is the version series the branch opened in, for example
`pool/v2026.0/n12.fix.stale-tag`), from
`rapid branch`, with no extra step. Numbers follow creation order and one
number never names two branches (I7), online or offline:

- The number is `n<N>`: N is one more than the highest number the clone
  knows of, its own and, when origin answers, those origin holds (a fetch;
  never below the count of merges on dev). Opening a branch never pushes: `rapid
  branch` takes the number in this clone, create-only, in the refs its work
  trees share, and the reservation `safety/numbers/n<N>` reaches origin with
  the anchor of the branch in the one push of the batch (`rapid land`), or with
  a push of the branch itself. Two clones that cannot see each other may count
  the same N: when another clone published the number first, `rapid land`
  gives the branch, still unpublished, the next free number, and the close
  refuses a collision that appears after the land, before anything is pushed.
- `safety/numbers/<number>` names the branch's anchor, so it stays
  forever like one; with the anchor commit's date it orders every branch ever
  started, landed or not. `git for-each-ref
  --format='%(refname:lstrip=4) %(committerdate:iso) %(contents:subject)'
  refs/heads/safety/numbers` lists them.
- A landed merge carries its number as `Branch-Number:` (land, I3). A branch
  made by hand or before numbers takes the next number when it lands; a
  hand-made name with a number the clone did not reserve for it is refused
  at land.

## Developers never delete branches

dev, main, branches, safety anchors and vault branches are never
deleted or renamed by hand, by a human or an agent: a branch leaves only as
rapid moves it, and on a forge only a repository admin removes a branch.

- `rapid land` lands a branch into the open batch, local and ungated (its
  commits live on as the merge's second parent, its fork point in its anchor,
  its tip in its vault branch); with `--batch` the close is deferred, and
  without it the land closes the batch: it gates the batch's final tree
  once (`gates_full`) and pushes it all in one atomic push. A `--pr` land,
  apart from its atomic push, tries to delete the branch on origin.
  The `rapid-branch-deletions` ruleset lets only admins do that: for anyone
  else the branch stays on origin, landed. A branch never landed stays a branch:
  `rapid status` and `rapid doctor` list it as not landed yet.
- `rapid status` and `rapid doctor` list landed branches still on origin, and an
  admin's `rapid branch --delete-landed [BRANCH...]` deletes them; it never deletes a
  branch dev does not hold.
- pre-push refuses deleting a branch on the remote unless dev holds it: the
  same push lands it on dev, or this clone's dev or the remote's already
  holds it. It refuses deleting dev, main, an anchor or a vault branch
  outright.
- The agent guard denies `git branch -d/-D/-m/-M`, `update-ref -d` and a
  deleting push of dev, main, a branch, a safety or vault branch,
  preflight or not.
- On a forge the rulesets are the authority, as in neo-git: `rapid-protected`
  and `rapid-main` keep dev and main, `rapid-branch-deletions` the branches,
  `rapid-safety-lockdown` the safety branches (no update or deletion),
  `rapid-vault-readonly` the vault branches (no update or deletion) and
  `rapid-branch-deletions` the branches (no deletion); only repository admins
  bypass the last three. Creating a safety branch stays open: every lander
  writes its own branch's anchor and its number with the branch's first push, and from then
  on nobody but an admin can move or delete it. neo-git also locked
  creation, because its CI bot made every anchor; that bot is gone, and
  pre-push refuses an anchor whose commit names another branch (a rename keeps
  its kind and number) or a number key naming a branch with another number.
- Convention for humans in their own clone: git has no hook on a local
  branch deletion, so a local `git branch -D` of a branch is not caught; its
  anchor stays, and once pushed origin keeps the branch.

## Safety anchors

Safety anchors stay forever. `rapid branch` writes the branch
`safety/v<series>/<number>.<kind>.<slug>`, as neo-git did, on an anchor commit whose only
parent is the commit the branch forked from and whose message, author and
date record the branch and who started it when (a commit per branch, so two
branches forked from one dev tip never share an anchor). Nothing ever deletes
or moves it: the branch may be synced, renamed, left not landed or landed
and deleted, and its fork point (`safety/v<series>/<number>.<kind>.<slug>^1`) is still there.

- Every push that carries a branch carries its anchor: pre-push pushes it
  first when the remote lacks it (and a clone sharing a coworker's branch
  takes origin's anchor, never a second one), `rapid land` puts it
  in its atomic push, and `rapid sync --dev` publishes the anchors of branches
  landed offline. A branch made by hand or before anchors existed gets one
  where it leaves dev, at its first push or land.
- `rapid branch --rename` writes the new name's anchor on the same anchor
  commit; the old name's anchor stays.
- pre-push refuses deleting an anchor, moving one, and creating one that is
  not an anchor commit (one parent, the fork point); the agent guard denies
  `update-ref` and `git branch` writes on safety branches, a push that
  deletes, forces or sends anything but the anchor itself there, and a
  pruning or forced fetch into it, preflight or not; on a forge
  `rapid-safety-lockdown` does the same for everyone but admins.

## Vault branches

Every landed branch also keeps a pointer to its end. `rapid land` writes the
branch `vault/v<series>/<number>.<kind>.<slug>` on the branch's tip as it landed (the merge's
second parent), in the same atomic push as dev and the tag, as neo-git
vaulted a merged branch; an offline land's vault branch is published by `rapid
sync --dev`. With the anchor at its start, every branch is bounded by two
branches that stay forever, after the branch itself is deleted. They
are pointers, not copies: the commits are dev's anyway. A re-land keeps the
vault branch of the branch's first land. pre-push, the agent guard and, on a
forge, `rapid-vault-readonly` keep vault branches as they keep anchors: never
deleted, moved or hand-written.

## Production

main is production. Publishing is a release reaching main, and only the owner
promotes dev to main. dev is integration; pushing dev, branches or tags to a
remote is transport, never publishing.

- The owner is an admin: an email listed in `.rapid/admins` (one per line, `#`
  comments allowed); `rapid setup` writes the setup author as the first admin
  in the root commit, unless that author is an agent, and
  `rapid setup --owner <email>` writes the named person instead, never the
  runner (setup-owner). While no admin is listed, `rapid release`
  refuses everyone. With `release_who=list` the owner is instead every email
  in `release_list`. An agent session never releases.
- Who may release is read as committed at main's tip, never at dev's: a branch
  landed on dev cannot grant itself the right, and a new admin takes effect
  only through a release a current admin makes. While main lists no admin
  (a repository first released under this rule), dev's admins rule.
- Enforced by `rapid release` (before its gate; the release tag records
  `Released-By:`), pre-push (main moves only by release merges of a dev
  commit carrying an annotated `release/<v>` whose tagger the policy at the
  old main allows, and a `release/<v>` tag
  pushed on its own, which would open the next series, meets the same
  tagger check), I5 (each release tag's tagger against the policy at the
  release before it), the agent guard (an agent's `rapid release` is denied
  however the program is named, copied or linked, `--dry-run` is allowed,
  and so is any `release/<v>` tag it would create, write or push) and, on a forge, the `rapid-main` ruleset (only the
  repository's admins update main) and the `rapid-release-tags` ruleset (only
  they create a `release/*` tag). dev's review rule (`land_pr=required`)
  lives in the dev-only `rapid-review` ruleset, so it never blocks the owner's
  release push to main.
- With `signed=required` (at the old main or at the released commit)
  promotion is verifiable: `rapid release` signs the release tag (`git tag
  -s`), and `rapid release`, pre-push (main arm and a pushed `release/<v>`
  tag) and I5 refuse a release tag without a good signature or whose signer
  (the verified ssh principal or gpg email) the policy at the old main does
  not allow. The keys are `.rapid/signers` committed at the old main (git's
  allowed signers format, `<email> <keytype> <key>`; main moves only by a
  release, so only the owner changes them), else git's own verification
  config. Residual: without `signed=required` or a forge ruleset on main,
  owner-only release rests on the address the releaser's git reports,
  which is an address by convention.

## Commits

- Subject: `[NEW|FIX|REFACTOR|DOCS|TEST|REVERT|HOTFIX|MODE] Capitalised summary`,
  12 to 72 chars, no final period; second line blank; no em or en dash.
- One concern per commit, and a change and the test that proves it share a
  commit. The deterministic part is enforced as the commit audit (rule
  `commit-audit`, `lib/audit.sh`): a subject whose text needs `and`,
  `with`, `plus`, `or`, `then`, `beside`, `+` or `,` joins two concerns; a `[FIX]` or `[HOTFIX]`
  body carries a `Cause:` paragraph, then a `Fix:` paragraph; a commit
  changes at most `max_commit_lines` lines (default 800, added plus
  deleted); a `[NEW]`, `[FIX]` or `[HOTFIX]` commit that changes behaviour
  (a path that is not prose, a test, a requirement file or the policy files)
  touches a `test_paths` path, unless the commit before it carries `Red:`.
  Checked at commit (`commit-msg`), by `rapid check --each` and `--audit`, at
  land, at a branch push (`pre-push`, which runs no gate), by I4, and on a forge by the required
  `commit-audit` status. The rest (one concept, a body true to the diff) is
  convention: `rapid check --judge` gives an advisory review of it; review on
  a forge is the authority.
- A test-first commit that fails its test on purpose carries one trailer
  `Red: <test name>` and is followed in the same branch by the commit that
  turns it green; it can never be a branch tip. `rapid check --each` runs the
  fast gate on every branch commit and fails on an unmarked red one.
- `Red:` cannot hide broken work: it marks a `[TEST]` commit only
  (`commit-msg`, land, pre-push, I4); the commit after a `Red:` commit must
  pass the fast gate and carry no `Red:` (no chain of reds; `rapid check
  --each`, land, and I4 for the chain); a `Red:` commit whose fast gate
  passes is a stale marker and is refused (`rapid check --each`). Land runs
  no gate: it refuses a `Red:` branch tip and a chain of reds from the
  trailers alone, and the close tests the final tree.
- `Fixes: <sha>` names the commit (usually a landed merge) a fix or revert
  repairs; `rapid land` refuses one that names no commit on dev.
- A change commit says what it does: with `commit_body` at its default
  `required`, a `[NEW]`, `[FIX]`, `[REFACTOR]`, `[REVERT]` or `[HOTFIX]`
  commit carries a body line of five words or more that is not the subject
  again; the text after `Cause:` or `Fix:` counts, so a `[FIX]` body of a
  `Cause:` line then a `Fix:` line passes (`commit-msg`, land, pre-push, I4;
  lazy-docs).
- Who may commit and push is the repository's own access: rapid keeps no
  list of authors and checks no author or committer against one. No
  `Co-Authored-By:` trailer of any kind (rule `no-coauthor`):
  the commit's author is its author.
- A branch holds 1 to `max_commits` commits (default 20) and no merge commit.
- Banned files never enter history, for humans as for agents: secrets and
  keys (`.env` and `.env.*` but templates such as `.env.example`, `.auth/`,
  `keys/`, `*.p8`, `*.p12`, `*.pem`, `*.cer`, `*.provisionprofile`,
  `*.mobileprovision`), build output (`build/`, `build-*/`), `node_modules/`,
  `*.zip`, `*.bak` and `.DS_Store`. `pre-commit` refuses them in the staged
  set on every branch; a branch push and `rapid land` refuse a branch commit
  that adds one past the hook; the agent guard denies staging one. Deleting
  one is always allowed; a branch that ever added one is rebuilt without it.
- A branch is judged by dev's framework, never by its own copy: `rapid land`,
  `commit-msg` and `pre-push` run dev's committed `.rapid` (exported once per
  dev framework tree into `<git common dir>/rapid/judge/<tree>/`, `lib/judge.sh`)
  whenever the work tree's `.rapid` differs from dev's, so a branch that rewrites
  a check never runs its rewrite on itself. In rapid's own repository this is
  the protection.
- Caught at the earliest point: the commit that would make a branch
  `max_commits + 1` is refused before it is written (`prepare-commit-msg`;
  an amend passes); a branch's first commit never carries the placeholder
  requirement, and with `gates_commit` set the staged tree must pass it
  (`pre-commit`); a branch push is refused above `max_commits` or when a
  commit fails the fast gate without a valid `Red:` (`pre-push`, the same
  check as `rapid check --each`).

## Merges (written by `rapid land`, never by hand)

```
[MERGE] pool/v<series>/<number>.<kind>.<slug> into dev: vYYYY.S.N

<body: a paragraph saying what the branch does, then a '- ' list>

Branch-Base: <dev tip the branch contained>
Requirement: requirements/<slug>.md
Gates: deferred to the close of batch <id>     (a land into the batch: no gate ran on this tree)
Merge-Tree: <the tree of the merge>     (with a deferred receipt; never Tested-Tree)
Gates: fast=<pass|none> full=<pass|none> (a land --pr: both gates ran on the merge tree)
Tested-Tree: <the tree the gates passed on, equal to the tree of the merge>
Branch-Number: <the number of the branch, n<N>>
Ticket: <CODE-123>              (when the branch has one)
Proof: <test file or scenario slug>     (the requirement's proof, requirement_proof=required)
Docs: <docs> | none (<reason>)  (a branch that changes code a docs_rules pair names)
```

A receipt says only what ran. A land into the batch runs no gate, so its merge
says `Gates: deferred to the close of batch <id>` (the id is the commit dev stood at
when the batch opened) and names its tree as `Merge-Tree`. The close then
runs `gates_each` on the own tree of every merge of the batch, all merges at
once, and writes each result into the gate log of that merge; it runs the one
gate on the final tree and writes that record into the gate log of the last
merge. `rapid doctor --history` accepts a deferred receipt only when the last
merge of its batch carries that record with exit 0, or its plain statement
that no gate is configured (I3); the batch still open in the clone is exempt.
Land reports every static refusal of a branch in one list before any gate
(`rapid check --land BRANCH...` prints the same list for many branches at once).
The branch must contain dev's tip (land rebases a stale branch onto it first, exit 4 on a conflict), so the merge tree is
exactly the branch tree. The body is a paragraph, then a `- ` list (land,
pre-push and I3); land also refuses a body too thin to say anything (a
paragraph under three words, no list item of two words) and a requirement
under three words. Shape and a floor are machine-checked; whether the words
are true is review's job. A `-F` body whose last paragraph is only
`Key: value` lines (`Replays:`, `Fixes:`) has them moved into the trailer
block, so `git log --format='%(trailers:key=...)'` finds them. `requirements/<slug>.md` is committed on the branch, states a
real requirement (land refuses the placeholder; with `requirement_proof`
at its default `required`, eight words or more and a `Proof: <test file or
scenario slug>` line naming what the branch tip holds, or `Untested: <reason>`; land
copies it as a `Proof:` trailer) and is never edited or
deleted by a later branch (land and I8).

Every land keeps its gate log as a note on the merge under `refs/notes/gates`:
a land into the batch notes that its gates are deferred, and the close
adds each gate it ran on the final tree (command, exit code, duration and log
tail) to the note of the batch's last merge (a `--pr` land notes its own
merge-tree gates), pushed atomically with dev and the tags; the ref only grows (pre-push refuses
its deletion or rewrite, the agent guard any hand write), and `rapid doctor
--prove` shows it beside the rerun.

A `Gates:` receipt is re-proven, never only trusted: pre-push reruns the fast
gate on any merge this clone neither gated nor closed (a `--pr` land and the
close of a batch leave a local `rapid-proof` note naming the tree and the
private id of this clone, so a note fetched from elsewhere never counts),
`rapid doctor --prove` reruns on the own tree of each merge what its receipt
names (both gates for a `--pr` land; `gates_each` for a batch merge, with the
full gate on the last merge of the batch), and the rapid-check workflow does so for each new dev
merge. A dev push must carry each new merge's version tag. A human can still
hand-write the note in their own clone, as they can skip any hook; the forge
proof is what catches it.

Lands take no lock and keep no queue: two lands racing for one version take
it once (land creates the version tag before dev moves, and dev moves by
compare-and-swap), so the second stops with dev unchanged; it syncs and lands
again. The agent guard denies hand writes under `<git common dir>/rapid/`
(the open batch) and to `refs/notes/rapid-proof`.

## Requirements register

`REQUIREMENTS.md` at the root is the project-reqs register (Hard
Requirements, Units of Intent, Scrapped), generated from
`requirements/<slug>.md` by `lib/reqs.sh`; nobody edits it by hand.

- A requirement file is `# <kind>/<slug>`, a blank line, the requirement as
  one paragraph, then optional `Key: value` lines: `Status:`
  (`done`, the default, `in-progress`, `blocked` or `intent`), `Pri:` (`P0`
  to `P3`; default `P0` for a fix, `P1` for a feature, else `P2`), `Tests:`
  (paths; default the scenarios `scenario slug` the text names, else the row says
  `needs units`), `Source:` (default `jira-<Ticket>` with a ticket, else
  `internal`), `Code:` (paths), and for intents `Sprint:` and `Notes:`.
- A landed file never changes (I8), so a later branch changes a row from its
  own file: `Promotes: <slug>` ends an intent, `Completes: <slug>` marks
  an in-progress or blocked row done, `Scraps: <slug>: <why>` moves a row to
  Scrapped, the graveyard that keeps it.
- IDs are `<reqs_id>-R-<slug>` and `<reqs_id>-I-<slug>`: a slug is unique
  for the life of the repository (I7) and taken without a counter, so two
  offline clones never mint the same ID.
- Every Hard Requirement is protected: a test it names must exist in the
  tree, or the register cannot be generated and the commit and the land are
  refused, until a branch scraps the row with its reason.
- Enforced by `pre-commit` (regenerates and stages it with every branch
  commit), `rapid sync`, the re-land and `rapid branch --rename` (regenerate it in
  every rewritten commit; a row merge driver, `lib/reqs-merge.sh`, declared
  by `rapid setup` and `rapid branch`, lets even a plain `git rebase` combine two
  branches' rows),
  `rapid land` (refuses a register its tree does not generate) and I8 (rule
  `reqs-register`). `rapid check --reqs` compares, `--write` regenerates.

## Versions and tags

- `vYYYY.S.N`: year, series (releases so far that year), land number in the
  series starting at 1. After `release/<v>` the next land opens series S+1;
  a new year starts at `vYYYY.0.1`. Computed from dev's first-parent line;
  no counter is stored.
- Each landed merge carries exactly one annotated `v*` tag naming it (I2,
  I3). `release/<v>` sits on a released dev commit that main's release merge
  `[MERGE] dev into main: <v>` takes as second parent, with its tree (I5).
- Version and release tags are created once and never moved or deleted;
  every one sits on dev's first-parent line (I6). A re-land by
  `rapid sync --dev` keeps the dev it replaced whole in one snapshot branch
  `safety/dev-<timestamp>`, pushed with the re-land's close, never moved or deleted.
- `release/<v>` records the release gate result, the tested tree and the
  branches still open at release, oldest first, with their first and last
  commit dates.

## Release identity

What ships is the gated artifact of the release tag, never a rebuild. With
`release_build` set, `rapid release` builds the artifacts on the released
tree (a clean private worktree of the tagged commit, `BUILD_TYPE=release`)
into `$RAPID_ARTIFACTS`, then refuses the release, main and tags unchanged,
when the build fails, writes no artifact, changes a tracked file, writes a
non-file, names an artifact without `$RAPID_LABEL` (`<version>-<sha>`: one
artifact, one commit), ships debug output (the no-debug audit: `*.dSYM`,
`*.pdb`, `*.debug`, a debug name segment, `*.map`, `debugger;` in shipped
JavaScript, inside tarballs too) or fails `gates_artifact`. The release
tag then lists `Artifact: <sha256> <name>` for each and
`Gates: release=... artifact=...`; that manifest is the release object
offline. After the release push, `release_publish` ships them and, when
origin is a GitHub repository and `gh` is present, the forge's release
object is created on `release/<v>` with the artifacts and the tag's message
as notes. The artifacts stay in `.git/rapid-artifacts/<v>`: `rapid release
--publish [<v>]` ships them again after a failed channel, refusing any file
whose checksum is not in the manifest. (`rapid doctor --history`)

`rapid doctor --history` checks merges in full only after the last dev tip
this clone verified clean: a note in the clone's git dir
(`rapid-history-verified`, never tracked, never a ref, so never pushed).
The version chain and the checks that span history (I5 to I9) run on every
run. The note is ignored, and every merge is checked in full, when the
recorded merge is no longer on dev's first-parent line, the version or
release tags reachable from it changed, or the verifier's own code or
config changed (`rapid`, `lib/`, `conf`, `FRAMEWORK`, the
`gpg.*` settings); the run prints which. `--all` forces the full walk;
`--since REV` and `--history-only` neither read nor write the note, and
`pre-push` and `rapid doctor --prove` do not use it.

| Id | Holds when |
|---|---|
| I1 | every first-parent commit on dev after the root is a two-parent merge whose branch range is linear |
| I2 | each carries exactly one version tag, the next version after the previous one |
| I3 | its subject is the merge subject naming that tag, with Branch-Base, Requirement, Gates, a tree trailer and Branch-Number; Tested-Tree (gates ran on the merge tree) or Merge-Tree (Gates: deferred to the close of batch) equals the tree of the merge, Branch-Base its first parent; a deferred receipt holds only with the passing close record on the last merge of its batch |
| I4 | the branch holds 1 to max_commits commits, each with a ruled subject, no commit-audit smell and at most one Red: trailer, on a [TEST] commit that neither ends the branch nor follows another Red: commit; a commit changing .rapid/conf or .rapid/admins is a [MODE] commit of those files only, by an admin at the first parent; since framework-policy a commit changing a framework path (framework_paths) is an admin's |
| I5 | main holds nothing dev lacks: its first-parent line is release merges "[MERGE] dev into main: <version>", each with a released dev commit (carrying an annotated release/<version>) as second parent and its tree, releases going forward, down to the root or a release made before release merges; every release tag made under the owner rule is annotated and tagged by an owner, by the policy at the release before it |
| I6 | every v* and release/* tag sits on dev's first-parent line |
| I7 | branch slugs are unique across landed merges and branches not landed yet, and so are branch numbers: one number never names two branches |
| I8 | requirements/<slug>.md exists at every merge of that branch and at dev's tip, and REQUIREMENTS.md at each merge is the register its requirement files generate |
| I9 | every replaced merge (a first-parent merge of a `safety/dev-<timestamp>` snapshot that dev lacks) is re-landed on dev or kept as a branch not landed yet, and no re-land is left half done |

## Policy (`.rapid/conf`, one `key=value` per line, a key set twice is refused)

| Key | Meaning | Default |
|---|---|---|
| `land_who` | `anyone` or `list` | anyone |
| `land_list` | emails allowed to land when `land_who=list` | empty |
| `land_on_conflict` | command started in the background when `rapid land` meets a conflict rebasing a stale branch (args: branch, the file listing the conflicting paths); land leaves the branch as it was and exits 4 | unset |
| `test_on_fail` | command started in the background the moment a scenario fails in any gate run (args: scenario name, its output file), so a fixer starts on that issue at once; failures also print live | unset |
| `max_commits` | most commits one branch may carry | 20 |
| `gates_commit` | command the `pre-commit` hook runs on the staged tree of every branch commit | none |
| `max_commit_lines` | most lines one branch commit may change, added plus deleted (commit audit) | 800 |
| `commit_body` | `required`: a change commit carries a body line of five words or more; `optional` drops the rule | required |
| `requirement_proof` | `required`: a requirement states eight words or more and a `Proof:` line naming a file in the branch tip (or `scenario slug`), or `Untested:`; `optional` drops the rule | required |
| `docs_rules` | comma-separated `<code glob>=<doc glob>` pairs: a branch changing code matching one changes a doc matching its pair, or its requirement says `Docs: none (<reason>)`; the merge records which (land) | unset |
| `signed` | `required`: every branch commit, merge and version tag is signed with a key git verifies (`%G?` is G or U): refused at commit when `commit.gpgsign` is off, and at land, push and I4; the release tag is signed too and its signer must be an owner (Production) | optional |
| `test_paths` | shell patterns of test paths, space separated; a behaviour change touches one (commit audit) | `test/* tests/* */test/* */tests/* spec/* */spec/* *_test.* *.test.* *_spec.* test_*` |
| `gates_each` | command the close of a batch (`rapid land`) runs on the own tree of every merge of the batch, all merges at once, before the one gate on the final tree; each result goes into the gate log of its merge, and a failing merge stops the close by name | none |
| `gates_fast` | command `rapid check --each` runs on every branch commit (and a `land --pr` on its merge tree) | none |
| `gates_full` | command the close of a batch (`rapid land`) runs once on the batch's final tree (a `land --pr` on its merge tree before the merge exists); a branch's own conf must set it (`none` lands without one, with a warning), and a dev without it lands only a branch that sets it | none |
| `gates_release` | command run on dev's tip before a release | none |
| `release_build` | command that builds the release artifacts on the released tree into `$RAPID_ARTIFACTS`, each named with `$RAPID_LABEL` (`<version>-<sha>`), with `BUILD_TYPE=release` | none |
| `gates_artifact` | command run on the built artifacts (`$RAPID_ARTIFACTS`) after rapid's no-debug audit | none |
| `release_publish` | command that ships the gated artifacts (`$RAPID_ARTIFACTS`, `$RAPID_VERSION`) after the release push; the forge's release object is made by rapid | none |
| `land_pr` | `required` makes review mandatory (`rapid land --pr`); on a forge `rapid setup --remote` then adds GitHub's review rule and the rapid-check status to the dev-only `rapid-review` ruleset | optional |
| `land_approvals` | approvals given on the exact merge commit that `rapid land --pr` waits for, and the forge's review rule requires (0 to 10) | 1 |
| `forge_repo` | OWNER/REPO when origin's URL does not name it | from origin |
| `agent_env` | variable names (comma or space separated) that mark an AI agent session besides `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` and `CODEX_*`: such a session never releases | unset |
| `smart_commit_cmd` | the command `rapid commit --smart` pipes its prompt to (stdin) and reads the message from (stdout); unset: the claude CLI in print mode, fresh context, read-only tools | unset |
| `tracker` | may only be `none`; a command tracker is operator-only (`git config rapid.tracker command:<path>`). `.rapid/trackers` ships three adapters that speak the contract of `lib/tracker.sh` (`get`, `link`, `transition`): `github` through `gh`, `jira` through `curl`, `mcp` through an MCP tracker server; the operator names a copy kept outside the repository, credentials come from the environment only, and a missing credential is a named refusal | none |
| `reqs_id` | the project token of the register's IDs, `<reqs_id>-R-<slug>` and `<reqs_id>-I-<slug>` (lib/reqs.sh) | REQ |
| `release_who` | `owner` (the admins listed in `.rapid/admins`) or `list`; read at main's tip, never dev's | owner |
| `release_list` | emails allowed to release when `release_who=list`; an agent never releases | empty |

Land always reads the conf committed on dev, never the copy of the branch, so a branch
cannot relax the gates it is judged by. The policy files are `.rapid/conf`
and `.rapid/admins`: a commit that changes one is a
policy flip, its own `[MODE]` commit of policy files only, authored and
committed by an admin listed in `.rapid/admins` on dev (commit-msg, land,
pre-push, I4), so no lander can empty a gate, open `land_who` or raise
`max_commits` on their own. `rapid setup` writes the setup author, when a human, as the first
admin in the root commit; with no admin listed, the one flip allowed is the
`[MODE]` commit that creates
`.rapid/admins`. An agent session, which never releases, is known by `CLAUDECODE`,
`CLAUDE_CODE_ENTRYPOINT`, a `CODEX_*` variable or one `agent_env` names, with
the agent guard or without it.

## Lint: quiet grep

Under `set -o pipefail` a pipeline ending in a quiet grep (`-q`, `--quiet`, `--silent`) turns a hit into a
miss once its input outgrows the pipe buffer. Feed grep a here-string (`grep -q x <<<"$v"`), or let it read
all of its input with its output sent to `/dev/null` (BSD grep, GNU grep 2.27 or later). `.rapid/lint/quiet-grep.py`
fails the gates on any such pipe in a tracked shell file, in every spelling; its `--self-check` proves each one.

## Lint: personal data

No tracked file holds a real person's home or session path or an email address outside the reserved domains
(`*.test`, `*.example`, `*.invalid`, `*.localhost`, `example.com`, `users.noreply.github.com`). Write
`<workspace>`, `<tmp>` or a `.test` address. `.rapid/lint/personal.sh` fails the gates on any finding.
The one exemption is the email rule in `.rapid/admins` at the repository root, where the admins belong; the same
address in any other file, a copy of it under another name or directory included, is refused, and a home path in
it is refused as anywhere else.

## Lint: doubled lines

A conflict resolution that keeps both sides leaves a line beside its stale twin, and the gates stay green.
`.rapid/lint/dup.sh` fails the gates on a top-level variable assigned twice in one `.rapid/lib/*.sh` or hook, on two
`echo` help lines within three lines that share their first 28 characters or three in four of their words, and on
the same pair of lines in a doc, code blocks included (lint-dup).

## Lint: docs against code

The docs state only what the code holds: the verbs and their flags (README's
command table), the invariant ids, the conf keys, the kinds and commit tags,
the subject limits, the policy defaults, the exit codes, the FLOWS section
of every verb, the files DESIGN's Layout names, and the scenario ids and
counts are read from the code and checked against the docs by
`.rapid/lint/docs.sh`, run by every gate. A consumer ties its own code to its
own docs with `docs_rules` (land refuses a branch that changes the code and
not the doc, unless its requirement says `Docs: none (<reason>)`).
