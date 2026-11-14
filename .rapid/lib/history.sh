# shellcheck shell=bash
# history.sh - the history invariants I1 to I9, checked by doctor --history
# and, per landed merge, by pre-push. Each check prints "<Id> <sha> <why>"
# for every violation; empty output means the history holds.
#
#   I1 every first-parent commit on dev after the root is a two-parent merge
#      whose second-parent range is linear
#   I2 every such merge carries exactly one version tag, the next version
#      after the previous one (version.sh)
#   I3 the merge subject is "[MERGE] pool/v<series>/<number>.<kind>.<slug> into dev: <version>" and
#      its trailers Branch-Base, Gates, Tested-Tree and Requirement are present,
#      Tested-Tree equal to the merge's tree, Branch-Base equal to its first parent;
#      and Branch-Number, a branch number (core.sh)
#   I4 the branch holds 1 to max_commits commits, each with a ruled subject,
#      no commit-audit smell (lib/audit.sh) and at most one
#      Red: trailer, on a [TEST] commit that neither ends the branch nor follows
#      another Red: commit, and each change commit with a body line (commit_body)
#      another Red: commit; a commit changing .rapid/conf or .rapid/admins is a
#      [MODE] commit of those files only, by an admin of the first parent
#   I5 main holds nothing dev lacks: its first-parent line is release merges
#      "[MERGE] dev into main: <version>" (rapid release, --no-ff), each with a
#      released dev commit as second parent and that commit's tree, down to
#      the root or a release made before release merges (main then a dev
#      commit carrying release/<version>); every release/<version> made under
#      the owner rule is an annotated tag whose tagger the admins at the
#      previous release (or the root) list
#   I6 every v* and release/* tag sits on dev's first-parent line
#   I7 branch slugs are unique across landed merges and branches not landed yet,
#      and so are branch numbers: one number never names two branches
#   I8 requirements/<slug>.md exists at every merge of that branch and at dev's tip,
#      and REQUIREMENTS.md at each merge is the register its requirement files
#      generate (lib/reqs.sh; merges made under rule reqs-register)
#   I9 every replaced merge is re-landed on dev or kept as a branch not landed yet, and
#      no re-land is left half done

