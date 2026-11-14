# shellcheck shell=bash
# policy.sh - who may land, how big a branch may be, which gates run.
#
# conf keys (all optional):
#   land_who=anyone|list     who may land a branch (default anyone)
#   land_list=a@x,b@x        allowed lander emails when land_who=list
#   max_commits=N            most commits one branch may carry (default 20)
#   commit_body=required|optional  required: a NEW, FIX, REFACTOR, REVERT or HOTFIX commit carries a body
#                            line of five words or more (default required)
#   requirement_proof=required|optional  required: a branch's requirement states eight words or more and a
#                            Proof: <path or scenario slug> line naming what proves it in the branch tip (default required)
#   docs_rules=c=d,c2=d2     pairs <code glob>=<doc glob>: a branch changing code matching c changes a doc matching
#                            d, or its requirement says Docs: none (<reason>); the merge records which (default unset)
#   signed=required|optional required: every branch commit, merge, version tag and release tag is signed and verifies (%G? is
#                            G or U); the only answer to one person committing under another's address (default optional)
#   land_pr=optional|required  required: a land goes through review (rapid land --pr)
#   land_approvals=N         approving reviews land --pr waits for (default 1)
#   agent_env=VAR,VAR2       environment variables that mark an AI agent session besides CLAUDECODE,
#                            CLAUDE_CODE_ENTRYPOINT and CODEX_* (rapid_agent_session): such a session never
#                            releases (default unset)
#   smart_commit_cmd=<cmd>   rapid commit --smart: the command that reads the prompt on stdin and prints the
#                            message (default: the claude CLI in print mode, fresh context, read-only tools)
#   forge_repo=OWNER/REPO    the forge repository when origin's URL does not name it
#   tracker=none             the committed conf may only say none (lib/tracker.sh)
#   reqs_id=TOKEN            the project token of REQUIREMENTS.md IDs, <TOKEN>-R-<slug> (default REQ; lib/reqs.sh)
#   release_who=owner|list   who may promote dev to main (default owner: the admins listed in .rapid/admins)
#   release_list=a@x,b@x     allowed releaser emails when release_who=list
#   gates_commit=<command>   run by the pre-commit hook on the staged tree of every branch commit (default none)
#   max_commit_lines=N       most lines one branch commit may change, added plus deleted (default 800; lib/audit.sh)
#   test_paths=<patterns>    shell patterns of test paths, space separated (default lib/audit.sh's list); a
#                            [NEW], [FIX] or [HOTFIX] commit that changes behaviour touches one of them
#   gates_fast=<command>     run on every branch commit by check --each
#   gates_full=<command>     run by rapid land on the batch's final tree (and on a land --pr merge tree)
#   gates_each=<command>     run by rapid land on the own tree of every merge of the batch, all at once,
#                            before the one gate on the final tree: a cheap proof that each merge starts
#                            (default none)
#   gates_release=<command>  run on dev before a release
#   test_on_fail=<command>   started in the background the moment a scenario fails during any gate run
#                            (args: scenario name, its output file): a fixer starts on that issue at once
#   land_on_conflict=<command> started in the background when rapid land meets a conflict rebasing a branch
#                            (args: branch, the file listing the conflicting paths); land exits 4
#   release_build=<command>  builds the release artifacts on the released tree into $RAPID_ARTIFACTS, each
#                            named with $RAPID_LABEL (<version>-<sha>); BUILD_TYPE=release (default none)
#   gates_artifact=<command> run on those artifacts ($RAPID_ARTIFACTS) after rapid's no-debug audit (default none)
#   release_publish=<command> ships the gated artifacts ($RAPID_ARTIFACTS, $RAPID_VERSION) after the release push
# A gate is one shell command run from the tree's root; exit 0 passes.
# An empty gate passes and is reported as "none"; so does the explicit value
# "none", which land requires for gates_full instead of an unset key.

# the defaults, named once: lint/docs.sh checks RULES' policy table against them
RAPID_MAX_COMMITS_DEFAULT=20

rapid_policy_may_land() {
  local who email list
  who=$(rapid_conf land_who anyone)
  email=$(git var GIT_AUTHOR_IDENT 2>/dev/null | sed -E 's/.*<([^>]*)>.*/\1/')
  case "$who" in
    anyone) return 0 ;;
    list)
      list=$(rapid_conf land_list "")
      if [ -n "$email" ] && tr ',' '\n' <<<"$list" | grep -Fx -- "$email" >/dev/null; then return 0; fi
      echo "'${email:-<no identity>}' is not in land_list (land_who=list)"; return 1 ;;
    *) echo "land_who='$who' is not anyone or list"; return 1 ;;
  esac
}

