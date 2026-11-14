# rapid: the agent manual

How an AI agent works in a repository that vendors `.rapid`. Imperative on
purpose: do what a line says, never what it forbids. The short form that stays
loaded is [SKILL.md](SKILL.md); the lenses under [lenses/](lenses/) hold the
detail of one task each. This manual says what you are to rapid, the order of
work, and what stops you when you go wrong.

## 1. What you are to rapid

- You are an agent session when your process carries `CLAUDECODE`,
  `CLAUDE_CODE_ENTRYPOINT`, a `CODEX_*` variable (`CODEX_HOME` alone is a
  human's config path), or a variable the conf key `agent_env` names.
- main is production. An agent session never releases: `rapid release` refuses
  it by name ("an agent never promotes dev to main: report that dev is
  ready"). `rapid release --dry-run` is yours to run; report what it says.
- `rapid setup` run by an agent session writes no admin. When you initialize a
  repository, name its owner: `rapid setup --owner <email>`. Never name
  yourself, never invent an address.
- The guard is installed with `rapid setup --agent`. It denies the commands of
  section 6 before they run. `rapid doctor` says so when the guard is missing
  in an agent session: install it, then go on.
- The guard is a guard against accidents, not a sandbox. A command it does not
  know is not a permission.

## 2. Start of a session

1. Load [SKILL.md](SKILL.md). Read one lens only when its task comes up.
2. `rapid status`: where you are, the open branches, the last version.
3. `rapid doctor`: hooks active, conf sane, guard installed. Fix what it names
   before you write anything.
4. A clone that never ran `rapid setup` refuses `branch`, `commit`, `land`,
   `sync` and `release` with the one command to run. Run it.

## 3. The work loop

1. Open the branch: `rapid branch <kind> <slug> -r "<requirement; how its tests
   prove it>" --proof <test file or scenario slug>`. Kinds: feature fix
   refactor docs test chore. The branch is `pool/v<series>/n<N>.<kind>.<slug>`;
   rapid picks the number and writes the safety anchor. Never pick a number.
   A requirement nothing can test carries, in its file, a line
   `Untested: <reason, five words or more>` in place of the proof.
2. Never edit `REQUIREMENTS.md`: pre-commit regenerates it from
   `requirements/<slug>.md`. Edit the requirement file.
3. Commit one concern at a time, the change and its test in the same commit.
   Stage by name. See [lenses/commit.md](lenses/commit.md).
4. The message rules, checked by commit-msg, by land and by `doctor --history`:
   - subject `[NEW|FIX|REFACTOR|DOCS|TEST|REVERT|HOTFIX|MODE] Capitalised
     summary`, 12 to 72 characters, no final period, a blank second line;
   - no em or en dash; no `Co-Authored-By:` trailer;
   - a subject that needs `and`, `with`, `plus`, `or`, `then`, `beside`, `+` or
     `,` joins two concerns: split the commit;
   - a change commit has a body line of five words or more saying what and why;
   - a `[FIX]` body carries a `Cause:` paragraph, then a `Fix:` paragraph;
   - `Red: <test>` marks a `[TEST]` commit written first and left red, once,
     and the next commit turns it green.
5. Check before you land, all read-only:
   - `rapid check --each`: the commit audit and the fast gate on every commit
     of the branch;
   - `rapid check --audit`: the commit audit alone;
   - `rapid check --land <branch>...`: every static land check, every
     violation in one list.
6. `rapid commit --smart` is opt-in: a fresh model context composes the message
   for the staged diff and the hooks still judge it. Use it only when asked.

## 4. The batch protocol

- `rapid land --batch` lands the branch into the open batch and defers the
  close: one local merge, one version tag, no gate, no push. Use it for every
  branch but the last.
- `rapid land`, without `--batch`, lands the last branch and closes the batch:
  every merge is proven on its own tree (`gates_each`), the final tree is tested
  once (`gates_full`), and one atomic push carries dev, the tags, the safety and
  vault branches and the gate notes. With no batch open it is a batch of one.
- It is idempotent. After a push origin refused, or a close that failed and
  whose fix has landed, run `rapid land` again: from the landed branch or from
  dev it finishes only what is owed, and a tree that already passed is not
  tested twice. There is no second mechanism; never build one by hand.
- A failed close keeps the batch: dev, its tags and the branches stay, nothing
  is pushed, and the close names the branch that broke the close. Land the fix
  as one more branch, then `rapid land`.
- `rapid land --failed-gates-only` is valid only after a close of this batch
  failed: it runs again only the gates that close failed. With no failed close
  on record it is refused; it does not combine with `--batch` or `--pr`.
- A branch that lands while a close is testing stops that close; the next
  `rapid land` tests the new final tree.
- `rapid land --halt` stops the close under test and keeps the batch.
- `rapid land --prune` puts dev back where the batch began and drops the batch;
  the branches stay as they were. Run it only when the owner tells you to.
- A branch behind dev is rebased by land itself. Exit 4 is a conflict: the
  branch is left as it was and the files are named; `rapid sync`, resolve, land
  again. Exit 3 from `rapid land --pr` is waiting for approvals: stop, report.
- Write the merge body with `-F`; see [lenses/merge.md](lenses/merge.md).

## 5. Receipts

- A landed merge says, in its trailers: `Branch-Base` (the dev commit it forked
  from), `Branch-Number`, `Requirement` (its `requirements/<slug>.md`), `Gates`,
  the tree the gates answer for, and `Proof` when the requirement names one.
- A batch land reads `Gates: deferred to the close of batch <id>` and names its
  tree as `Merge-Tree`: no gate ran on it at the land. A `--pr` land reads
  `Gates: fast=pass full=pass` and names its `Tested-Tree`.
- The gate log lives in `refs/notes/gates`: `git notes --ref=gates show
  <merge>` shows what ran on that merge, its exit code and its log tail. The
  close writes its record on the last merge of the batch. Never write a note
  there by hand.
- Before you say done: `rapid doctor --history` exits 0 and no batch is open.
  On dev, `rapid land --dry-run` answers `would close the batch open since ...`
  when one is, and `rapid status` shows origin/dev behind local dev.
- Report verbatim, never paraphrased: the result line of the close ("batch
  gates pass; ..." or the refusal) and the doctor line ("doctor: ok (history
  I1-I9 hold)" or each violation it printed).
- A number, a cause or an outcome in a message names the run that proved it.

## 6. Never

Each line names what stops it. "This rule" means nothing else does: it is on
you.

| Never | Stopped by |
|---|---|
| push to main | guard rule 3; pre-push (main moves only by a release merge) |
| merge into main | this rule; a local merge into main never reaches origin (pre-push) |
| run `rapid release` | guard rule 3; `rapid release` refuses an agent session |
| create, write or push a `release/<v>` tag | guard rule 3; pre-push |
| push, move or delete a version tag (`v<year>.<n>.<n>`), `--tags` | guard rule 5; pre-push |
| delete or rename dev, main or a branch | guard rule 9; pre-push for a deleting push |
| delete, move or hand-write a `safety/` or `vault/` ref | guard rule 8; pre-push |
| force-push without `--force-with-lease`, a `+refspec` | guard rule 3 |
| destructive git without the preflight the guard names | guard rule 2 |
| `git add -A`, `git add .`, `git add -u`, `git commit -a` | guard rule 5 |
| stage a secret, key, build output, `node_modules/`, `.env`, `*.zip`, `*.bak` | pre-commit, land and pre-push; guard rule 5 |
| write under `<git dir>/rapid` (the batch, its markers, the logs) | the guard's write rule |
| edit a vendored `.rapid` other than `conf` and `admins` | the guard's write rule |
| change `.rapid/conf` or `.rapid/admins` unless an admin asks | commit-msg, land, pre-push and I4: a `[MODE]` commit by an admin |
| commit or push with `--no-verify`, move `core.hooksPath` | guard rule 5 |
| commit on dev or main | commit-msg |
| push while a batch is open | pre-push |
| rewrite landed history, move dev back | pre-push (dev takes only merges rapid land made); this rule |
| land by a hand-made merge, tag or proof note | pre-push and `doctor --history`; this rule |
| amend, rebase or replay a commit you did not author | this rule |
| print a credential into the transcript | guard rule 4 |
| delete a file outside the temp roots (use the Trash) | guard rule 1 |

## 7. Sharing a branch

- `rapid sync` rebases the branch onto dev locally and never pushes.
- `rapid sync --push` then sends the branch to origin with a lease on the copy
  origin held, together with its safety anchor and its number.
- A plain `git push origin <branch>` also works; pre-push judges its commits
  and no gate runs on a branch push.
- Nothing is pushed while a batch is open: pre-push refuses it. Close the batch
  first with `rapid land`.
- Forge work (pull requests, CI runs, tokens): [lenses/forge.md](lenses/forge.md).

## 8. When something refuses

Every refusal names its reason and, most often, the command to run. Read it,
fix the cause, run the same command again. Never work around a refusal.

- A refused commit message: commit-msg lists each broken rule. Rewrite the
  message, or split the commit when the subject joins two concerns.
- A banned file in the index: unstage it, keep it out of the tree's history.
- Exit 4 from a land: `rapid sync`, resolve the named files, `git rebase
  --continue`, then land again. The branch as it was is kept at the preflight
  ref the message names.
- A failed close: section 4. The batch stays; the fix is one more branch.
- "a batch is open" from pre-push: `rapid land` publishes it.
- A policy change refused: it is a `[MODE]` commit by an admin listed in
  `.rapid/admins` on dev. Ask the admin; do not make it.
- `rapid sync --dev` stopped on a conflict: resolve, `git cherry-pick
  --continue`, `rapid sync --dev --continue`. Never a hand `rapid land` while a
  re-land is pending.
- A rewrite, a recovery or a history question:
  [lenses/history.md](lenses/history.md). Gates and checks:
  [lenses/verify.md](lenses/verify.md). A rebuild from old material:
  [lenses/rebuild.md](lenses/rebuild.md).
- When the cause is not yours to fix (a missing admin, a forge rule, a
  credential), stop and report the refusal verbatim.
