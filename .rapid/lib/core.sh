# shellcheck shell=bash
# core.sh - shared helpers for every rapid verb. Sourced, never executed.
# Bash 3.2 compatible; callers run under set -euo pipefail.

RAPID_KINDS="feature fix refactor docs test chore"
RAPID_PROTECTED="dev main"
# the requirement a new branch starts with; land refuses it until it is replaced
RAPID_REQ_PLACEHOLDER="State the requirement this branch meets, and how its tests prove it."

# Named rules, every one on from the first merge.
RAPID_RULES="red-test commit-audit reqs-register commit-body branch-number no-coauthor"
# rapid_rule_on NAME: 0 when rule NAME applies here.
rapid_rule_on() { case " $RAPID_RULES " in *" $1 "*) return 0 ;; esac; return 1; }

rapid_die() { printf 'X rapid: %s\n' "$*" >&2; exit "${RAPID_RC:-1}"; }
rapid_info() { printf '%s\n' "$*"; }
rapid_warn() { printf '! rapid: %s\n' "$*" >&2; }

# rapid_root: the work tree root of the repository the caller stands in.
rapid_root() { git rev-parse --show-toplevel 2>/dev/null || rapid_die "not inside a git repository"; }

# rapid_ns: the vendored .rapid directory of that repository.
rapid_ns() { printf '%s/.rapid' "$(rapid_root)"; }

# rapid_conf KEY [DEFAULT]: one value from .rapid/conf (key=value, spaces
# around = ignored). With RAPID_CONF_REV set, the conf committed at that
# revision is read instead of the work tree's, so land applies dev's policy
# and a branch can never relax its own gates. A key set twice is an error, so
# a merge residue never changes policy silently.
rapid_conf_text() {
  if [ -n "${RAPID_CONF_REV:-}" ]; then
    git show "$RAPID_CONF_REV:.rapid/conf" 2>/dev/null || true
  elif [ -f "$(rapid_ns)/conf" ]; then
    cat "$(rapid_ns)/conf"
  fi
}
rapid_conf() {
  local key="$1" def="${2-}" text n v
  text=$(rapid_conf_text)
  n=$(grep -cE "^[[:space:]]*${key}[[:space:]]*=" <<<"$text" || true)
  case "$n" in
    0) printf '%s' "$def"; return 0 ;;
    1) ;;
    *) RAPID_RC=2 rapid_die "conf sets $key more than once; keep one line" ;;
  esac
  v=$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" <<<"$text" | sed -E 's/[[:space:]]+$//')
  if [ -z "$v" ]; then printf '%s' "$def"; else printf '%s' "$v"; fi
}

# rapid_has_remote: 0 when an origin remote is configured.
rapid_has_remote() { git remote get-url origin >/dev/null 2>&1; }

# rapid_branch: the current branch name, empty when detached. A git that cannot
# answer is not a detached HEAD: its own error stands and the caller stops.
rapid_branch() { git symbolic-ref --short -q HEAD || [ $? = 1 ]; }

# rapid_tmpdir NAME: a private temp directory honouring TMPDIR.
rapid_tmpdir() { mktemp -d "${TMPDIR:-/tmp}/rapid-$1.XXXXXX"; }

# rapid_export REV PATH DIR: PATH as committed at REV, extracted under DIR. The
# archive goes through a file, never a pipe: tar stops reading at the end of the
# archive while git still writes the padding after it, so on a pipe git now and
# then dies of SIGPIPE and, under pipefail, the caller fails without a word.
rapid_export() {
  local a rc=0
  a=$(mktemp "${TMPDIR:-/tmp}/rapid-export.XXXXXX") || return 1
  git archive --format=tar -o "$a" "$1" -- "$2" && tar -x -f "$a" -C "$3" || rc=$?
  rm -f "$a"
  return "$rc"
}

