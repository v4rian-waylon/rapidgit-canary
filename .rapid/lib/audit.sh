# shellcheck shell=bash
# audit.sh - the deterministic commit-audit smells (how-git's git-commit-audit
# lens, sections A and C, neo-git's required commit-audit check), one
# implementation for commit-msg, rapid check --each and --audit, rapid land,
# pre-push and I4. They run under rule commit-audit (lib/core.sh), so history
# landed before the rule is never judged by it.
#
#   joiner    a subject whose text needs '+', ',', 'and', 'with', 'plus', 'or', 'then' or 'beside'
#             joins two concerns: split the commit
#   cause-fix a [FIX] or [HOTFIX] body carries a 'Cause:' paragraph, then a
#             'Fix:' paragraph
#   size      a commit changes at most max_commit_lines lines (default 800,
#             added plus deleted, binary files not counted)
#   test      a [NEW], [FIX] or [HOTFIX] commit that changes behaviour (a
#             path that is not a doc, a test, a requirement file, the register
#             or .rapid/conf or .rapid/admins) also touches a test path
#             (test_paths, shell patterns); the commit right after a Red:
#             commit is exempt, its test is the Red: commit's, and a [FIX] or
#             [HOTFIX] may instead name the existing test that proves it with a
#             'Proof: <test path or scenario slug>' trailer, which its tree must
#             hold as a test path
# Message smells live in rapid_msg_violations (lib/message.sh); this file holds
# the two that read the diff.

# the size cap's default, named once: lint/docs.sh checks RULES' policy table against it
RAPID_MAX_COMMIT_LINES_DEFAULT=800
RAPID_TEST_PATHS_DEFAULT='test/* tests/* */test/* */tests/* spec/* */spec/* *_test.* *.test.* *_spec.* test_*'

# rapid_path_is_test PATH: 0 when PATH matches test_paths (dev's conf).
rapid_path_is_test() {
  local p="$1" pat
  set -f
  for pat in $(rapid_conf test_paths "$RAPID_TEST_PATHS_DEFAULT"); do
    # shellcheck disable=SC2254
    case "$p" in $pat) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# rapid_path_is_doc PATH: 0 for prose, requirements and the policy files.
rapid_path_is_doc() {
  case "$1" in
    *.md|*.txt|*.rst|*.adoc|docs/*|*/docs/*|LICENSE*|requirements/*|.rapid/conf|.rapid/admins) return 0 ;;
  esac
  return 1
}

# rapid_proof_test PROOF [REV]: 0 when PROOF, a path or a scenario slug (naming
# .rapid/tests/scenarios/<slug>.sh), is a test path (test_paths) that REV's
# tree holds; with no REV, the index (the commit being made).
rapid_proof_test() {
  local p="$1" rev="${2:-}"
  [ -n "$p" ] || return 1
  git cat-file -e "$rev:$p" 2>/dev/null || { [[ "$p" =~ ^[a-z0-9][a-z0-9-]*$ ]] && p=".rapid/tests/scenarios/$p.sh"; }
  git cat-file -e "$rev:$p" 2>/dev/null && rapid_path_is_test "$p"
}

# rapid_diff_smells SUBJECT NUMSTAT PREV_RED [PROOF [REV]]: the diff smells of
# one commit, one line each. NUMSTAT is 'git diff --numstat' output for the
# commit; PREV_RED is 1 when the commit right before it carries Red:; PROOF is
# its Proof: trailer and REV the commit holding it (none: the index).
rapid_diff_smells() {
  local subj="$1" stat="$2" prev_red="${3:-0}" proof="${4:-}" rev="${5:-}" max lines=0 a d p behav=0 tested=0 tag
  rapid_rule_on commit-audit || return 0
  max=$(rapid_conf max_commit_lines "$RAPID_MAX_COMMIT_LINES_DEFAULT")
  [[ "$max" =~ ^[0-9]{1,6}$ ]] && [ "$max" -ge 1 ] || RAPID_RC=2 rapid_die "max_commit_lines='$max' must be 1 to 999999"
  while IFS=$'\t' read -r a d p; do
    [ -n "${p:-}" ] || continue
    [ "$a" = - ] || lines=$((lines + a))
    [ "$d" = - ] || lines=$((lines + d))
    # a rename reads 'old => new'; judge the new path
    case "$p" in *" => "*) p=$(sed -E 's/\{[^{}]* => ([^{}]*)\}/\1/; s/^.* => //' <<<"$p" | sed 's#//*#/#g') ;; esac
    if rapid_path_is_test "$p"; then tested=1
    elif ! rapid_path_is_doc "$p"; then behav=1; fi
  done <<<"$stat"
  [ "$lines" -le "$max" ] || echo "changes $lines lines (max_commit_lines=$max); split it into atomic commits"
  tag=$(sed -nE 's/^\[([A-Z]+)\] .*/\1/p' <<<"$subj")
  case "$tag" in
    NEW|FIX|HOTFIX)
      if [ "$behav" = 1 ] && [ "$tested" = 0 ] && [ "$prev_red" != 1 ]; then
        if [ "$tag" != NEW ] && [ -n "$proof" ]; then
          rapid_proof_test "$proof" "$rev" \
            || echo "a [$tag] commit names Proof: $proof, which is no test path its tree holds (test_paths); name an existing test file or scenario slug, or commit the change with its test"
        else
          local alt="tag it [REFACTOR] or [DOCS] if it changes no behaviour"
          [ "$tag" = NEW ] || alt="name the existing test that proves it with a 'Proof: <test path or scenario slug>' trailer"
          echo "a [$tag] commit changes behaviour and touches no test path (test_paths); commit the change with its test, or $alt"
        fi
      fi ;;
  esac
}

# rapid_commit_smells C: rapid_diff_smells for commit C (its first parent is the base).
rapid_commit_smells() {
  local c="$1" prev_red=0 base
  rapid_rule_on commit-audit || return 0
  base=$(git rev-parse -q --verify "$c^1" 2>/dev/null || git hash-object -t tree /dev/null)
  [ -z "$(rapid_trailer "$c^1" Red 2>/dev/null || true)" ] || prev_red=1
  rapid_diff_smells "$(git log -1 --format=%s "$c")" "$(git diff --numstat -M "$base" "$c")" "$prev_red" "$(rapid_trailer "$c" Proof)" "$c"
}