# rapid_check_merge M PREV_VERSION PREV_RELEASED: I1-I4 and I8 for one merge;
# prints violations, and on success prints "OK <version>" as its last line.
rapid_check_merge() {
  local m="$1" prev="$2" released="$3" n p1 p2 v vs subj slug want tt tree base req c reds f pb
  n=$(git rev-list --parents -n1 "$m" | wc -w | tr -d ' ')
  if [ "$n" != 3 ]; then echo "I1 $m is not a two-parent merge"; return 0; fi
  p1=$(git rev-parse "$m^1"); p2=$(git rev-parse "$m^2")
  if [ -n "$(git rev-list --merges "$p1..$p2")" ]; then echo "I1 $m branch range holds a merge commit"; fi
  vs=$(git tag --points-at "$m" -l 'v*' | grep -cE '^v[0-9]{4}\.[0-9]+\.[0-9]+$' || true)
  v=$(rapid_version_of "$m")
  if [ "$vs" != 1 ]; then echo "I2 $m carries $vs version tags (want 1)"; fi
  subj=$(git log -1 --format=%s "$m")
  f=$(mktemp "${TMPDIR:-/tmp}/rapid-msg.XXXXXX"); git log -1 --format=%B "$m" >"$f"
  while IFS= read -r line; do [ -n "$line" ] && echo "I3 $m $line"; done <<<"$(rapid_msg_violations "$f" merge)"
  rm -f "$f"
  if [ -n "$v" ]; then
    want=$(rapid_version_next "$prev" "$released" "${v:1:4}")
    [ "$v" = "$want" ] || echo "I2 $m is $v, expected $want after ${prev:-<none>}"
    case "$subj" in *": $v") ;; *) echo "I3 $m subject does not name its tag $v" ;; esac
  fi
  slug=$(sed -nE 's/^\[MERGE\] pool\/[^ ]*[.]([a-z0-9-]+) into dev: .*/\1/p' <<<"$subj")
  local trs; trs=$(git log -1 --format=%B "$m" | git interpret-trailers --parse)
  base=$(sed -nE 's/^Branch-Base: (.*)$/\1/p' <<<"$trs" | sed -n 1p); tt=$(sed -nE 's/^(Tested|Merge)-Tree: (.*)$/\2/p' <<<"$trs" | sed -n 1p)
  req=$(sed -nE 's/^Requirement: (.*)$/\1/p' <<<"$trs" | sed -n 1p)
  grep -q '^Gates: ' <<<"$trs" || echo "I3 $m has no Gates: trailer"
  tree=$(git rev-parse "$m^{tree}")
  [ "$tt" = "$tree" ] || echo "I3 $m Tested-Tree or Merge-Tree ${tt:-<missing>} is not its tree $tree"
  # a receipt never claims a test of a tree no gate ran on: deferred gates go with Merge-Tree
  if grep -q '^Gates: deferred to the close of batch [0-9a-f]\{7,40\}$' <<<"$trs"; then
    grep -q '^Merge-Tree: ' <<<"$trs" || echo "I3 $m defers its gates to a batch close, so it names its tree as Merge-Tree, never Tested-Tree"
  elif grep -q '^Gates: deferred' <<<"$trs"; then
    echo "I3 $m Gates: receipt is not 'deferred to the close of batch <id>'"
  else
    grep -q '^Tested-Tree: ' <<<"$trs" || echo "I3 $m names no Tested-Tree for the gates its receipt lists"
  fi
  [ -n "$base" ] && [ "$(git rev-parse -q --verify "$base^{commit}" 2>/dev/null)" = "$p1" ] \
    || echo "I3 $m Branch-Base ${base:-<missing>} is not its first parent"
  [ "$req" = "requirements/$slug.md" ] || echo "I3 $m Requirement ${req:-<missing>} is not requirements/$slug.md"
  [ -n "$slug" ] && git cat-file -e "$m:requirements/$slug.md" 2>/dev/null \
    || echo "I8 $m has no requirements/${slug:-?}.md"
  # the register at the merge is the one its requirement files generate (rule reqs-register)
  if rapid_rule_on reqs-register; then
    local rd; rd=$(rapid_reqs_drift "$m"); [ -z "$rd" ] || echo "I8 $m $rd"
  fi
  n=$(git rev-list --count "$p1..$p2")
  local max; max=$(RAPID_CONF_REV="$p1" rapid_policy_max_commits)
  if [ "$n" -lt 1 ] || [ "$n" -gt "$max" ]; then echo "I4 $m branch holds $n commits (1 to $max)"; fi
  local prevred=0 red ln
  if rapid_rule_on branch-number; then
    ln=$(sed -nE 's/^Branch-Number: (.*)$/\1/p' <<<"$trs" | sed -n 1p)
    [[ "$ln" =~ ^$RAPID_NUM_RE$ ]] || echo "I3 $m Branch-Number ${ln:-<missing>} is not a branch number (n<N>)"
  fi
  f=$(mktemp "${TMPDIR:-/tmp}/rapid-msg.XXXXXX")
  for c in $(git rev-list --reverse "$p1..$p2"); do
    git log -1 --format=%B "$c" >"$f"
    while IFS= read -r line; do [ -n "$line" ] && echo "I4 $c $line"; done <<<"$(RAPID_CONF_REV="$p1" rapid_msg_violations "$f")"
    while IFS= read -r line; do [ -n "$line" ] && echo "I4 $c $line"; done <<<"$(RAPID_CONF_REV="$p1" rapid_commit_smells "$c")"
    pb=$(RAPID_CONF_REV="$p1" rapid_policy_flip_commit "$c")
    while IFS= read -r line; do [ -n "$line" ] && echo "I4 $c $line"; done <<<"$pb"
    if rapid_rule_on red-test; then
      red=$(grep -cE '^Red: .+' "$f" || true)
      if [ "${red:-0}" -ge 1 ]; then
        [ "$prevred" = 0 ] || echo "I4 $c a Red: commit follows a Red: commit"
        [ "$c" != "$p2" ] || echo "I4 $c a Red: commit is the branch tip"
        prevred=1
      else
        prevred=0
      fi
    fi
  done
  rm -f "$f"
  # signed=required at the first parent: the branch commits and the merge verify
  if [ "$(RAPID_CONF_REV="$p1" rapid_conf signed optional)" = required ]; then
    for c in $(git rev-list "$p1..$p2") "$m"; do
      pb=$(RAPID_CONF_REV="$p1" rapid_signed_problem "$c"); [ -z "$pb" ] || echo "I4 $c $pb"
    done
  fi
  [ -n "$v" ] && echo "OK $v"
  return 0
}

# rapid_jobs: how many merge checks run at once: one per core
# (RAPID_HISTORY_JOBS, a positive number, overrides it).
rapid_jobs() {
  local j="${RAPID_HISTORY_JOBS:-}"
  [[ "$j" =~ ^[1-9][0-9]*$ ]] || j=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  printf '%s' "$j"
}