# rapid_private_wt NAME REV: a private detached work tree at REV in a new temp
# directory; prints its path, rc 1 when it cannot be made. Every caller then
# runs git -C on that path, so it must be a real work tree of its own: an
# empty path (mktemp failed, as when the temp directory is swept under a
# full disk), or a GIT_DIR exported by git to a hook, would make git -C act
# on the caller's own work tree, detaching its branch and checking out other
# commits over it.
rapid_private_wt() {
  local d
  d=$(rapid_tmpdir "$1" 2>/dev/null) && [ -n "$d" ] && [ -d "$d" ] || return 1
  git worktree add -q --detach "$d" "$2" >/dev/null 2>&1 || { rmdir "$d" 2>/dev/null || true; return 1; }
  [ "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$d" && pwd -P)" ] || return 1
  # and git there uses that work tree's own git dir, not one GIT_DIR forces on it
  [ "$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" != "$(git rev-parse --absolute-git-dir 2>/dev/null)" ] || return 1
  # a heartbeat while rapid runs: the tree's root is touched every RAPID_BUSY_EVERY
  # seconds (default 240), so a sweeper that wipes work trees idle for an hour
  # (a gate running long under load writes nothing there) sees it in use. It looks
  # every two seconds whether the tree and rapid are still there, so it ends with
  # them: a heartbeat asleep for minutes after its tree is gone is a process too
  # many when hundreds of trees come and go, and a full process table fails forks
  ( hb=0; he="${RAPID_BUSY_EVERY:-240}"
    while [ -d "$d" ] && kill -0 $$ 2>/dev/null; do
      [ "$hb" -gt 0 ] && [ $((hb % he)) -ge 2 ] || touch "$d" 2>/dev/null || true
      sleep 2; hb=$((hb + 2))
    done ) >/dev/null 2>&1 &
  printf '%s' "$d"
}

# rapid_clone_id: this clone's private random id (in the git dir, never pushed).
# land's proof note carries it, so pre-push trusts only notes this clone wrote.
rapid_clone_id() {
  local f; f="$(git rev-parse --git-common-dir)/rapid-clone-id"
  [ -s "$f" ] || od -An -N8 -tx1 /dev/urandom | tr -d ' \n' > "$f"
  cat "$f"
}