# rapid_policy_may_release MAIN DEV EMAIL...: 0 when every EMAIL may promote
# dev to main, else prints why. main is production: release_who,
# release_list and the admins (.rapid/admins, the owner's file) are read as
# committed at MAIN (main's tip, or for a push the main it moves from), so a
# branch landed on dev never grants itself the right. While MAIN lists no admin
# (a repository not yet released under this rule) the admins at DEV rule; rapid
# setup writes its human runner, or the one --owner names, as the first admin
# in the root commit, so a new repository starts with one.
rapid_policy_may_release() {
  local main="$1" dev="$2" who list e
  shift 2
  who=$(RAPID_CONF_REV="$main" rapid_conf release_who owner)
  case "$who" in
    owner)
      list=$(RAPID_CONF_REV="$main" rapid_admins | tr '\n' ',')
      [ -n "$list" ] || list=$(RAPID_CONF_REV="$dev" rapid_admins | tr '\n' ',')
      if [ -z "$list" ]; then
        echo "main is production and no admin is listed in .rapid/admins; the first [MODE] commit creates .rapid/admins with the owner's email"; return 1
      fi ;;
    list)
      list=$(RAPID_CONF_REV="$main" rapid_conf release_list "")
      if [ -z "$list" ]; then echo "main is production and release_list is empty at main (release_who=list); an admin sets it"; return 1; fi ;;
    *) echo "release_who='$who' is not owner or list"; return 1 ;;
  esac
  list="${list%,}"
  for e in "$@"; do
    if [ -z "$e" ] || ! tr ',' '\n' <<<"$list" | grep -Fx -- "$e" >/dev/null; then
      echo "main is production; only $list promotes dev to main ('${e:-<no identity>}' may not)"; return 1
    fi
  done
  return 0
}

# rapid_agent_session: prints the variable that marks this process as an AI
# agent session and returns 0, or returns 1. Claude Code sets CLAUDECODE and
# CLAUDE_CODE_ENTRYPOINT, Codex CLI its CODEX_* variables (CODEX_HOME is a
# human's config path, not a session); conf agent_env names more (variable
# names, comma or space separated). An agent session is an agent whether or
# not the agent guard is installed: it never releases.
rapid_agent_session() {
  local v
  for v in CLAUDECODE CLAUDE_CODE_ENTRYPOINT; do
    [ -z "${!v:-}" ] || { echo "$v"; return 0; }
  done
  for v in $(compgen -e); do
    case "$v" in CODEX_HOME) ;; CODEX_*) [ -z "${!v:-}" ] || { echo "$v"; return 0; } ;; esac
  done
  for v in $(rapid_conf agent_env "" | tr ',' ' '); do
    [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [ -z "${!v:-}" ] || { echo "$v"; return 0; }
  done
  return 1
}

rapid_policy_max_commits() {
  local m; m=$(rapid_conf max_commits "$RAPID_MAX_COMMITS_DEFAULT")
  [[ "$m" =~ ^[0-9]{1,4}$ ]] && [ "$m" -ge 1 ] || RAPID_RC=2 rapid_die "max_commits='$m' must be 1 to 9999"
  printf '%s' "$m"
}

# rapid_gate_missing [DIR]: one line per gate whose command names a .rapid/tests
# or .rapid/lint script DIR (default the work tree root) does not have, as a
# fresh vendor that dropped the framework's own tests would.
rapid_gate_missing() {
  local dir="${1:-.}" g cmd p
  for g in fast full release; do
    cmd=$(rapid_conf "gates_$g" "")
    for p in $(grep -oE '\.rapid/(tests|lint)/[A-Za-z0-9._/-]+' <<<"$cmd" || true); do
      [ -e "$dir/$p" ] || echo "gates_$g runs $p, which this repository does not have"
    done
  done
}