# rapid_check_merges_par DIR: stdin holds one "<merge> <previous version or -> <released 0|1>"
# line per merge; rapid_check_merge runs on each with rapid_jobs workers at once
# (worker w takes lines w, w+N, ...), and the output for line i (from 1) goes to
# DIR/i, so the caller prints the results in order whatever order they finish in.
rapid_check_merges_par() {
  local dir="$1" list n w
  list=$(sed '/^$/d'); [ -n "$list" ] || return 0
  n=$(rapid_jobs)
  for ((w = 0; w < n; w++)); do
    (
      i=0
      while read -r m p r; do
        i=$((i + 1))
        [ $(( (i - 1) % n )) = "$w" ] || continue
        [ "$p" != - ] || p=""
        rapid_check_merge "$m" "$p" "$r" > "$dir/$i"
      done <<<"$list"
    ) &
  done
  wait
}

# rapid_release_point C DEVFP: the dev commit main's commit C released: C
# itself when it is on dev's first-parent line (DEVFP, one sha per line),
# else, for a release merge, its second parent.
rapid_release_point() {
  if grep -Fx -- "$1" <<<"$2" >/dev/null; then printf '%s' "$1"; else git rev-parse "$1^2" 2>/dev/null || printf '%s' "$1"; fi
}

# rapid_main_check MAIN DEV [FROM]: I5's shape of main. Walks MAIN's
# first-parent line down to FROM (a push: the main it moves from) or to its
# base on DEV's first-parent line: every commit walked is a release merge
# "[MERGE] dev into main: <v>" whose second parent is a dev commit carrying
# <v> and an annotated release/<v>, whose tree is that commit's tree, and
# whose first parent's release point is an ancestor of it (releases go
# forward). The base is the root or a release made before release merges
# (it carries release/<v>); a push never reaches it (FROM is met first).
# Prints "I5 <sha> <why>" per break.
rapid_main_check() {
  local main="$1" dev="$2" from="${3:-}" fp root c n p1 p2 v
  fp=$(git rev-list --first-parent "$dev"); root=$(tail -n 1 <<<"$fp")
  c=$(git rev-parse "$main")
  while :; do
    [ -n "$from" ] && [ "$c" = "$from" ] && return 0
    if grep -Fx -- "$c" <<<"$fp" >/dev/null; then
      if [ -n "$from" ]; then echo "I5 $c main moves to a dev commit; it takes only release merges made by rapid release"; return 0; fi
      [ "$c" = "$root" ] && return 0
      v=$(rapid_version_of "$c")
      [ -n "$v" ] && git rev-parse -q --verify "refs/tags/release/$v" >/dev/null \
        || echo "I5 $c $main holds a dev commit that carries no release/<version>"
      return 0
    fi
    n=$(git rev-list --parents -n1 "$c" | wc -w | tr -d ' ')
    if [ "$n" != 3 ]; then echo "I5 $c on $main is neither a release merge nor a released dev commit"; return 0; fi
    p1=$(git rev-parse "$c^1"); p2=$(git rev-parse "$c^2")
    grep -Fx -- "$p2" <<<"$fp" >/dev/null || { echo "I5 $c release merge's second parent is not on dev's first-parent line"; return 0; }
    v=$(rapid_version_of "$p2")
    [ "$(git log -1 --format=%s "$c")" = "[MERGE] dev into main: ${v:-<no version>}" ] \
      || echo "I5 $c subject is not '[MERGE] dev into main: ${v:-<version>}'"
    { [ -n "$v" ] && [ "$(git cat-file -t "refs/tags/release/$v" 2>/dev/null)" = tag ]; } \
      || echo "I5 $c releases ${v:-a commit with no version}, which carries no annotated release/<version>"
    [ "$(git rev-parse "$c^{tree}")" = "$(git rev-parse "$p2^{tree}")" ] || echo "I5 $c tree is not the released dev commit's tree"
    git merge-base --is-ancestor "$(rapid_release_point "$p1" "$fp")" "$p2" || echo "I5 $c releases a dev commit older than the release before it"
    c="$p1"
  done
}

# The history checkpoint. After a doctor --history run in which every
# invariant held, this clone records the dev tip it verified in a note inside
# its git dir, <git common dir>/rapid-history-verified: never a tracked file,
# never a ref, so never pushed, and one per clone (its worktrees share it).
# The next run checks merges in full only after that tip (RAPID_HISTORY_SINCE);
# the version chain before it and the whole-history checks (I5 to I9) still
# run every time. The note is trusted only while all three still hold, else
# the run walks every merge and says why (rapid_history_checkpoint):
#   1. the recorded merge is on dev's first-parent line (hence an ancestor of
#      dev): a rewritten or reset dev is walked in full;
#   2. the v* and release/* tags reachable from it are the ones recorded: the
#      version chain I2 reads from the skipped merges has not moved;
#   3. the verifier is the one recorded (rapid_history_verifier): the running
#      rapid and its lib/, its conf, admins and FRAMEWORK, and the gpg.*
#      settings the signature check reads. A changed rule or config re-judges
#      every merge.
# rapid doctor --history --all ignores the note; --since REV and --history-only
# never read or write it.

