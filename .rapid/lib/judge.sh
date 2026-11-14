# shellcheck shell=bash
# judge.sh - a branch is judged by dev's framework, never by its own copy (audit 4 H2).
# Sourced first, before any other lib, by .rapid/rapid (for land), hooks/commit-msg and
# hooks/pre-push. Bash 3.2 compatible; callers run under set -euo pipefail.
#
# A branch that rewrites the checks (lib/policy.sh, a hook, rapid itself) would otherwise
# run its own rewritten checks on itself. rapid_judge_exec runs dev's committed .rapid
# instead: exported once per dev framework tree into
#   <git common dir>/rapid/judge/<tree of dev:.rapid>/
# (a cache only rapid writes; the agent guard denies hand writes under rapid/) and
# exec'd with the same arguments, stdin and work tree. RAPID_JUDGED=<tree> marks the
# judged run, so it never re-execs. No dev branch (rapid setup, a fresh clone before
# its first sync) or a running copy whose tracked files are dev's runs as it is.

# rapid_judge_exec SELF ENTRY ARGS...: SELF is the running .rapid directory, ENTRY the
# path of the running script inside it (rapid, hooks/commit-msg, hooks/pre-push).
rapid_judge_exec() {
  local self="$1" entry="$2" top t d tmp
  shift 2
  [ -z "${RAPID_JUDGED:-}" ] || return 0
  t=$(git rev-parse -q --verify 'refs/heads/dev:.rapid' 2>/dev/null) || return 0
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  if [ "$(cd "$self" && pwd -P)" = "$(cd "$top" 2>/dev/null && pwd -P)/.rapid" ] \
     && git -C "$top" diff --quiet refs/heads/dev -- .rapid 2>/dev/null; then
    return 0
  fi
  d="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/rapid/judge/$t"
  if [ ! -f "$d/.rapid/$entry" ]; then
    mkdir -p "$(dirname "$d")"
    tmp=$(mktemp -d "$(dirname "$d")/.x.XXXXXX")
    # through a file, never a pipe: tar stops reading before git ends writing, and the
    # SIGPIPE that then kills git fails the caller without a word under pipefail
    git archive --format=tar -o "$tmp.tar" refs/heads/dev -- .rapid && tar -x -f "$tmp.tar" -C "$tmp"
    rm -f "$tmp.tar"
    if [ -e "$d" ]; then rm -rf "$tmp"; else mv "$tmp" "$d" 2>/dev/null || rm -rf "$tmp"; fi
  fi
  [ -f "$d/.rapid/$entry" ] || return 0
  RAPID_JUDGED="$t" exec bash "$d/.rapid/$entry" "$@"
}
