# rapidgit design record

rapidgit distils neo-git into one flow: branches in, one merge out, and the
history as the only database. The specification is the distillation spec of
the rapidgit design audit (principles, invariants, verbs, scenario matrix);
this file records the decisions taken while building it. The code now holds
thirteen verbs and invariants I1 to I9, and `.rapid/lint/docs.sh` keeps every
count and name in these docs equal to the code.

## Principles

1. Merge once. `rapid land` writes the merge commit with its final message,
   version tag and receipts; nothing on dev or main is amended or
   force-pushed.
2. History is the database. Versions, branch uniqueness and requirements are
   answered by walking dev's first-parent line; no counter, anchor or vault
   ref stores them (a safety anchor keeps a branch's fork point, nothing
   more).
3. One flow. A remote is a transport, not a mode: the same commands work
   with and without one, and the close of a batch pushes atomically when
   there is one.
4. Every guarantee has one enforcement point and one history check
   (`rapid doctor --history`, invariants I1 to I9 in `.rapid/lib/history.sh`).
5. Land applies the conf committed on dev, never the branch's own copy, so a
   branch cannot relax the gates it is judged by, and only an admin listed in
   `.rapid/admins` on dev changes the conf, in a `[MODE]` commit.

## Decisions

- Versions are `vYYYY.S.N`. N starts at 1 in every series; after a
  `release/<v>` tag the next land opens series S+1 at 1, and the first land
  of a new year is `vYYYY.0.1` (the spec's ".0 after a release" reads
  `.1` here, so the first land of every series has the same number).
- The landing year comes from the clock, or from `RAPID_YEAR` in tests and
  replays, so version math is deterministic under test.
- A branch must contain dev's tip to land (no stale merges): the merge tree is
  then the tree of the branch tip. A land into the batch runs no gate on it and
  records it as `Merge-Tree`; a `land --pr` gates that exact tree in a private
  worktree before the merge commit exists and records it as `Tested-Tree`.
- Lands need no lock and no queue, and no gate: every `rapid land` goes into
  the open batch, local and offline, and the land without `--batch` runs the one test on
  the final tree and the one push (owner rule: a batch is many branches, one
  test, one push; no test per land or per push inside it). Two lands racing
  for one version take it once (the version tag is created before dev moves,
  and dev moves by compare-and-swap), so the loser stops with dev unchanged,
  syncs and lands again. Only `land --pr`, which publishes one merge at once,
  gates that merge itself.
- A test-first commit that fails its test on purpose carries `Red: <test>`
  and cannot be a branch tip; `rapid check --each` runs the fast gate on every
  branch commit and names any unmarked red commit.
- The vocabulary is neo-git's, the owner's terms: a working branch is a
  branch (`rapid branch`, `pool/v<series>/n<N>.<kind>.<slug>`), a landed tip sits in the
  vault, a fork point under safety, and the merge says `Branch-Base:` and
  `Branch-Number:`. A branch never landed simply stays a branch, its anchor kept
  forever; `rapid status` and `rapid doctor` list the branches not landed yet, as
  neo-git's own branch report did. These are the only forms
  rapid reads: no other branch prefix or trailer family parses. The anchor
  commit says `rapid branch <name>: fork point`.
- Landing is only through `rapid land`, never a forge merge button, because a
  forge-written merge cannot carry the receipts and would bring back the
  amend this design removes.
- Offline is a state, not a mode: with origin configured but unreachable,
  `rapid land` lands locally and says so; `rapid sync --dev` later publishes the
  local lands (fast-forward) or re-lands them onto a moved origin dev through
  `rapid land`, so a re-landed merge passes the gates again and takes the next
  version. The dev it replaced stays whole in one snapshot branch
  `safety/dev-<timestamp>`, neo-git's snapshot form, pushed with the re-land's
  close and never moved or deleted; no commit is lost. The re-land
  plan lives in `.git/rapid-reland`, so a conflict stops it without dropping
  the remaining lands: `--continue` resumes and `--abort` keeps the rest as
  branches not landed yet. doctor reports a half-done re-land and any replaced merge
  that is neither re-landed nor kept as a branch (I9). While a re-land is in progress a
  hand `rapid land` is refused with the `--continue`/`--abort` instruction (the
  plan lands each branch itself), a plan head whose slug is already on dev is
  dropped from the plan, and `--abort` never keeps a landed slug, so an
  branch not landed yet never repeats a slug (I7). A `Fixes:` trailer that names a
  re-landed commit is rewritten to the commit's new sha.