# rapid_history_note: the note's path.
rapid_history_note() { printf '%s/rapid-history-verified' "$(git rev-parse --git-common-dir)"; }

# rapid_history_verifier: one hash of the verifier's own code and config.
rapid_history_verifier() {
  local d="${RAPID_SELF:-$(rapid_ns)}" f
  { for f in "$d/rapid" "$d"/lib/*.sh "$d/conf" "$d/admins" "$d/FRAMEWORK"; do
      [ -f "$f" ] || continue
      printf '== %s\n' "${f#"$d"/}"; cat "$f"
    done
    printf '== gpg\n'; git config --get-regexp '^gpg[.]' 2>/dev/null || true
  } | git hash-object --stdin
}

# rapid_history_tags M: one hash of the v* and release/* tags reachable from M.
rapid_history_tags() {
  git for-each-ref --merged "$1" --format='%(refname) %(objectname)' 'refs/tags/v*' 'refs/tags/release/*' | git hash-object --stdin
}

# rapid_history_checkpoint [DEV]: "from <sha>" when the note may be trusted,
# else "full <why>".
rapid_history_checkpoint() {
  local dev="${1:-dev}" f m
  f=$(rapid_history_note)
  [ -s "$f" ] || { echo "full no merge verified by this clone yet"; return 0; }
  m=$(sed -nE 's/^merge=([0-9a-f]{40,64})$/\1/p' "$f" | sed -n 1p)
  [ -n "$m" ] && git cat-file -e "$m^{commit}" 2>/dev/null || { echo "full the checkpoint note names no commit"; return 0; }
  git rev-list --first-parent "$dev" | grep -Fx -- "$m" >/dev/null \
    || { echo "full the recorded merge $(git rev-parse --short "$m") is no longer on $dev's first-parent line"; return 0; }
  [ "tags=$(rapid_history_tags "$m")" = "$(sed -n '/^tags=/{p;q;}' "$f")" ] \
    || { echo "full the version or release tags up to the recorded merge changed"; return 0; }
  [ "verifier=$(rapid_history_verifier)" = "$(sed -n '/^verifier=/{p;q;}' "$f")" ] \
    || { echo "full the verifier's code or config changed since the recorded run"; return 0; }
  echo "from $m"
}

# rapid_history_record [DEV]: write the note for DEV's tip (after a clean run).
rapid_history_record() {
  local m f
  m=$(git rev-parse "${1:-dev}^{commit}"); f=$(rapid_history_note)
  printf 'merge=%s\ntags=%s\nverifier=%s\n' "$m" "$(rapid_history_tags "$m")" "$(rapid_history_verifier)" > "$f.tmp.$$"
  mv -f "$f.tmp.$$" "$f"
}

# rapid_version_map: "<commit> <version>" for each commit a version tag names,
# the tag rapid_version_of picks (the first well-formed v* in name order), from
# one git call, so the whole-history walks run no git per merge.
rapid_version_map() {
  git tag -l 'v*' --format='%(refname:short) %(objecttype) %(objectname) %(*objecttype) %(*objectname)' \
    | awk '$1 ~ /^v[0-9][0-9][0-9][0-9][.][0-9]+[.][0-9]+$/ {
        c = ""; if ($2 == "commit") c = $3; else if ($2 == "tag" && $4 == "commit") c = $5
        if (c != "" && !(c in seen)) { seen[c] = 1; print c, $1 } }'
}
# rapid_first_parents DEV: "<commit> <version or ->" for each commit on DEV's
# first-parent line, oldest first.
rapid_first_parents() {
  git rev-list --first-parent --reverse "$1" | RAPID_VMAP="$(rapid_version_map)" awk 'BEGIN { n = split(ENVIRON["RAPID_VMAP"], L, "\n")
    for (i = 1; i <= n; i++) if (split(L[i], a, " ") == 2) ver[a[1]] = a[2] }
    { print $1, (($1 in ver) ? ver[$1] : "-") }'
}
# _hrel V: 0 when refs/tags/release/V exists (_HV_REL: the release tag refs, newline-framed).
_hrel() { case "$_HV_REL" in *$'\n'"refs/tags/release/$1"$'\n'*) return 0 ;; esac; return 1; }

# rapid_history_check [DEV] [MAIN]: every invariant over the whole history.
rapid_history_check() {
  local dev="${1:-dev}" main="${2:-main}" since="${RAPID_HISTORY_SINCE:-}" checking=1 root c out prev="" released=0 v t tc slugs dup s r
  git rev-parse -q --verify "$dev^{commit}" >/dev/null || { echo "I1 - no $dev branch"; return 0; }
  root=$(git rev-list --first-parent --max-parents=0 "$dev" | tail -n 1)
  local _HV_REL fpv cv
  fpv=$(rapid_first_parents "$dev")
  _HV_REL=$'\n'"$(git for-each-ref --format='%(refname)' refs/tags/release/)"$'\n'
  [ -z "$since" ] || { since=$(git rev-parse -q --verify "$since^{commit}") || { echo "I1 - unknown revision for --since"; return 0; }; checking=0; }
  [ "$since" != "$root" ] || checking=1
  # the version chain is read from the tags first (a merge's "OK <version>" is
  # its own version tag when it is a two-parent merge), so every merge's
  # check is independent: they run at once (rapid_check_merges_par), and
  # their findings print in history order
  local twop jobs="" pd i
  twop=$'\n'"$(git rev-list --first-parent --min-parents=2 --max-parents=2 "$dev")"$'\n'
  while read -r c cv <&3; do
    [ "$c" = "$root" ] && continue
    if [ "$checking" = 0 ]; then
      # before SINCE: only the version chain, for the checks that follow
      v=${cv#-}; [ -z "$v" ] || { prev="$v"; if _hrel "$v"; then released=1; else released=0; fi; }
      [ "$c" = "$since" ] && checking=1
      continue
    fi
    jobs="$jobs$c ${prev:--} $released"$'\n'
    v=${cv#-}
    case "$twop" in *$'\n'"$c"$'\n'*) ;; *) v="" ;; esac
    if [ -n "$v" ]; then
      prev="$v"
      if _hrel "$v"; then released=1; else released=0; fi
    fi
  done 3<<<"$fpv"
  if [ -n "$jobs" ]; then
    pd=$(mktemp -d "${TMPDIR:-/tmp}/rapid-history.XXXXXX")
    rapid_check_merges_par "$pd" <<<"$jobs"
    i=1
    while [ -f "$pd/$i" ]; do grep -v '^OK ' "$pd/$i" | sed '/^$/d' || true; i=$((i + 1)); done
    rm -rf "$pd"
  fi
  # I5: main holds nothing dev lacks, release merge by release merge
  if git rev-parse -q --verify "$main^{commit}" >/dev/null; then
    rapid_main_check "$main" "$dev"
  fi
  # I5: main is production; each release was an admin's, by the admins at the release before it
  local gov="$root" rt rtag tagger why
  while read -r c cv <&3; do
    v=${cv#-}; [ -n "$v" ] || continue
    rt="refs/tags/release/$v"
    _hrel "$v" || continue
    # releases made before the framework knew the owner rule are not judged by it
    if git show "$c:.rapid/lib/policy.sh" 2>/dev/null | grep -F 'release_who' >/dev/null; then
      rtag=$(git rev-parse "$rt")
      if [ "$(git cat-file -t "$rtag")" != tag ]; then
        echo "I5 $c release/$v is not an annotated tag"
      else
        tagger=$(git for-each-ref --format='%(taggeremail)' "$rt" | tr -d '<>')
        why=$(rapid_policy_may_release "$gov" "$c" "$tagger") || echo "I5 $c release/$v tagged by '${tagger:-<none>}': $why"
        why=$(rapid_release_sig_problem "$rt" "$gov" "$c"); [ -z "$why" ] || echo "I5 $c $why"
      fi
    fi
    gov="$c"
  done 3<<<"$fpv"
  # I6
  local fp ty o pt po; fp=$'\n'"$(git rev-list --first-parent "$dev")"$'\n'
  while read -r t ty o pt po; do
    [ -n "$t" ] || continue
    # a tag of a commit, or an annotated tag of one, peels here; anything else asks git
    if [ "$ty" = commit ]; then tc="$o"; elif [ "$ty" = tag ] && [ "$pt" = commit ]; then tc="$po"; else tc=$(git rev-parse "$t^{commit}"); fi
    case "$fp" in *$'\n'"$tc"$'\n'*) ;; *) echo "I6 $tc tag $t is off dev's first-parent line" ;; esac
  done <<<"$(git tag -l 'v*' 'release/*' --format='%(refname:short) %(objecttype) %(objectname) %(*objecttype) %(*objectname)')"
  # I7 (a branch landed into the open batch keeps its branch until rapid land: not a repeat)
  local bbranches; bbranches=$(cat "$(git rev-parse --git-common-dir)/rapid/batch.branches" 2>/dev/null || true)
  slugs=$( { git log --first-parent --format=%s "$dev" | sed -nE 's/^\[MERGE\] pool\/[^ ]*[.]([a-z0-9-]+) into dev: .*/\1/p'
             git for-each-ref --format='%(refname:short)' $RAPID_POOL_NS | { if [ -n "$bbranches" ]; then grep -vxF -- "$bbranches" || true; else cat; fi; } | sed -nE 's#^pool/[^/]+/##p' | sed -E "s/^$RAPID_NUM_RE[.]//; s/^[a-z]+[.]//"; } )
  dup=$(sort <<<"$slugs" | uniq -d | sed '/^$/d' || true)
  for s in $dup; do
    # a branch still open after it landed is the one allowed repeat: land deletes it, a stale copy is reported
    echo "I7 - branch slug '$s' is used more than once"
  done
  # I7 for numbers: each "number slug" pair once; a number with two slugs is two branches
  local pairs
  pairs=$( { git log --first-parent --format='%(trailers:key=Branch-Number,valueonly,separator=%x2C)%x09%s' "$dev" \
               | awk -F '\t' '$1 ~ /^n/ && $2 ~ /^\[MERGE\] pool\/[^ ]+ into dev: / { split($2, w, " "); sub(/^.*[.]/, "", w[2]); print $1, w[2] }'
             git for-each-ref --format='%(refname:short)' $RAPID_POOL_NS \
               | sed -nE "s#^pool/[^/]+/($RAPID_NUM_RE)[.][a-z]+[.]([a-z0-9-]+)\$#\\1 \\2#p"; } | sort -u )
  for s in $(awk '{ print $1 }' <<<"$pairs" | sort | uniq -d); do
    echo "I7 - branch number '$s' names more than one branch"
  done
  # I8 at the tip
  local reqs; reqs=$'\n'"$(git ls-tree --name-only "$dev" requirements/)"$'\n'
  for s in $(git log --first-parent --format=%s "$dev" | sed -nE 's/^\[MERGE\] pool\/[^ ]*[.]([a-z0-9-]+) into dev: .*/\1/p'); do
    case "$reqs" in *$'\n'"requirements/$s.md"$'\n'*) ;; *) echo "I8 - requirements/$s.md was deleted after it landed" ;; esac
  done
  # I3 over a batch: deferred gates are shown by the close record
  rapid_batch_receipts "$dev"
  # I9
  rapid_reland_pending "$dev" | sed 's/^/I9 - re-land pending: /'
  [ ! -d "$(git rev-parse --git-path rapid-reland)" ] || echo "I9 - a rapid sync --dev re-land is half done; finish it with --continue or --abort"
  return 0
}

