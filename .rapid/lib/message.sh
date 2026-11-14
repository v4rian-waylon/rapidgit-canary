# shellcheck shell=bash
# message.sh - the commit message rules, one implementation for the
# commit-msg hook, land's per-commit check and doctor --history.

# the subject limits, named once: lint/docs.sh checks every doc that states them
RAPID_SUBJ_MIN=12
RAPID_SUBJ_MAX=72
RAPID_MERGE_SUBJ_MAX=140
RAPID_TAGS="NEW FIX REFACTOR DOCS TEST REVERT HOTFIX MODE"

# rapid_msg_violations FILE [merge]: prints one line per broken rule; empty
# output means the message passes. Comment lines (#) are ignored.
rapid_msg_violations() {
  local f="$1" kind="${2:-commit}" subj second len tag reds
  local body; body=$(grep -v '^#' "$f" || true)
  subj=$(printf '%s\n' "$body" | sed -n 1p)
  second=$(printf '%s\n' "$body" | sed -n 2p)
  len=${#subj}
  if [ "$kind" = merge ]; then
    [[ "$subj" =~ ^\[MERGE\]\ pool/v[0-9]{4}\.[0-9]+/(n[0-9]+\.)?[a-z]+\.[a-z0-9][a-z0-9-]*\ into\ dev:\ v[0-9]{4}\.[0-9]+\.[0-9]+$ ]] \
      || echo "subject must read '[MERGE] pool/v<series>/<number>.<kind>.<slug> into dev: vYYYY.S.N'"
    [ "$len" -le "$RAPID_MERGE_SUBJ_MAX" ] || echo "subject is $len chars (merge max $RAPID_MERGE_SUBJ_MAX)"
    local mbody
    mbody=$(printf '%s\n' "$body" | sed '1,2d' | grep -vE '^[A-Z][A-Za-z-]+: ' || true)
    [ -n "$(printf '%s\n' "$mbody" | sed -n 1p | sed 's/^[[:space:]]*//')" ] && [[ "$(printf '%s\n' "$mbody" | sed -n 1p)" != "- "* ]] \
      || echo "merge body starts with a paragraph saying what the branch does"
    grep -qE '^- ' <<<"$mbody" || echo "merge body lists the branch's changes as a '- ' list after the paragraph"
  else
    tag=$(printf '%s' "$subj" | sed -nE 's/^\[([A-Z]+)\] .*/\1/p')
    if [ -z "$tag" ] || [[ " $RAPID_TAGS " != *" $tag "* ]]; then
      echo "subject must start with one of [${RAPID_TAGS// /] [}] and a space"
    else
      [[ "$subj" =~ ^\[[A-Z]+\]\ [A-Z0-9] ]] || echo "subject text starts with a capital letter or digit"
    fi
    [ "$len" -ge "$RAPID_SUBJ_MIN" ] && [ "$len" -le "$RAPID_SUBJ_MAX" ] || echo "subject is $len chars ($RAPID_SUBJ_MIN to $RAPID_SUBJ_MAX)"
    # a change says what it does and why: a body line of five words that is not the subject again
    case "$tag" in NEW|FIX|REFACTOR|REVERT|HOTFIX)
      if rapid_rule_on commit-body && [ "$(rapid_conf commit_body required 2>/dev/null || echo required)" != optional ]; then
        # the text of a Cause: or Fix: line says what and why as well as a description line does
        local said; said=$(printf '%s\n' "$body" | sed '1,2d' | sed -E 's/^(Cause|Fix): //' | grep -vE '^[A-Z][A-Za-z-]+: ' \
          | awk -v s="${subj#\[*\] }" 'NF >= 5 && $0 != s && !f { print; f = 1 }')
        if [ -z "$said" ]; then
          local shape=" (a description, Cause: or Fix: line)"
          case "$tag" in FIX|HOTFIX) shape="; the shape: a blank line, 'Cause: <why it broke>', a blank line, 'Fix: <what the change does>'" ;; esac
          echo "a [$tag] commit needs a body: a line of five words or more saying what changed and why$shape"
        fi
      fi ;;
    esac
    case "$subj" in *.) echo "subject ends without a period" ;; esac
  fi
  [ -z "$second" ] || echo "second line is blank"
  if LC_ALL=C grep -q -e $'\xe2\x80\x94' -e $'\xe2\x80\x93' <<<"$body"; then echo "no em or en dash; use ',' or '-'"; fi
  if grep -qiE '^co-authored-by:.*claude' <<<"$body"; then echo "no Co-Authored-By: Claude trailer"
  elif rapid_rule_on no-coauthor && grep -qiE '^co-authored-by:' <<<"$body"; then
    echo "no Co-Authored-By: trailer; every author of a commit is its author"
  fi
  reds=$(grep -cE '^Red: .+' <<<"$body" || true)
  [ "${reds:-0}" -le 1 ] || echo "at most one Red: trailer"
  # a test written first and red on purpose is a [TEST] commit; nothing else hides behind Red:
  if [ "${reds:-0}" -ge 1 ] && [ "$kind" != merge ] && rapid_rule_on red-test && [[ "$subj" != "[TEST] "* ]]; then
    echo "a Red: trailer marks a [TEST] commit only (the test written first); this is not one"
  fi
  # commit-audit (lib/audit.sh holds the smells that read the diff)
  if [ "$kind" != merge ] && rapid_rule_on commit-audit; then
    local text="${subj#\[*\] }"
    if grep -qE '(^|[[:space:]])(and|with|plus|or|then|beside)([[:space:]]|$)|\+|,' <<<"$text"; then
      echo "subject joins two concerns ('and', 'with', 'plus', 'or', 'then', 'beside', '+' or ','); one concern per commit: split it"
    fi
    case "$tag" in
      FIX|HOTFIX)
        # after the description: a 'Cause:' paragraph, then a 'Fix:' paragraph
        if ! awk 'NR > 2 && /^Cause: [^[:space:]]/ { c = 1 } NR > 2 && c && /^Fix: [^[:space:]]/ { f = 1 } END { exit !(c && f) }' <<<"$body"; then
          echo "a [$tag] body carries a 'Cause:' paragraph, then a 'Fix:' paragraph (the shape: a blank line, 'Cause: <why it broke>', a blank line, 'Fix: <what the change does>')"
        fi ;;
    esac
  fi
}