# rapid_path_in GLOBS PATH: 0 when PATH matches one of the comma-separated GLOBS.
rapid_path_in() {
  local g gs
  # split on commas only: a glob is never expanded against the work tree
  IFS=, read -r -a gs <<<"$1"
  for g in ${gs[@]+"${gs[@]}"}; do
    g="${g#"${g%%[![:space:]]*}"}"; g="${g%"${g##*[![:space:]]}"}"
    [ -n "$g" ] || continue
    # shellcheck disable=SC2053
    [[ "$2" == $g ]] && return 0
  done
  return 1
}

# rapid_signed_problem COMMIT: empty when signed=required is off or COMMIT
# carries a signature git verifies (G, or U: good, trust unknown), else why.
rapid_signed_problem() {
  [ "$(rapid_conf signed optional)" = required ] || return 0
  case "$(git log -1 --format=%G? "$1" 2>/dev/null)" in
    G|U) return 0 ;;
    *) echo "$(git rev-parse --short "$1") is not signed with a key git verifies (signed=required): sign it (git commit -S, commit.gpgsign=true) and make the key verifiable (gpg, or gpg.ssh.allowedSignersFile)" ;;
  esac
}

# rapid_release_signed GOV TIP: 0 when signed=required at GOV (the main a release
# moves from) or at TIP (the released commit): the release tag must be signed.
rapid_release_signed() {
  [ "$(RAPID_CONF_REV="$1" rapid_conf signed optional)" = required ] || [ "$(RAPID_CONF_REV="$2" rapid_conf signed optional)" = required ]
}

# rapid_release_sig_problem TAGREF GOV TIP: empty unless signed=required (at GOV
# or TIP) and the release tag carries no good signature, or its signer may not
# release by the policy at GOV. The signer is the verified principal (ssh) or
# the GOODSIG email (gpg). The keys come from .rapid/signers committed at GOV
# (git's allowed signers format, "<email> <keytype> <key>") when it exists:
# main moves only by a release, so only the owner changes them; without it
# git's own config verifies, which the releaser's machine controls.
rapid_release_sig_problem() {
  local t="$1" gov="$2" tip="$3" af="" raw signer why c=()
  rapid_release_signed "$gov" "$tip" || return 0
  if git cat-file -e "$gov:.rapid/signers" 2>/dev/null; then
    af=$(mktemp "${TMPDIR:-/tmp}/rapid-signers.XXXXXX"); git show "$gov:.rapid/signers" > "$af"
    c=(-c "gpg.ssh.allowedSignersFile=$af")
  fi
  raw=$(git ${c[@]+"${c[@]}"} verify-tag --raw "$t" 2>&1) || raw=""
  [ -z "$af" ] || rm -f "$af"
  signer=$(sed -nE 's/^Good "git" signature for ([^ ]+) with .*/\1/p; s/^\[GNUPG:\] GOODSIG [^ ]+ .*<([^>]+)>.*/\1/p' <<<"$raw" | sed -n 1p)
  if [ -z "$signer" ]; then
    echo "${t#refs/tags/} carries no signature git verifies$([ -z "$af" ] || echo " against .rapid/signers at main") (signed=required): the owner signs it, as rapid release does under signed=required"
    return 0
  fi
  why=$(rapid_policy_may_release "$gov" "$tip" "$signer") || echo "${t#refs/tags/} is signed by '$signer': $why"
}

# rapid_docs_named BASE TIP REQFILE: with docs_rules set, a branch that changes
# code matching a rule's code glob changes a doc matching its doc glob, or
# its requirement says "Docs: none (<reason>)". Prints the merge trailer
# ("Docs: <doc>, ..." or "Docs: none (<reason>)"), or on rc 1 the reason.
rapid_docs_named() {
  local rules files r code doc hit need="" got="" why p rs
  rules=$(rapid_conf docs_rules "")
  [ -n "$rules" ] || return 0
  files=$(git diff --name-only --no-renames "$1" "$2" || true)
  IFS=, read -r -a rs <<<"$rules"
  for r in ${rs[@]+"${rs[@]}"}; do
    code="${r%%=*}"; doc="${r#*=}"; [ -n "$code" ] && [ -n "$doc" ] && [ "$code" != "$r" ] || continue
    hit=""; while IFS= read -r p; do [ -n "$p" ] && rapid_path_in "$code" "$p" && hit=1; done <<<"$files"
    [ -n "$hit" ] || continue
    hit=""; while IFS= read -r p; do [ -n "$p" ] && rapid_path_in "$doc" "$p" && { hit="$p"; break; }; done <<<"$files"
    if [ -n "$hit" ]; then got="$got, $hit"; else need="$need $code=$doc"; fi
  done
  if [ -n "$need" ]; then
    why=$(sed -nE 's/^Docs: none \((.+)\)$/\1/p' "$3" | sed -n 1p)
    [ -n "$why" ] && { echo "Docs: none ($why)"; return 0; }
    echo "the branch changes code its docs describe and no doc:$need; change the doc, or say 'Docs: none (<reason>)' in the requirement"; return 1
  fi
  [ -z "$got" ] || echo "Docs: ${got#, }"
}