# rapid_exceptions [DEV]: one line per kind of exception the rules let land,
# "<kind>: <n> merge(s): <versions>", for merges carrying Bulk:, Untested:,
# Gate-Change: or Docs: none, for merges of a batch its close gated (batch-close)
# and for merges no gate ran on (no-gate). The
# history audit prints it so every exception is visible from one command.
rapid_exceptions() {
  local dev="${1:-dev}" root v kind out
  root=$(git rev-list --first-parent --max-parents=0 "$dev" | tail -n 1)
  # one git call for every merge's trailers (%(trailers:only,unfold) is what
  # interpret-trailers --parse reads) and one for the versions (rapid_version_map)
  out=$(git log --first-parent --reverse --format='%x1e%H %h%n%(trailers:only,unfold)' "$dev" \
    | RAPID_VMAP="$(rapid_version_map)" awk -v root="$root" 'BEGIN { RS = "\036"; n = split(ENVIRON["RAPID_VMAP"], L, "\n")
        for (i = 1; i <= n; i++) if (split(L[i], a, " ") == 2) ver[a[1]] = a[2] }
      NF { k = split($0, l, "\n"); split(l[1], h, " "); if (h[1] == root) next
        v = (h[1] in ver) ? ver[h[1]] : h[2]; b = u = gc = dn = 0; g = ""; gg = 0
        for (i = 2; i <= k; i++) {
          if (l[i] ~ /^Bulk: /) b = 1; if (l[i] ~ /^Untested: /) u = 1; if (l[i] ~ /^Gate-Change: /) gc = 1
          if (l[i] ~ /^Docs: none/) dn = 1;
          if (!gg && l[i] ~ /^Gates: /) { g = substr(l[i], 8); gg = 1 } }
        if (b) print "bulk", v; if (u) print "untested", v; if (gc) print "gate-change", v
        if (dn) print "docs-none", v
        if (g ~ /^deferred to the close of batch /) { split(g, w, " "); print "batch:" w[7], v, h[1] } else if (g !~ /=pass/) print "no-gate", v }')
  # a batch merge counts by what its close ran: a gate (batch-close), or none configured (no-gate)
  local bid bk blast bnote
  for bid in $(awk '$1 ~ /^batch:/ { print substr($1, 7) }' <<<"$out" | sort -u); do
    blast=$(awk -v b="batch:$bid" '$1 == b { s = $3 } END { print s }' <<<"$out"); bk=batch-close
    bnote=$(git notes --ref=gates show "$blast" 2>/dev/null || true)
    if grep -q '^exit=none (no gate configured)$' <<<"$bnote" && ! grep -q '^exit=0$' <<<"$bnote"; then bk=no-gate; fi
    out=$(sed "s/^batch:$bid /$bk /" <<<"$out")
  done
  for kind in bulk untested gate-change docs-none batch-close no-gate; do
    v=$(awk -v k="$kind" '$1 == k { printf " %s", $2 }' <<<"$out")
    [ -z "$v" ] || printf '%s: %s merge(s):%s\n' "$kind" "$(wc -w <<<"$v" | tr -d ' ')" "$v"
  done
}

