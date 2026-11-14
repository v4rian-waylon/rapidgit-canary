#!/usr/bin/env bash
# lint/dup.sh - no line that a conflict resolution doubled. A rebase or
# merge that unions both sides of a conflict keeps the old line beside the
# new one; the gates pass and the code or the doc then says a thing twice,
# once stale. Three shapes, each found by name:
#   assigned twice  a top-level variable assigned twice in one .rapid/lib/*.sh
#                   or hook (the later value silently wins)
#   doubled help    two echo lines within three lines of each other that
#                   share their first 28 characters, or most of their words,
#                   in one .rapid/lib/*.sh, hook or .rapid/rapid (one is stale)
#   doubled doc     two lines within three lines of each other that share
#                   their first 28 characters, or most of their words, in a
#                   doc (.rapid/*.md, .rapid/skill/SKILL.md and, in the framework
#                   source, the root README.md), code blocks included; table
#                   rows and short lines are left out
# "Most of their words": at least six words each and three in four shared.
# Prints file:line for each finding; exit 1 on any.  Run from the tree root.
set -euo pipefail
rc=0
code=(); docs=()
for f in .rapid/lib/*.sh .rapid/hooks/*; do [ -f "$f" ] && code+=("$f"); done
for f in .rapid/*.md .rapid/skill/SKILL.md; do [ -f "$f" ] && docs+=("$f"); done
[ -f .rapid/FRAMEWORK ] && [ -f README.md ] && docs+=(README.md)

# assigned twice: NAME= at column 0, outside functions and heredocs is close
# enough (a top-level line starts at column 0; function bodies are indented)
for f in ${code[@]+"${code[@]}"}; do
  out=$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*=/ { n = $0; sub(/=.*/, "", n)
      if (n in seen) printf "X assigned twice: %s:%d: %s (first at line %d)\n", FILENAME, FNR, n, seen[n]
      else seen[n] = FNR }' "$f")
  [ -z "$out" ] || { printf '%s\n' "$out"; rc=1; }
done

# near PATTERN FILE...: two kept lines within three lines that share their first
# 28 characters (leading space dropped) or three in four of six words or more
near() {
  local label="$1" mode="$2"; shift 2
  local f out
  for f in "$@"; do
    out=$(awk -v label="$label" -v mode="$mode" '
      function words(s, arr,   n, i, w, k) { n = split(s, w, /[ \t]+/); k = 0
        for (i = 1; i <= n; i++) { gsub(/^[(,;:]+|[),;:.]+$/, "", w[i]); if (w[i] != "") { arr[w[i]] = 1; k++ } }
        return k }
      function similar(a, b,   wa, wb, na, nb, w, inter, uni) {
        if (length(a) >= 28 && length(b) >= 28 && substr(a, 1, 28) == substr(b, 1, 28)) return 1
        split("", wa); split("", wb); na = words(a, wa); nb = words(b, wb)
        if (na < 6 || nb < 6) return 0
        inter = 0; uni = 0
        for (w in wa) { uni++; if (w in wb) inter++ }
        for (w in wb) if (!(w in wa)) uni++
        return inter * 4 >= uni * 3 }
      {
        s = $0; sub(/^[ \t]+/, "", s); keep = 0
        if (mode == "echo") keep = (s ~ /^echo /)
        else keep = (length(s) >= 28 && s !~ /^\|/ && s !~ /^```/)
        if (!keep) next
        for (j = 1; j <= 3; j++) {
          p = FNR - j
          if ((p in line) && similar(line[p], s)) {
            printf "X %s: %s:%d repeats line %d: %s\n", label, FILENAME, FNR, p, s; break }
        }
        line[FNR] = s; delete line[FNR - 4]
      }' "$f")
    [ -z "$out" ] || { printf '%s\n' "$out"; rc=1; }
  done
}
help=(${code[@]+"${code[@]}"}); [ -f .rapid/rapid ] && help+=(.rapid/rapid)
near "doubled help" echo ${help[@]+"${help[@]}"}
near "doubled doc" doc ${docs[@]+"${docs[@]}"}
exit "$rc"