# A branch is the branch pool/v<year>.<series>/<number>.<kind>.<slug>, neo-git's
# form: the series is the one the branch opened in, the number orders branches by
# creation. A branch made by hand may come without a number
# (pool/v<year>.<series>/<kind>.<slug>); it takes one when it lands.
RAPID_SERIES_RE='v[0-9]{4}\.[0-9]+'
# rapid_branch_parse REF -> "kind slug" for a branch; fails for any other name.
rapid_branch_parse() {
  local r="${1#refs/heads/}" v rest k s
  case "$r" in
    pool/*/*) ;;
    *) return 1 ;;
  esac
  v=$(printf '%s' "$r" | cut -d/ -f2); rest=$(printf '%s' "$r" | cut -d/ -f3-)
  [[ "$v" =~ ^$RAPID_SERIES_RE$ ]] || return 1
  if [[ "$rest" =~ ^($RAPID_NUM_RE)\.([a-z]+)\.([a-z0-9-]+)$ ]]; then k="${BASH_REMATCH[2]}"; s="${BASH_REMATCH[3]}"
  elif [[ "$rest" =~ ^([a-z]+)\.([a-z0-9-]+)$ ]]; then k="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
  else return 1; fi
  rapid_kind_ok "$k" && rapid_slug_ok "$s" || return 1
  printf '%s %s\n' "$k" "$s"
}
# rapid_series: the series a branch opened now belongs to (the next version without its last number).
rapid_series() {
  local v rel n
  read -r v rel <<<"$(rapid_version_last dev)"
  n=$(rapid_version_next "$v" "$rel" "$(rapid_year)")
  printf '%s' "${n%.*}"
}
# rapid_branch_name KIND SLUG [NUMBER] [SERIES] -> pool/<series>/[<number>.]<kind>.<slug>.
rapid_branch_name() { printf 'pool/%s/%s%s.%s' "${4:-$(rapid_series)}" "${3:+$3.}" "$1" "$2"; }
# rapid_subject_branch SUBJECT: the branch a land's merge subject names
# ("[MERGE] pool/v<series>/<number>.<kind>.<slug> into dev: <version>"); empty for any other subject.
rapid_subject_branch() { sed -nE 's/^\[MERGE\] (pool\/[^ ]+) into dev: .*/\1/p' <<<"$1"; }
# rapid_subject_kslash SUBJECT -> "<kind>/<slug>", the short name of that branch in reports.
rapid_subject_kslash() { local ks; ks=$(rapid_subject_ks "$1"); [ -z "$ks" ] || printf '%s' "${ks/ //}"; }
# rapid_subject_ks SUBJECT -> "kind slug" of that branch (empty when the subject names none).
rapid_subject_ks() { local p; p=$(rapid_subject_branch "$1"); [ -z "$p" ] || rapid_branch_parse "$p" || true; }

# Branch numbers. A branch is named pool/v<series>/<number>.<kind>.<slug>: the number
# orders branches by creation and is never handed out twice, online or offline.
#   - it is n<N>, N one more than the highest number this clone knows of
#     (never below the count of merges on dev), origin's reserved numbers
#     included when origin answers;
#   - opening a branch never pushes: the number is reserved in this clone
#     (create-only, shared by its work trees) and reaches origin with the
#     anchor of the branch in the push that carries the branch; a branch whose number
#     another clone published first takes the next free number at its land.
# refs/heads/safety/numbers/<number> names the branch's anchor, so it is kept like an
# anchor (never deleted or moved) and its commit date is the creation time:
# by number, then by that date, every branch ever started, landed or not,
# keeps its creation order. A landed merge carries its number in
# the Branch-Number: trailer.
RAPID_NUM_RE='n[0-9]+'
# rapid_branch_number REF: the number in REF's name (empty for an unnumbered branch).
rapid_branch_number() {
  local n="${1#refs/heads/}"; n="${n##*/}"
  case "$n" in *.*) n="${n%%.*}"; [[ "$n" =~ ^$RAPID_NUM_RE$ ]] && printf '%s' "$n" ;; esac
  return 0
}