# rapid_batch_receipts [DEV]: a merge landed into a batch says "Gates: deferred to the close of batch
# close <id>": no gate ran on its tree at the land. That receipt holds once the last merge
# of its batch carries the record of the close in its gate log (refs/notes/gates): the gate
# that ran on the final tree, exit 0 (or the plain statement that no gate is configured). Prints "I3 <sha> <why>" for a batch with no such
# record; the batch still open in this clone is exempt (its close has not run yet).
rapid_batch_receipts() {
  local dev="${1:-dev}" rows id last tree bf open=""
  rows=$(git log --first-parent --reverse --format='%H %(trailers:key=Gates,valueonly,separator=%x20)' "$dev" \
    | sed -nE 's/^([0-9a-f]+) deferred to the close of batch ([0-9a-f]+).*$/\2 \1/p')
  [ -n "$rows" ] || return 0
  bf="$(git rev-parse --git-common-dir)/rapid/batch"
  [ ! -s "$bf" ] || open=$(cat "$bf")
  awk '{ last[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } } END { for (i = 1; i <= n; i++) print order[i], last[order[i]] }' <<<"$rows" \
  | while read -r id last; do
    [ -z "$open" ] || [ "$(git rev-parse -q --verify "$id^{commit}" 2>/dev/null || true)" != "$open" ] || continue
    tree=$(git rev-parse "$last^{tree}")
    git notes --ref=gates show "$last" 2>/dev/null \
      | awk -v t="$tree" '/^close of batch [0-9a-f]+: gates on the final tree / { f = ($NF == t) } f && /^exit=(0|none \(no gate configured\))$/ { ok = 1 } END { exit !ok }' \
      || echo "I3 $last batch $id has no passing close record in the gate log of its last merge: its merges defer their gates and none is shown to have run"
  done
}