# rapid_gate NAME DIR: run gates_NAME in DIR; prints pass|fail|none, rc 0 unless fail.
# With RAPID_GATE_REC set (a file path), the run, green or red, is recorded
# there: its command, exit code, duration and log tail (rapid land's gate log).
rapid_gate() {
  local name="$1" dir="$2" cmd rc=0 log t0
  cmd=$(rapid_conf "gates_$name" "")
  if [ -z "$cmd" ] || [ "$cmd" = none ]; then echo none; return 0; fi
  log=$(mktemp "${TMPDIR:-/tmp}/rapid-gate-$name.XXXXXX"); t0=$(date +%s)
  # The gate is the project's own command: it runs without rapid's internal
  # state (RAPID_CONF_REV names a revision of this repository, which a test
  # suite driving other repositories must not inherit).
  local tof; tof=$(rapid_conf test_on_fail "" 2>/dev/null || true)
  ( cd "$dir" && unset RAPID_CONF_REV RAPID_OFFLINE RAPID_RELAND_STEP RAPID_GATE_REC RAPID_JUDGED GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && export RAPID_TEST_ON_FAIL="${RAPID_TEST_ON_FAIL:-$tof}" && sh -c "$cmd" ) >"$log" 2>&1 || rc=$?
  if [ -n "${RAPID_GATE_REC:-}" ]; then
    {
      printf 'gate=%s\ncommand=%s\nexit=%s\nduration=%ss\nat=%s\n' \
        "$name" "$cmd" "$rc" "$(( $(date +%s) - t0 ))" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf -- '--- log tail\n'
      tail -n 25 "$log" 2>/dev/null || true
    } > "$RAPID_GATE_REC"
  fi
  if [ "$rc" = 0 ]; then rm -f "$log"; echo pass; return 0; fi
  # the end of the log: a test runner prints its failures and counts last
  tail -n 25 "$log" | sed 's/^/    | /' >&2; rm -f "$log"
  echo fail; return 1
}

# rapid_check_each BASE TIP: the fast gate on every commit of BASE..TIP, in order.
# A failing commit passes only with a Red: trailer and a later green commit:
# the commit right after it must pass and carry no Red: (no chain of reds),
# and a Red: commit whose gate passes is a stale marker, refused. Shared by
# rapid check --each and rapid land (a branch push runs no gate: transport).
rapid_check_each() {
  local base="$1" tip="$2" wt c r subj red last fails=0 prev_red=0
  last=$(git rev-parse "$tip")
  if [ -z "$(rapid_conf gates_fast "")" ]; then rapid_info "check --each: no fast gate configured"; return 0; fi
  wt=$(rapid_private_wt each "$base") || { rapid_info "  FAIL  cannot make a private work tree under ${TMPDIR:-/tmp}"; return 1; }
  for c in $(git rev-list --reverse "$base..$tip"); do
    git -C "$wt" checkout -q --detach "$c"
    subj=$(git log -1 --format=%s "$c"); red=$(rapid_trailer "$c" Red)
    if r=$(rapid_gate fast "$wt" 2>/dev/null); then
      if [ -n "$red" ]; then
        rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: stale Red: marker, the fast gate passes (Red: $red)"; fails=1
      else
        rapid_info "  pass  $(git rev-parse --short "$c") $subj"
      fi
      prev_red=0
    elif [ -n "$red" ] && [ "$prev_red" = 1 ]; then
      rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: a Red: commit follows a Red: commit; the commit after a red one turns it green"; fails=1
    elif [ -n "$red" ] && [ "$c" != "$last" ]; then
      rapid_info "  red   $(git rev-parse --short "$c") $subj (marked: Red: $red)"; prev_red=1
    elif [ -n "$red" ]; then
      rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: a Red: commit cannot be the branch tip"; fails=1
    else
      rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: fast gate fails and no Red: trailer marks it"; fails=1
    fi
  done
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  return "$fails"
}