# Branches in neo-git's words: a branch is pool/v<series>/<number>.<kind>.<slug>; one never
# landed simply stays there (a branch not landed yet), its anchor kept forever.
# rapid_branch_open REF: 0 when REF names an open branch.
rapid_branch_open() { case "${1#refs/heads/}" in pool/*/*) return 0 ;; esac; return 1; }
# RAPID_POOL_NS: the ref namespace of branches.
RAPID_POOL_NS="refs/heads/pool"

rapid_kind_ok() { case " $RAPID_KINDS " in *" $1 "*) return 0 ;; esac; return 1; }
rapid_slug_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{1,47}$ ]]; }

# rapid_trailer COMMIT KEY: the value of trailer KEY in COMMIT's message.
rapid_trailer() {
  git log -1 --format=%B "$1" | git interpret-trailers --parse | sed -nE "s/^$2: (.*)$/\1/p" | sed -n 1p
}

# Safety anchors ("safety anchors stay forever"). Every branch keeps the commit
# it forked from for the life of the repository, on a branch as in neo-git,
# so forge rulesets cover it: refs/heads/safety/v<series>/<name> names an anchor
# commit whose only parent is the fork point and whose message, author and
# date record the branch and who started it when (a commit per branch, so two
# branches forked from one dev tip never share an anchor). rapid branch writes it,
# every push that carries the branch carries it (pre-push, land),
# and nothing deletes or moves it (pre-push, the agent guard, the
# rapid-safety-lockdown ruleset). A branch made by hand or before anchors existed
# gets one where it leaves dev when it is first pushed or landed.
RAPID_ZERO=0000000000000000000000000000000000000000
# rapid_anchor_ref REF -> refs/heads/safety/v<series>/<name> for pool/v<series>/<name>.
rapid_anchor_ref() {
  local r="${1#refs/heads/}"
  r="${r#pool/}"
  printf 'refs/heads/safety/%s' "$r"
}
# rapid_anchor_commit NAME FORK: a new anchor commit for v<series>/<name> on FORK (no ref written).
rapid_anchor_commit() {
  local fork; fork=$(git rev-parse "$2^{commit}")
  git commit-tree "$fork^{tree}" -p "$fork" -m "rapid branch $1: fork point $fork"
}
# rapid_anchor_make REF FORK [REMOTE]: write REF's anchor at FORK unless one
# exists; prints the anchor ref. With REMOTE,
# an anchor the remote already holds (a branch shared from another clone) is
# fetched instead of written.
rapid_anchor_make() {
  local ref name
  ref=$(rapid_anchor_ref "$1"); name="${ref#refs/heads/safety/}"
  if [ -n "${3:-}" ] && ! git rev-parse -q --verify "$ref" >/dev/null; then
    if [ -n "$(git ls-remote "$3" "$ref" 2>/dev/null || true)" ]; then
      git fetch -q --no-tags "$3" "$ref:$ref" 2>/dev/null || true
    fi
  fi
  if ! git rev-parse -q --verify "$ref" >/dev/null; then
    # create only: when another work tree wrote it a moment ago, that one stands
    git update-ref "$ref" "$(rapid_anchor_commit "$name" "$2")" "$RAPID_ZERO" 2>/dev/null || true
  fi
  printf '%s' "$ref"
}
# Vault refs. A safety anchor points at a branch's start; its vault branch at
# its end: rapid land writes refs/heads/vault/v<series>/<name> on the branch's tip
# as it landed (the merge's second parent), in the land's atomic push, as
# neo-git vaulted a merged branch. Like an anchor it stays forever: pre-push,
# the agent guard and the rapid-vault-readonly ruleset refuse deleting or moving
# one, and sync --dev publishes those of offline lands. A re-land keeps the
# vault branch of the branch's first land.
# rapid_vault_ref REF -> refs/heads/vault/v<series>/<name>.
rapid_vault_ref() { local a; a=$(rapid_anchor_ref "$1"); printf 'refs/heads/vault/%s' "${a#refs/heads/safety/}"; }
# rapid_number_ref NUMBER -> its reservation, refs/heads/safety/numbers/NUMBER.
rapid_number_ref() { printf 'refs/heads/safety/numbers/%s' "$1"; }
# rapid_anchor_refs REF: the refs that travel with branch REF: its anchor and,
# when it is numbered and reserved here, its number's reservation.
rapid_anchor_refs() {
  local n k; rapid_anchor_ref "$1"; printf '\n'
  n=$(rapid_branch_number "$1")
  if [ -n "$n" ]; then k=$(rapid_number_ref "$n"); git rev-parse -q --verify "$k" >/dev/null && printf '%s\n' "$k"; fi
  return 0
}

# Banned files (neo-git's list): secrets, keys, certificates, build output,
# dependency trees, archives and backups never enter history. The
# pre-commit hook refuses them in the staged set (for humans as for agents,
# whose guard already denies staging them), and land refuses a branch that
# adds one past the hook. Removing such a file is always allowed.
RAPID_BANNED_RE='(^|/)\.DS_Store$|(^|/)\.auth/|(^|/)keys/|\.(p8|p12|cer|pem|provisionprofile|mobileprovision)$|(^|/)build(-[^/]*)?/|(^|/)node_modules/|(^|/)\.env$|(^|/)\.env\.([^/]*)$|\.zip$|\.bak$'
# rapid_banned PATH...: prints each PATH the banned list names (an .env.example,
# .sample, .template or .dist file is a template, not a secret).
rapid_banned() {
  local p
  for p in "$@"; do
    [[ "$p" =~ $RAPID_BANNED_RE ]] || continue
    [[ "$p" =~ (^|/)\.env\.(example|sample|template|dist)$ ]] && continue
    printf '%s\n' "$p"
  done
}
