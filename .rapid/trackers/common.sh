# shellcheck shell=bash
# trackers/common.sh - what the shipped adapters share: the argument shape of
# the tracker contract (lib/tracker.sh), named refusals and the JSON answers.
# An adapter sets T_NAME, sources this file and calls t_args "$@".
# Exit codes: 2 a refusal before any call (usage, a missing tool, a missing
# credential or setting), 1 the provider failed or answered something else.

t_die() { echo "X trackers/$T_NAME: $1" >&2; exit "${2:-2}"; }

# t_need TOOL HINT: the tool the adapter drives is installed.
t_need() { command -v "$1" >/dev/null 2>&1 || t_die "$1 is not installed${2:+ ($2)}"; }

# t_args OP ID [FLAGS]: sets T_OP T_KEY T_NUM T_BRANCH T_TO T_REF, or refuses.
#   get <ID> | link <ID> --branch <branch> | transition <ID> --to <state> [--ref <version>]
t_args() {
  T_OP="${1:-}"; T_KEY="${2:-}"; T_BRANCH=""; T_TO=""; T_REF=""
  case "$T_OP" in
    get|link|transition) ;;
    *) t_die "usage: $T_NAME get <ID> | link <ID> --branch <branch> | transition <ID> --to done [--ref <version>]" ;;
  esac
  [[ "$T_KEY" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]] || t_die "a ticket id looks like CODE-123, got '$T_KEY'"
  T_NUM="${T_KEY##*-}"
  shift 2
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || t_die "$1 needs a value"
    case "$T_OP $1" in
      "link --branch") T_BRANCH="$2" ;;
      "transition --to") T_TO="$2" ;;
      "transition --ref") T_REF="$2" ;;
      *) t_die "$T_OP does not take $1" ;;
    esac
    shift 2
  done
  case "$T_OP" in
    link) [ -n "$T_BRANCH" ] || t_die "link needs --branch <branch>" ;;
    transition)
      case "$T_TO" in
        done|in-progress|in-review) ;;
        *) t_die "transition needs --to done, in-progress or in-review, got '$T_TO'" ;;
      esac ;;
  esac
}

# t_link_text, t_done_text: the one sentence an adapter leaves on the ticket.
t_link_text() { printf 'rapidgit branch %s now carries %s.' "$T_BRANCH" "$T_KEY"; }
t_done_text() { if [ -n "$T_REF" ]; then printf 'Landed as %s.' "$T_REF"; else printf 'Landed.'; fi; }

t_ok() { printf '{"ok": true}\n'; }

# t_ticket KEY URL: the provider's ticket JSON on stdin (GitHub issue or JIRA
# issue shape) becomes the contract's get answer, one JSON object on one line.
t_ticket() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, list): d = d[0] if d else {}
f = d.get("fields", d)
def text(v):
    if isinstance(v, str): return v
    if isinstance(v, dict):
        if v.get("type") == "text": return v.get("text", "")
        return "".join(text(c) for c in v.get("content", [])) + ("\n" if v.get("type") == "paragraph" else "")
    if isinstance(v, list): return "".join(text(c) for c in v)
    return ""
st = f.get("status", f.get("state", ""))
title = f.get("summary", f.get("title", ""))
if not isinstance(title, str) or not title: sys.exit("the ticket has no title")
print(json.dumps({"key": sys.argv[1], "title": title,
                  "body": text(f.get("description", f.get("body", "")) or "").strip(),
                  "state": st.get("name", "") if isinstance(st, dict) else str(st),
                  "url": f.get("url", "") or sys.argv[2]}))' "$1" "$2" \
    || t_die "the provider did not answer a ticket for $1" 1
}