# Policy flips. .rapid/conf (every key above) and .rapid/admins (the admins, one
# email per line, # comments allowed: the owner and whoever the owner adds) are
# the policy files. A commit that changes one is a policy flip: its own [MODE]
# commit, changing only policy files (and the requirement file of the branch,
# which the first commit of a branch carries, with the REQUIREMENTS.md register
# generated from it), authored and committed by an admin. Admins are read from
# .rapid/admins as committed at RAPID_CONF_REV (the tip of dev at commit and at
# land; the first parent of each merge in history), so a branch never makes
# itself an admin. rapid setup writes its human runner, or the one --owner
# names, as the first admin in the root commit. With no admin at that revision
# (a repository an agent set up without --owner), the one flip allowed is the
# [MODE] commit that creates .rapid/admins.
RAPID_POLICY_FILES=".rapid/conf .rapid/admins"

# rapid_admins: the admin emails at RAPID_CONF_REV (or in the work tree), one per line.
rapid_admins() {
  local text=""
  if [ -n "${RAPID_CONF_REV:-}" ]; then
    text=$(git show "$RAPID_CONF_REV:.rapid/admins" 2>/dev/null || true)
  elif [ -f "$(rapid_ns)/admins" ]; then
    text=$(cat "$(rapid_ns)/admins")
  fi
  grep -vE '^[[:space:]]*(#|$)' <<<"$text" | awk '{ print $1 }' || true
}

# rapid_policy_flip_problem SUBJECT FILES AE AN CE: empty when a commit with
# SUBJECT changing FILES (whitespace separated), authored by AE (name AN) and
# committed by CE, keeps the policy-flip rule at RAPID_CONF_REV; else one
# reason per line.
rapid_policy_flip_problem() {
  local subj="$1" files="$2" ae="$3" an="$4" ce="$5" f pol=0 other=0 admins who names boot=0
  names=$(sed 's/ /, /g' <<<"$RAPID_POLICY_FILES")
  for f in $files; do
    case " $RAPID_POLICY_FILES " in
      *" $f "*) pol=1 ;;
      *) case "$f" in requirements/*.md|REQUIREMENTS.md) ;; *) other=1 ;; esac ;;   # the requirement of the branch (and the register made from it) rides along
    esac
  done
  if [[ "$subj" == "[MODE] "* ]]; then
    [ "$pol" = 1 ] || { echo "a [MODE] commit is a policy flip: it changes a policy file ($names), and this one changes none"; return 0; }
    [ "$other" = 0 ] || echo "a [MODE] commit changes only policy files ($names) and the requirement of its branch; commit the other files apart"
  elif [ "$pol" = 1 ]; then
    echo "a change to a policy file ($names) is a policy flip: give it its own [MODE] commit"
  else
    return 0
  fi
  admins=$(rapid_admins)
  if [ -z "$admins" ]; then
    # no admin yet: the one flip allowed creates the admins file, and only that
    [ "$(grep -vxE 'requirements/.*\.md|REQUIREMENTS\.md' <<<"$(tr ' ' '\n' <<<"$files")" | sed '/^$/d')" = .rapid/admins ] \
      && [ -z "$(git show "${RAPID_CONF_REV:-HEAD}:.rapid/admins" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || true)" ] && boot=1
    if [ "$boot" = 0 ]; then
      echo "no admin is listed in .rapid/admins on dev; the first [MODE] commit creates .rapid/admins with the owner's email"; return 0
    fi
  fi
  [ "$boot" = 0 ] || return 0
  for who in "$ae" "$ce"; do
    grep -Fx -- "$who" <<<"$admins" >/dev/null \
      || { echo "'${who:-<no identity>}' is not an admin (.rapid/admins on dev: $(tr '\n' ' ' <<<"$admins" | sed 's/ $//')); an admin flips policy"; return 0; }
  done
  return 0
}

# rapid_policy_flip_commit C: rapid_policy_flip_problem for commit C (its subject,
# the files it changes against its parent, its author and committer).
rapid_policy_flip_commit() {
  local who ae an ce
  who=$(git log -1 --format='%ae%x09%an%x09%ce' "$1"); IFS=$'\t' read -r ae an ce <<<"$who"
  rapid_policy_flip_problem "$(git log -1 --format=%s "$1")" "$(git diff-tree --no-commit-id --name-only -r "$1")" "$ae" "$an" "$ce"
}
