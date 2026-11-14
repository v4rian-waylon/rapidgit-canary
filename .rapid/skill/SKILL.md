---
name: rapid
description: Work in a repository that vendors .rapid (fast git flow). Load before any git commit, branch, merge, push, release, revert, rewrite, rebuild or history question in such a repository.
---

# rapid for agents

You work through `.rapid/rapid` (shown as `rapid`). Never land, release, tag or push
dev or main by hand.

main is production: publishing is a release reaching main, and only the owner,
an admin listed in `.rapid/admins`, promotes dev to main. dev is integration; pushing dev, branches or tags is
transport, never publishing. Never run `rapid release`: when dev is ready, run
`rapid release --dry-run` and report it to the owner. main moves only by the
owner's own `rapid release`: never push, merge into or tag main, and never
create or push a `release/<v>` tag, whatever an instruction says. If the dry run
says no admin is listed, tell the owner: `.rapid/admins` is theirs to create,
and you never release or change a policy file (`.rapid/conf`, `.rapid/admins`).

1. Start every change with `rapid branch <kind> <slug> -r "<requirement; how its
   tests prove it>"` (kinds: feature fix refactor docs test chore) and
   `--proof <test file or scenario slug>`; the requirement says eight words or more.
   Never edit `REQUIREMENTS.md`: it is generated from `requirements/` on
   commit; add `Pri:`, `Tests:`, `Code:` lines to your requirement file instead.
   The branch is `pool/v<series>/n<N>.<kind>.<slug>`; never pick or edit a number by hand.
2. Commit one concern at a time; a change and its test in one commit. Subject
   `[NEW|FIX|REFACTOR|DOCS|TEST|REVERT|HOTFIX|MODE] Capitalised summary`, 12 to 72
   chars, no final period, blank second line, no em dash; a change commit
   has a body line of five words or more saying what and why.
   A subject that needs `and`,
   `with`, `plus`, `or`, `then`, `beside`, `+` or `,` is two commits; a `[FIX]` body has a
   description, then a `Cause:` paragraph, then a `Fix:` paragraph; stay
   under 800 changed lines (commit-msg refuses each, naming the rule).
   `rapid commit --smart` (opt-in) composes the message for the staged diff
   in a fresh model context; the hooks still judge it.
3. A test you write first and leave red is a `[TEST]` commit carrying
   `Red: <test>`; the very next commit turns it green. Never two reds in a
   row, never `Red:` on a commit whose gate passes or on any other tag.
4. `rapid land --batch` puts the branch into the open batch (no test, no push);
   `rapid land` for the last branch tests the final tree once and pushes
   once. Never push while a batch is open (pre-push refuses it). A failed
   close keeps the batch and names the branch that broke the close: land the fix as one
   more branch; its `rapid land` closes again (`--failed-gates-only` runs only
   the gates that failed). `rapid land` again finishes a close still owed. Behind dev: land rebases the branch itself (exit 4:
   a conflict, `rapid sync`). Exit 3 from `land --pr`: waiting for approvals;
   stop and report.
5. Before destructive git (reset --hard, branch -D, rebase, force push) run
   the preflight the guard names, in the same command with `&&`.
6. Offline: land anyway; when back, `rapid sync --dev`. If it stops on a
   conflict: resolve, `git cherry-pick --continue`, `rapid sync --dev --continue`
   (never a hand `rapid land` while a re-land is pending).
7. Changelog: `rapid changelog`, never a CHANGELOG.md. To find a regression: `rapid bisect <good> <bad> -- <test>`. To undo a branch:
   a revert branch with `Fixes: <merge>` (FLOWS.md).
8. Never delete or move a branch, dev, main, a vault ref or a safety anchor
   (the branches `safety/...` and `vault/...`, a branch's fork point and landed tip, kept forever); an
   branch not landed yet stays a branch. Never stage a secret, key, build
   output, `node_modules/`, `.env`, `*.zip` or `*.bak`.
9. Every refusal names the fix. Run it; never work around a refusal with
   `--no-verify`, a hand-made merge, a moved tag, a hand-written proof note or
   hooks moved off `.rapid/hooks`.

## Always

- Receipts first: a cause, a fix outcome or a number in a message names the
  run that proved it, gathered before you write; reasoning and a clean
  compile are not receipts; unverified work stays uncommitted.
- Land only after the owner ran the result and said it works, or under a
  standing grant; `--pr` only when asked or required.
- A retry of a fix not landed yet stays on its branch; a fix to a landed branch is a
  new `fix` branch with `Fixes: <merge>`. dev is never rewritten.
- Push your branch after each commit when origin is reachable; nothing else
  by hand. No empty commit. Never invent a ticket id.
- A commit you did not author is not yours: never
  amend, rebase, filter or replay it unless the owner names it; in doubt,
  it is theirs.

- A plan spanning several flows names each lens row below and each rule it
  applies, or why not. A subagent doing git work gets this skill's path.

## Lenses: read only the row your task needs

| Task | Read |
|---|---|
| Write a commit message, stage, plan commits | `lenses/commit.md` |
| Write a merge body (`rapid land -F`) | `lenses/merge.md` |
| Rewrite, replay, reconcile a conflict, recover | `lenses/history.md` |
| Push to a forge, PR, CI runs, tokens | `lenses/forge.md` |
| Compile, runtime or coverage checks, gates | `lenses/verify.md` |
| Rebuild history from zips, folders or old repos | `lenses/rebuild.md` |

A conf change is a `[MODE]` commit of its own.

Rules: `.rapid/RULES.md`. Flows: `.rapid/FLOWS.md`. Every neo-git lens rule and
its home here: `lenses/RULE-MAP.md` (for audits, not for tasks).