# rapid_slug_landed SLUG [DEV]: 0 when DEV's first-parent line holds a merge of SLUG.
rapid_slug_landed() {
  git log --first-parent --format=%s "${2:-dev}" 2>/dev/null | grep -E "^\[MERGE\] pool/[^ ]*[.]$1 into dev: " >/dev/null
}

# rapid_reland_pending [DEV]: the replaced merges whose branch is neither on DEV
# nor kept as a branch not landed yet, one "merge kind/slug" per line (I9). A
# re-land keeps the dev it replaced in a snapshot branch safety/dev-<timestamp>;
# its first-parent merges that DEV lacks are the replaced ones.
rapid_reland_pending() {
  local dev="${1:-dev}" b m subj ks
  for b in $(git for-each-ref --format='%(refname)' 'refs/heads/safety/dev-*'); do
    for m in $(git rev-list --first-parent "$b" --not "$dev"); do
      subj=$(git log -1 --format=%s "$m")
      ks=$(rapid_subject_ks "$subj")
      [ -n "$ks" ] || continue
      set -- $ks
      rapid_slug_landed "$2" "$dev" && continue
      git for-each-ref --format='%(refname)' $RAPID_POOL_NS | sed -E "s#.*/##; s/^$RAPID_NUM_RE[.]//; s/^[a-z]+[.]//" | grep -Fx -- "$2" >/dev/null && continue
      printf '%s %s/%s\n' "$(git rev-parse --short "$m")" "$1" "$2"
    done
  done
}