- A clone never builds on an unverified dev: before local dev takes origin's
  (in `rapid branch`, `rapid land`, `rapid sync`, `rapid release` and `rapid sync
  --dev`), every incoming first-parent commit is checked as pre-push checks
  a landed merge (I1 to I4 and I8). A commit rapid land did not make, pushed
  past the hooks onto a remote without rulesets, is refused there by name,
  author and invariant, and local dev stays where it was; plain `rapid
  doctor` names it too, from origin's dev as last fetched.
- Detection runs as early as the facts exist: the commit that would push a
  branch past `max_commits` is refused before it is written
  (`prepare-commit-msg`), a placeholder requirement at the branch's first
  commit and, with `gates_commit`, a staged tree that fails it are refused
  at commit (`pre-commit`). A branch push is transport: pre-push runs no gate
  on a branch (only the static checks: size, messages,
  banned files, policy), and `rapid sync` never pushes (`rapid sync --push`
  shares the branch, with a lease). The close tests the tree it pushes, once, so
  a red branch commit can sit on origin but never reaches dev.
- No gate is ever silent. `rapid setup` and `rapid doctor` name a gate whose
  command runs a `.rapid/tests` or `.rapid/lint` script the repository lacks (a
  fresh vendor drops the framework's tests); land refuses a branch whose own
  conf leaves `gates_full` unset, lands an explicit `gates_full=none` with a
  warning (and, once, a branch that sets it on a dev that has none), and
  `doctor --prove` counts the merges that carry no gate instead of calling
  every gate passed. README's quick start sets the gates before setup and
  runs as written (fresh-vendor).
- A clone that never ran `rapid setup` has no hooks: the verbs that write
  (branch, commit, land, sync, release) refuse with `rapid setup` instead of working
  unguarded, and `rapid status` says what is missing; `check`, `bisect` and
  `doctor` stay usable, since the forge workflow runs them on a runner with
  no hooks.
- A refused close push changes nothing: dev, the tags and the batch stay, and
  `rapid land` again publishes them. A `land --pr` push that fails undoes its
  tag and leaves dev unmoved.
- Safety anchors stay forever (the owner's rule, kept from neo-git). `rapid
  branch` writes the branch `safety/v<series>/<number>.<kind>.<slug>`, as neo-git did, on an
  anchor commit whose only parent is the fork point, so it records who
  forked and when and two branches never share one. It rides with the branch: pre-push sends it in one push right after the
  branch push when the remote lacks it, land puts it in its
  atomic push, and `rapid sync --dev` publishes those of offline lands. A
  sync, a rename (which adds the new name's anchor) and a land never
  touch it. pre-push and the agent guard refuse deleting, moving or forging
  one, and on a forge `rapid-safety-lockdown` refuses it to everyone but
  admins. Anchors are branches, not refs outside `refs/heads`, because a
  forge ruleset reaches only branches and tags (the owner settled on
  neo-git's branch namespace).
- Branch numbers are back from neo-git (the owner refused their removal), in
  rapidgit's shape: `rapid branch` takes the number itself, no allocator workflow and
  no extra command. neo-git's allocator could not serialize two clones
  offline (its RUNBOOK says a clone that allocates before fetching another's
  push can pick the same number). Here opening a branch never pushes (a batch
  is one push): a number is taken in the clone, create-only, in the refs its
  work trees share, counted past every number origin holds, and the close's
  one push reserves it on origin with the branch's anchor. Two clones that
  took the same N before either published are settled without a push too:
  `rapid sync` and `rapid land` renumber the unpublished branch, and the close
  refuses a collision that appears after the land. A clone that cannot
  reach origin writes the same form, `n<N>`. N is a Lamport count
  (one more than the highest number known), so a branch started after another
  was seen always numbers after it, and the reservation's commit date orders
  the rest; reservations are kept
  forever, so branches not landed yet keep their place. The number rides in the
  branch name, the anchor and the merge's `Branch-Number:` trailer; the slug
  stays the requirement file's name and the merge subject's, so I7 and I8
  read as before.
- Banned files and kept branches hold for humans too (neo-git's
  "developers never delete branches" ruleset and its banned list, which rapidgit
  had left to the agent guard). `pre-commit` refuses a staged banned file
  on every branch, and land and a branch push refuse a branch commit that adds
  one past the hook, so a `--no-verify` commit still never reaches dev or
  a shared remote. pre-push refuses a hand deletion of a branch on the remote
  and lets through only rapid's own moves, recognised in the same push (dev's
  new tip holds the branch); the agent guard
  denies deleting or renaming dev, main or a branch outright. On
  the forge `rapid-branch-deletions` lets only admins delete a branch (see the
  deletion decision below).
- Vault branches are back (the owner's decision): pointers to the start
  (`safety/`) and the end (`vault/`) of every branch, not redundancy. neo-git
  archived a merged branch to a frozen `vault/` branch by a separate claim
  step; here `rapid land` writes `vault/v<series>/<number>.<kind>.<slug>` on the branch tip in its
  own atomic push, so the merge stays merge-once and no extra command
  exists. pre-push, the guard and `rapid-vault-readonly` keep it like an
  anchor.
- Branches are deleted on the forge by admins only, as neo-git's
  `branch-deletions` ruleset had it (`rapid-branch-deletions`). So `rapid land` no
  longer deletes the branch inside its atomic push (a refused deletion would
  refuse the land): it pushes dev, the tag, the anchor, the number and the
  vault branch, then tries the deletion apart. An admin's succeeds; anyone
  else's branch stays, landed, listed by `rapid status` and `rapid doctor` until an
  admin's `rapid branch --delete-landed` removes it. A branch never landed is never
  deleted: it stays a branch.
- A slug that lands elsewhere first is refused at sync (I7). `rapid branch
  --rename` rewrites the branch so its requirement file always carried the
  new slug, never deleting the file the other branch landed.
- dev moves by fast-forward inside whichever work tree holds it, so a land
  from a linked worktree leaves the main checkout current. The same holds
  when `rapid branch`, `rapid land`, `rapid sync` or `rapid release` take origin's
  newer dev: a work tree with dev checked out follows it, so a branch started
  from a stale dev checkout never stages the reversal of a coworker's land,
  and `rapid branch` refuses to start when the work tree it stands in could not
  follow.
- main is production. Publishing is a release reaching main, and only the
  owner promotes dev to main; dev is integration, and pushing dev, branches or
  tags to a remote is transport, never publishing. The owner is an
  admin listed in `.rapid/admins` (`rapid setup` writes the setup author as
  the first admin in the root commit, or the one `--owner` names; when an
  agent sets up without it, release refuses everyone until `.rapid/admins`
  exists), or `release_list` under `release_who=list`.
  Who may release is read as committed at main's tip, so a branch landed on
  dev never grants itself the right, and a change of owner takes effect
  only through a release the current owner makes; while main lists
  no admin (a repository first released under this rule), dev's admins
  rule. An agent session never releases. `rapid release` refuses anyone else before its gate, the tag
  records `Released-By:`, pre-push refuses main moving to a release tagged
  by anyone else (or to a lightweight tag), I5 judges every release tag's
  tagger against the policy at the release before it, the agent guard
  denies `rapid release` (its `--dry-run` stays allowed) and any `release/<v>`
  tag an agent would create, write or push, and on a forge the `rapid-main`
  ruleset lets only the repository's admins update main and the
  `rapid-release-tags` ruleset only them create a `release/*` tag. A release
  tag pushed without main meets pre-push's tagger check too, since a
  release tag alone opens the next series.
- A release is `rapid release`: the release gate runs on dev's exact tip,
  `release/<version>` tags it and main takes it by a `--no-ff` release merge
  `[MERGE] dev into main: <version>` (first parent the old main, second
  parent the released dev tip, its tree, its body the branches landed since the
  last release), in one atomic push. So `git log --first-parent main` lists
  the releases, as neo-git's dev to main merges did ("the merge commit IS the
  released version"). main holds nothing dev lacks (I5: every release
  merge's tree is a released dev commit's, its releases go forward), and
  the next land opens the next series, so every version says which release
  precedes it. When main's ruleset on the forge requires a pull request (a
  direct push to main is declined there), the owner's `rapid release` opens
  or updates the dev to main PR and merges it through the forge's API
  (`merge_method=merge`, `sha` dev's tip, the release subject and body),
  then fetches main and checks the merge is the release merge (parents the
  old main and dev's tip, dev's tree) before it pushes `release/<v>`; a
  declined merge exits 3 with nothing tagged, a squash or any other merge
  is refused untagged, and a release whose tag push failed is finished by
  the next `rapid release`. Without such a forge the merge is written here
  and pushed with its tag atomically. A main fast-forwarded before release merges is the base the
  next release merge sits on; pre-push refuses main moving to a dev commit
  or to any merge but a release merge.
- Release identity, from neo-git's build on tag, release integrity gates and
  sha-labeled artifacts: what ships is the gated artifact of the release
  tag. `release_build` builds on the released tree in a clean worktree, so
  an artifact comes from exactly one commit; a build that edits tracked
  files, an unlabeled name (`<version>-<sha>`), debug output (the
  deterministic layer of neo-git's no-debug audit, tarballs unpacked) or a
  failing `gates_artifact` refuses the release before any tag exists. The
  tag carries the manifest (`Artifact: <sha256> <name>`), which is the
  release object offline; online, `release_publish` and the forge's release
  object (`gh release create` on `release/<v>`) ship the same bytes, kept in
  `.git/rapid-artifacts/<v>`, and `rapid release --publish` reships them only
  when every checksum matches. neo-git's Claude layer of the audit stays a
  project's choice through `gates_artifact`.
- Finding a regression is `rapid bisect GOOD BAD -- CMD`: a binary search over
  dev's first-parent merges finds the branch that broke CMD, then a search over
  that branch's commits finds the commit that broke it, skipping commits marked `Red:`. It
  works because every first-parent commit is a merge that parses, starts and
  lints on its own tree (`gates_each` at its close) and every branch commit is
  atomic; `rapid check --each` runs the fast gate on each commit on request.
- Client hooks are a guard rail. On a forge, server rulesets on dev, main,
  branches and tags are the authority, and with `land_pr=required` GitHub's
  own review rule on dev is what a hostile change meets.
- `rapid bisect` treats a command exit of 125 as "cannot test this commit", as
  git bisect does: the commit is skipped, and when a skipped commit could be
  the one that broke it the report names it instead of guessing.
- The agent guard and preflight come from neo-git with their parser and rules,
  renamed to the `.rapid` layout. The guard exports no identity and checks none:
  who may commit is the repository's own access. The guard is a best-effort
  guard against agent accidents, not a security boundary: it matches known
  command shapes and allows unknown ones; a hostile agent needs an OS sandbox
  and the server rulesets. `.rapid/FRAMEWORK` marks this repository as the
  framework source, the one place `.rapid` may be edited; `conf` and
  `admins` are the consumer's own files and stay editable everywhere.
- `rapid setup --remote` applies eight rulesets (dev and main: no deletion, no
  force push; `rapid-main`: main takes no update at all except from the
  repository's admins, since main is production and only the owner promotes;
  `rapid-release-tags`: no new `release/*` tag except from those admins;
  `rapid-review`: dev alone, where `land_pr=required` adds the review rule;
  neo-git's `rapid-safety-lockdown`
  (safety branches: no update or deletion; creation stays open, since every
  lander writes its own anchor now that neo-git's CI bot, which bypassed a
  creation lock, is gone), `rapid-vault-readonly`
  (vault branches: no update or deletion) and `rapid-branch-deletions` (branches:
  no deletion), each bypassed by repository admins only; `v*` and `release/*`
  tags: no update, no deletion) and writes a read-only `rapid-check` workflow.
  The workflow never runs the candidate's checker: it extracts `.rapid` from
  dev (for a dev push, from dev as it was before the push) and runs that
  copy against the candidate, so a branch that replaces `.rapid/rapid` is judged by
  the checker it tried to replace. With `land_pr=required` the dev-only
  `rapid-review` ruleset also carries GitHub's own `pull_request` rule (`land_approvals` approvals,
  stale approvals dismissed on a push, the last push approved by someone
  else) and the rapid-check status: `rapid land --pr` publishes the merge as the
  branch's head, reviewers approve that exact commit, the workflow proves it
  (`rapid check --merge`: shape, both gates on its tree, approvals on its sha),
  and dev then moves to it by a push of that head. Two limits are stated, not
  hidden: a candidate's gates are its own tests, and a candidate can edit the
  workflow file, so a status alone can be produced by the change it judges;
  the review rule is the authority, the status a second line. With
  `land_pr=optional` a land is a plain push and the workflow proves each new
  dev merge after the push (`rapid doctor --prove`); a receipt that does not
  hold fails it. A second job, `rapid-linux`, runs the full gate on ubuntu
  (bash 5, GNU tools) for every branch and dev push. The workflow checks the
  full invariants only for merges after its base (`--since`); the version
  chain and the invariants that span history still run on every push.
- A local `rapid doctor --history` stays cheap as history grows: it checks
  merges in full only after the last dev tip this clone verified clean, a
  note in the git dir (`rapid-history-verified`). The note is a cache, not a
  second database: losing it costs one full walk, and it is trusted only
  while the recorded merge is on dev's first-parent line, the tags it
  reaches are unchanged and the verifier (rapid, `lib/`, conf,
  `FRAMEWORK`, `gpg.*`) is the one that wrote it. Merges are immutable and
  every per-merge check reads only the merge and the rules at its first
  parent, so nothing else can change a verdict already given; `--all`
  re-walks everything. For the same reason the merges a walk does check are
  checked at once, one worker per core (`RAPID_HISTORY_JOBS` overrides), the
  version chain read from the tags first and the findings printed in history
  order; the pre-push dev arm checks a push's new merges the same way
  (parallel-history).
- The gate log is durable (neo-git's CI log archive, row 135): `rapid land`
  records each merge-tree gate it runs (command, exit code, duration and
  log tail) and stores the records as a note on the merge under
  `refs/notes/gates`, pushed in the same atomic push as dev and the tag. A
  land first merges origin's notes into its own (and `rapid sync --dev`
  publishes an offline land's), so the ref only ever fast-forwards and two
  clones never drop each other's logs. The `Gates:` trailer says what
  passed; the note says what ran and what it printed, so a later regression
  can be compared with what the gates showed then. `rapid doctor --prove`
  prints the stored log beside its rerun. pre-push refuses deleting or
  rewriting the ref and the agent guard refuses writing, rewriting or
  deleting it by hand. A merge landed before the archive says so.
- A receipt is never only trusted: pre-push reruns the fast gate on any merge
  this clone did not gate (a `--pr` land and the close of a batch leave a local proof note naming the merge's
  tree and this clone's private id, so a fetched or copied note never
  counts; the agent guard denies writing it by hand), and a dev push must
  carry each new merge's version tag.
- `rapid setup --upgrade SOURCE [REV]` runs on a branch, so a framework upgrade or
  downgrade lands, gates and versions like any change; it keeps `conf`,
  `admins` and `requirements/` and never vendors the framework's tests, bench
  or source marker.
- Under `land_pr=required` on GitHub, `rapid land --pr` lands through the PR's
  merge API (the live canary showed GitHub refusing the push of dev that the
  merge-as-head path makes): the PR head is the tested branch tip, GitHub writes
  the merge once with rapid's subject, body and trailers, and rapid verifies the
  parents (old dev, tested head), the tree (Tested-Tree) and the subject
  before tagging; I1 to I9 hold on that merge like on any other. The review
  rule asks for the last push's approval only when `land_approvals` asks for
  any. The path below stays for `land_pr=optional`.
- `rapid land --pr` publishes the merge itself as the branch's head and opens or
  updates its PR with the exact merge subject and body. It counts only
  approvals given on that merge sha (an approval of an earlier head never
  counts, so a new commit dismisses it) and, with `land_pr=required`, waits
  for the rapid-check status on it; then dev moves to exactly the approved
  commit. The forge's merge button is never a landing path.
- `rapid land` deletes the branch on origin (apart from its atomic push) only
  with a lease on the sha it landed, and refuses while origin's branch holds commits the lander lacks
  (a copy the lander rebased itself is not lacking: its preflight ref holds it),
  so a coworker's push to a shared branch is never discarded.
- The conf and admins that judge a branch are the ones committed on dev;
  per merge, history uses the ones at its first parent.
- The requirements register (`REQUIREMENTS.md`, the project-reqs model with
  protected rows and a graveyard) comes back as a view, not a database:
  `lib/reqs.sh` renders it from the requirement files of one tree, so the
  gate can prove it on the exact tree it lands. Fields live in the
  requirement file, and since a landed file is never edited, a later state
  is written by the branch that causes it (`Promotes:`, `Completes:`,
  `Scraps:`); the tree alone decides every row, with no history walk. IDs
  are the slug, the one name unique offline. Rows are sorted by slug and the
  register carries no totals line; a row merge driver (`lib/reqs-merge.sh`,
  declared by `rapid setup` and `rapid branch` in the clone's config and
  `info/attributes`, never in a tracked file) merges two branches' rows, so no
  rebase, merge or cherry-pick stops on it, and `rapid sync` and the re-land
  also regenerate it in every replayed commit. Defaults keep every older requirement file valid: done, a
  priority by kind, tests from the scenario ids its text names; rows with
  none say `needs units`, the visible test backlog.
- A ticket id travels from `rapid branch --ticket` into the requirement file and
  the merge's `Ticket:` trailer with no tracker at all. A command tracker runs
  an executable, so it is honoured only from operator settings
  (`RAPID_TRACKER`, `git config rapid.tracker`), never from the committed conf and
  never when the adapter is a file the repository tracks. A failed link or
  transition is reported and never undoes a branch or a land.
- rapid keeps no list of authors: who may commit and push is the
  repository's own access, on the forge and on the machine. The roles rapid
  does keep, who releases and who flips policy, are the admins of
  `.rapid/admins`. An agent session never releases, and the agent guard denies an agent a
  push to main and a release.
- `rapid release` writes the branches still open into the release tag, oldest
  first with their first and last commit dates (origin's branches when there is
  a remote): open branches are refs that move, so the release is where the
  snapshot of work in flight stays.
- `Fixes: <sha>` must name a commit on dev; a revert is a branch of its own that
  keeps the reverted branch's requirement file (I8) and links the merge it
  undoes, and the repaired work lands as a new branch linking the revert.

## Layout

The files of the CLI, its libraries, hooks, lints and runner (the docs lint
checks the libraries, hooks and lints):

- `rapid`: the CLI, thirteen verbs, one file.
- `lib/core.sh`: shared helpers, the kinds and the named rules.
- `lib/message.sh`: the commit and merge message rules and the subject limits.
- `lib/version.sh`: version math from dev's first-parent line.
- `lib/policy.sh`: the conf keys and their defaults, the gates, the
  per-commit fast gate, the owner rule, sizes, tests and docs rules.
- `lib/history.sh`: invariants I1 to I9, the per-clone history checkpoint
  and the gate proofs.
- `lib/tracker.sh`: the tracker contract.
- `lib/audit.sh`: the deterministic commit audit (size and test smells).
- `lib/reqs.sh`: the REQUIREMENTS.md register generated from
  `requirements/`; `lib/reqs-fix.sh` regenerates it on a rebase or re-land,
  and `lib/reqs-merge.sh` is its merge driver.
- `lib/judge.sh`: a branch judged by dev's framework: `rapid land`, `commit-msg`
  and `pre-push` exec dev's committed `.rapid` (exported once per dev framework
  tree under `<git common dir>/rapid/judge/`) when the work tree's copy differs.
- `hooks/pre-commit`: banned files, the placeholder requirement, the
  regenerated and staged `REQUIREMENTS.md` and `gates_commit` at commit.
- `hooks/prepare-commit-msg`: the branch size cap before a commit exists.
- `hooks/commit-msg`: message, policy and size rules at commit.
- `hooks/pre-push`: what reaches a shared remote.
- `lint/run.sh` runs every lint: `lint/docs.sh` (docs against code),
  `lint/personal.sh` (no personal data; `.rapid/admins` alone may hold
  a real address, the admins being its purpose),
  `lint/dup.sh` (no line a conflict resolution doubled) and
  `lint/quiet-grep.py` (no quiet grep in a pipeline).
- `tests/run.sh` runs the scenario matrix concurrently, `-j N` at once
  (default `RAPID_TEST_JOBS`, else every scenario at once); every scenario runs with
  its own `TMPDIR` under the run's directory, removed with the run, and
  results print in file order, so verdicts and output match a serial run
  (parallel-runner). A run holds a session
  fixture (pytest-xdist style, `RAPID_TEST_FIXTURE` under the run's
  directory): `mkrepo DIR [origin]` sets a repository up, with its seeded
  bare origin at `$T/origin.git` when asked, once per run and per setup
  input (actors, `RAPID_`/`GIT_` environment, global git config), under a
  lock, and every later call copies it; a set commit date or a non-empty
  directory builds afresh (session-fixture).

## Bootstrap of this repository

The root commit is the seed `rapid setup --owner <email>` wrote: its
`.rapid/admins` lists the owner as the first admin, not the author of the
commit.

Every feature landed as one branch into one batch, the one that began at the
seed: the receipt of every merge on dev names that batch
(`Gates: deferred to the close of batch <id>`), and each branch keeps its
safety anchor and its vault branch. What the close ran on each merge is in
the gate log, and nothing else is claimed: `git notes --ref=gates show <merge>`.

## What rapidgit gives up, and why each guarantee holds anyway

| neo-git machinery | rapidgit | The guarantee, and where it lives now |
|---|---|---|
| Merge first, then a separate claim amends, pushes again, tags and vaults | `rapid land` writes the final merge once | Version, receipt and requirement are in the merge commit itself (I2, I3); nothing on dev is ever rewritten |
| Server-allocated branch numbers and the allocator workflow | `rapid branch` numbers every branch `n<N>` in the clone; the number reaches origin in the one push of the batch | One number never names two branches (I7): a branch whose number another clone published first takes the next free number at its land |
| `safety/*` anchors and `vault/*` archive refs | `safety/v<series>/n<N>.<kind>.<slug>` and `vault/v<series>/n<N>.<kind>.<slug>` branches, kept forever by pre-push, the agent guard and the forge rulesets | The fork point of every branch survives a sync, a rename and a land in its anchor; its landed tip stays in its vault branch |
| Machine-authored reconcile branches | `rapid sync` by the author of the branch; `rapid sync --dev` lands offline work again | A merge landed again takes the next version; a conflict stops a plan that can be resumed, never drops a land (I9) |
| A gate on every merge before it exists | a land into the batch runs no gate; the close (`rapid land` without `--batch`) runs `gates_each` on the own tree of every merge and one gate on the final tree | Each merge says what ran: `Gates: deferred to the close of batch <id>`, and the close records are in the gate log. Only the final tree passed the full gate; every other merge is proven to parse, start and lint. A `land --pr` still gates its own merge tree |
| GitHub merge button, PR validation and claim workflows | `rapid land --pr` for review | Under `land_pr=required` the ruleset of dev carries the review rule of GitHub and the rapid-check status, computed by the checker dev holds |
| Off-grid and connected modes | one flow; a remote is transport | The same checks run with origin and without it |
| CI matrix and the required audit scripts | `gates_fast`, `gates_full`, `gates_each`, `gates_release` in `.rapid/conf` | `rapid check --each` runs the fast gate on every branch commit on request; the close runs the full gate once; a release passes the release gate |
| Sixteen agent skills, user overrides and a lazy loader | one skill, `skill/SKILL.md`, whose task table loads one lens file per task | `skill/lenses/RULE-MAP.md` lists each rule of the neo-git lenses with its home |
| Doc-freshness gate and protocol lint | `.rapid/lint/docs.sh` in every gate | Verbs and flags, invariant ids, conf keys, kinds and tags, scenario slugs and counts in the docs are read from the code and must match it |
| CHANGELOG file and the `changelog` tool | `rapid changelog` | Generated from the first-parent merges of dev; no file is kept, since a file would be a second database |
| Live canaries on public throwaway repositories | `tests/canary/live.sh`, run by hand in one persistent public canary repository | The gates never run it: live forge behaviour is proven only by a run made by hand. The scenarios drive the forge through a `gh` stub |
| Reconstruct, shuttle, snapshot and rewrite tooling | out of the core | History quality is enforced at land, not repaired afterwards; the rebuild rules live in the `rebuild.md` lens |
| The Codex adapter | none; `rapid setup --agent` serves Claude Code only (owner-approved removal 30) | The agent guard, the write guard and the preflight serve Claude Code |
| The table of known authors, its checks, its agent rows and its verb | none (removed by the owner); the roles moved to `.rapid/admins` | Repository access decides who commits and pushes; the admins release and flip policy, and `rapid setup --owner` names the first one (scenario `setup-owner`) |
| The merge queue that tested ahead of time, its lock and its store | none (removed by the owner) | One close tests one tree; two lands racing for one version take it once, since the version tag is created before dev moves |
| Bench harness and agent runner | `bench/speed.sh`, `bench/loadbytes.py`, `bench/multiplier.sh`, framework only | The bench measures the flows of rapidgit on scratch repositories; no model is called. A multiplier is printed only against a row of the baseline, marked measured or recorded |

Kept as they were: the message rules, the protected-ref and
tag rules of pre-push, the agent guard and preflight, the operator-only
command adapter of the tracker contract.

The agent skill is one loader with lazy lenses: `skill/SKILL.md` holds what
every task needs and a task table; each lens file (commit, merge, history,
forge, verify, rebuild) holds the rules of one task and is read only for that
task. `skill/lenses/RULE-MAP.md` lists each rule of the neo-git lenses with
its home, so an audit can check that none was lost.

The commit audit is deterministic: the subject joiners, Cause and Fix on a
fix, the size cap as a conf key, a behaviour change carrying its test (or, for
a fix, a `Proof:` trailer naming the existing test that proves it) are rule
`commit-audit` in `lib/audit.sh` and `lib/message.sh`, checked at commit-msg,
`check --each` and `--audit`, land, pre-push and I4. The joiners are matched
as words, so a single concern phrased with one of them is reworded. The
scenario repositories set `test_paths=*` so the test smell stays out of
scenarios about other rules (scenario `commit-audit` sets real paths).

The advisory commit judge is `rapid check --judge`: a model review of the
commits of a branch against what the hooks cannot check, with file tools only
and verdicts bound to a nonce. It never blocks a land; `--strict` makes it
fail for teams that want it as a gate.

## Live canary

`tests/canary/live.sh` drives the flows against a real forge in one
persistent public repository, by hand, and never deletes a repository: every
run lands branches whose slugs end in the run id, and its cleanup removes only
the branches not landed yet of that run by name. It needs the `repo` and `workflow`
scopes of gh, never `delete_repo` (scenario `live-canary` proves that
against a stub). The gates never run it, so no result is recorded here.

## Frictions removed

Each row names a friction of the predecessor, as the owner or the record of
its development described it, and what removes it here.

| Friction | What removes it |
|---|---|
| Every land ran the whole suite, one branch at a time | `rapid land` is local: one merge, one tag, no gate, no push (scenario `batch-land-local`). The batch is the only landing path |
| The suite ran one scenario at a time | `tests/run.sh` starts every selected scenario at once by default (scenario `parallel-runner`) |
| A queue of tests ran ahead of time | Removed by the owner. One close tests one tree |
| Tests ran between branches after the owner asked for a batch | A branch push is transport and runs no gate; `rapid sync` never pushes (scenario `push-is-transport`) |
| A batch was not one push | Opening a branch pushes nothing, and while a batch is open pre-push refuses every push but the push of the close (scenario `batch-one-push`) |
| A failed close threw the batch away | A failed close keeps dev, the tags and the branches, names the branch that broke the close and leaves the fix to one more branch (scenario `batch-land`); `rapid land --prune` is the only rollback |
| A stale branch needed stacking by hand | `rapid land` rebases a stale branch itself behind a preflight ref and lands a list in order; a conflict leaves that branch as it was (scenario `land-rebases`) |
| The close ran the fast subset, then the full set that contains it | The close runs one gate, `gates_full`, once (scenario `batch-close-one-gate`) |
| A test that another one replaces ran to its end | A branch that joins the batch stops the running close (scenario `batch-join`) |
| Landing, closing and undoing a batch were spread over several commands | The batch surface lives on `rapid land` alone, by owner ruling: `--batch` defers the close, the land without it closes, `--failed-gates-only` runs again what failed, `--halt` stops a close, `--prune` drops the batch; a land run again finishes only what is owed (scenarios `land-closes-batch`, `batch-close-failed-gates`) |
| Failures were reported at the end of a run | Each failure prints the moment it happens and `test_on_fail` starts a fixer on it at once (scenario `parallel-runner`) |
| The history walk was linear | Merges are checked concurrently, one worker per core (scenario `parallel-history`) |
| A batch merge claimed gates that never ran on it | A batch merge says `Gates: deferred to the close of batch <id>`; the close records what it ran, per merge and on the final tree (scenario `batch-receipts`) |
| Two branches adding a scenario picked the same number | Scenarios are named by slug; the matrix and a `Proof:` line key on the slug |
| A land reported its refusals one at a time | Land lists every static refusal at once before any gate (scenario `all-refusals`) |
| A fix had to touch a test path though a test already proved it | A `[FIX]` names the existing test in a `Proof:` trailer (scenario `fix-names-its-proof`) |
| main moved without the owner | Only an admin releases, by a `--no-ff` merge; an agent never pushes main (scenarios `owner-release`, `main-protection`) |
| Words the owner never approved | The vocabulary is pool (every branch in flight in the repository), branch (one feature unit), batch (the grouping one developer lands with one test and one push; a batch ⊆ the pool), vault, safety, dev and main; branches read `pool/v<series>/n<N>.<kind>.<slug>` as in neo-git |

## Measured

This file quotes no timing. The measurements of this repository are records,
not prose: the duration of each close and of each per-merge proof is in the
gate log (`git notes --ref=gates show <merge>`), and `bench/speed.sh` prints
the time of each flow on the machine that runs it. `bench/multiplier.sh`
compares like with like, the gated land of the predecessor against a batch
land plus its share of the close, and prints a multiplier only for a row
of its baseline; the rows of `bench/lean-baseline.md` are recorded, read from
the development record of the predecessor and never timed by a bench, and the
table says so row by row. The bench refuses a baseline with no row.