# rapid_prove_merge M [GATES]: re-run the gates (default "fast full") the conf at M's first parent names on
# M's own tree and compare with M's Gates: receipt. Prints "P1 <m> <why>" per
# gate that fails (a receipt that claims a pass it cannot show is a lie).
rapid_prove_merge() {
  local m="$1" gates="${2:-fast full}" p1 wt g r receipt claimed out=""
  p1=$(git rev-parse "$m^1"); receipt=$(rapid_trailer "$m" Gates)
  # a batch merge is proven by what its close ran: gates_each on its own tree, and on the
  # last merge of the batch (the one carrying the close record) the full gate as well
  if [[ "$receipt" == "deferred to the close of batch "* ]]; then
    gates=each
    ! grep -q '^close of batch [0-9a-f]*: gates on the final tree ' <<<"$(git notes --ref=gates show "$m" 2>/dev/null || true)" || gates="each full"
    p1="$m"
  fi
  wt=$(mktemp -d "${TMPDIR:-/tmp}/rapid-prove.XXXXXX")
  git worktree add -q --detach "$wt" "$m" >/dev/null 2>&1 || { echo "P1 $m cannot check out its tree"; return 0; }
  for g in $gates; do
    claimed=$(sed -nE "s/(^|.*[[:space:]])$g=([a-z]+).*/\2/p" <<<"$receipt")
    r=$(RAPID_CONF_REV="$p1" rapid_gate "$g" "$wt" 2>/dev/null) || true
    if [ "$r" = fail ]; then
      out="$out
P1 $m gate $g fails on the merge tree (receipt says ${claimed:-nothing})"
    fi
  done
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  [ -z "$out" ] || printf '%s\n' "${out#?}"
  return 0
}

# rapid_ungated_range SINCE DEV: the version (or sha) of each first-parent
# merge of DEV after SINCE whose Gates: receipt names no gate that ran.
rapid_ungated_range() {
  local since="$1" dev="${2:-dev}" root m range g v ng out=""
  ng=" $(rapid_exceptions "$dev" | sed -nE 's/^no-gate: [0-9]+ merge\(s\): //p') "
  root=$(git rev-list --first-parent --max-parents=0 "$dev" | tail -n 1)
  case "$since" in ""|0000000000000000000000000000000000000000) range="$dev" ;; *) range="$since..$dev" ;; esac
  for m in $(git rev-list --first-parent --reverse $range); do
    [ "$m" = "$root" ] && continue
    g=$(rapid_trailer "$m" Gates)
    [[ "$g" == *=pass* ]] && continue
    # a batch merge is gated by its close, unless that close had no gate configured
    if [[ "$g" == "deferred to the close of batch "* ]]; then
      v=$(rapid_version_of "$m"); [ -n "$v" ] || v=$(git rev-parse --short "$m")
      case "$ng" in *" $v "*) out="$out $v" ;; esac
      continue
    fi
    out="$out $(rapid_version_of "$m")"; [ -n "$(rapid_version_of "$m")" ] || out="$out$(git rev-parse --short "$m")"
  done
  printf '%s' "${out# }"
}

# rapid_prove_release C: re-run the release gate the conf at C names on C's own
# tree and compare with the release/<v> tag's Gates: receipt; prints
# "P1 <c> <why>" when a release that claims a pass cannot show one.
rapid_prove_release() {
  local c="$1" v receipt wt r
  v=$(rapid_version_of "$c"); [ -n "$v" ] || return 0
  git rev-parse -q --verify "refs/tags/release/$v" >/dev/null || return 0
  receipt=$(git cat-file -p "refs/tags/release/$v" | sed -nE 's/^Gates: (.*)$/\1/p' | sed -n 1p)
  wt=$(mktemp -d "${TMPDIR:-/tmp}/rapid-prove.XXXXXX")
  git worktree add -q --detach "$wt" "$c" >/dev/null 2>&1 || { echo "P1 $c cannot check out the tree of release/$v"; return 0; }
  r=$(RAPID_CONF_REV="$c" rapid_gate release "$wt" 2>/dev/null) || true
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  [ "$r" != fail ] || echo "P1 $c release gate fails on the tree of release/$v (its tag says ${receipt:-nothing})"
  return 0
}

# rapid_prove_range SINCE DEV: rapid_prove_merge on each first-parent merge of DEV
# after SINCE (SINCE empty or all zeros: every merge after the root), and
# rapid_prove_release on each of them that a release/<v> tag names.
rapid_prove_range() {
  local since="$1" dev="${2:-dev}" root m range
  root=$(git rev-list --first-parent --max-parents=0 "$dev" | tail -n 1)
  case "$since" in ""|0000000000000000000000000000000000000000) range="$dev" ;; *) range="$since..$dev" ;; esac
  for m in $(git rev-list --first-parent --reverse $range); do
    [ "$m" = "$root" ] && continue
    rapid_prove_merge "$m"
    rapid_prove_release "$m"
  done
}

