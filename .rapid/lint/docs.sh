#!/usr/bin/env bash
# lint/docs.sh - the docs state only what the code holds. Every fact a doc
# can get stale on is read from the code and checked against the docs:
#   verbs        the dispatcher in .rapid/rapid; README's command table has a row
#                for each with every long flag its usage names; any `rapid X`
#                in a doc is a real verb; "N verbs" counts them
#   invariants   the I<n> list in lib/history.sh; RULES has a row for each; no
#                doc names a higher id; "I1 to I<n>" alone means all of them
#   conf keys    the key list in lib/policy.sh, every key the code reads, the
#                keys .rapid/conf sets and RULES' policy table are one set
#   kinds, tags  core.sh and message.sh hold the lists RULES and SKILL print
#   scenarios    (framework source only) every scenario a doc names by its slug (scenario `<slug>`
#                or tests/scenarios/<slug>) exists, and "N scenarios" matches the matrix
#   production   every doc and the usage state "main is production" (only
#                the owner promotes dev to main)
#   lenses       every lens file SKILL's task table names exists, every lens
#                file is named there (the lazy loader resolves), and every
#                home RULE-MAP gives is a file that exists
#   limits       the subject limits (message.sh) and the max_commits
#                (policy.sh) and max_commit_lines (audit.sh) defaults wherever RULES, SKILL
#                and the policy table state them; every exit code rapid uses
#                in the usage's "Exit codes:" line
#   sections     FLOWS keeps the section that carries each verb's flow
#   layout       DESIGN's Layout section names every file under .rapid/lib,
#                .rapid/hooks and .rapid/lint
# Docs: .rapid/*.md, .rapid/skill/SKILL.md, rapid's usage header and, in the
# framework source, the root README.md. Requirement files are history (I8),
# never edited after they land, so they are not judged here. Prints one line
# per finding; exit 1 on any.  Run from the tree root.
set -euo pipefail
N=.rapid
[ -f "$N/rapid" ] || { echo "X docs: no $N/rapid here; run from the tree root" >&2; exit 1; }
rc=0
bad() { echo "X docs: $*"; rc=1; }
docs=("$N/README.md" "$N/RULES.md" "$N/FLOWS.md" "$N/DESIGN.md" "$N/skill/SKILL.md")
[ -f "$N/FRAMEWORK" ] && [ -f README.md ] && docs+=(README.md)
for f in "${docs[@]}"; do [ -f "$f" ] || bad "$f is missing"; done
usage=$(awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$N/rapid")
# the lens files are read on demand; they are checked for facts like every doc
lenses=(); for f in "$N"/skill/lenses/*.md; do [ -f "$f" ] && lenses+=("$f"); done
alltext() { cat "${docs[@]}" ${lenses[@]+"${lenses[@]}"} 2>/dev/null; printf '%s\n' "$usage"; }
# words before "verbs" or "scenarios" that are not a count
stop='the|its|all|every|these|those|both|more|other|by|fast|own|real|of|and|or|its|same|new|first|which|software|reviewer|assistant|standard|implementation|impl'
words="zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen"
num() { local w="$1" i=0 x; case "$w" in *[!0-9]*) for x in $words; do [ "$x" = "$w" ] && { echo "$i"; return; }; i=$((i + 1)); done; echo -1 ;; *) echo "$w" ;; esac; }

# ---- verbs and their flags
verbs=$(sed -nE 's/^  ([a-z]+)\) shift; cmd_[a-z]+ "\$@" ;;$/\1/p' "$N/rapid")
nverbs=$(wc -w <<<"$verbs" | tr -d ' ')
[ "$nverbs" -gt 0 ] || bad "no verbs found in $N/rapid's dispatcher"
for v in $verbs; do
  row=$(grep -E "^\| .*\`rapid $v\`" "$N/README.md" || true)
  [ -n "$row" ] || { bad "$N/README.md has no command-table row for rapid $v"; continue; }
  flags=$(awk -v v="$v" '$0 ~ "^  rapid " v "( |$)" { on = 1; print; next }
      on && /^   +[^ ]/ && $0 !~ /^  rapid / { print; next } { on = 0 }' <<<"$usage" | grep -oE -- '--[a-z][a-z-]*' | sort -u || true)
  for fl in $flags; do
    grep -F -- "$fl" <<<"$row" >/dev/null || bad "$N/README.md's row for rapid $v does not name $fl (its usage does)"
  done
done
for f in "${docs[@]}"; do
  [ -f "$f" ] || continue
  while IFS=: read -r ln w; do
    [ -n "$w" ] || continue
    grep -Fx -- "$w" <<<"$verbs" >/dev/null || bad "$f:$ln names 'rapid $w', which is not a verb ($(tr '\n' ' ' <<<"$verbs"))"
  done <<<"$(grep -noE '(`|\.rapid/)rapid [a-z]+' "$f" | sed -E 's/^([0-9]+):.*rapid ([a-z]+)$/\1:\2/' || true)"
done
while read -r w; do
  [ -n "$w" ] || continue
  [ "$(num "$w")" = "$nverbs" ] || bad "a doc says '$w verbs'; rapid has $nverbs"
done <<<"$(alltext | grep -oiE '\b[a-z0-9]+ verbs\b' | sed -E 's/ verbs$//' | tr 'A-Z' 'a-z' | grep -vxE "$stop" || true)"

# ---- invariants
imax=$(sed -nE 's/^#   I([0-9]+) .*/\1/p' "$N/lib/history.sh" | sort -n | tail -n 1)
[ -n "$imax" ] || bad "no invariant list in $N/lib/history.sh"
imax=${imax:-0}
for k in $(seq 1 "$imax"); do
  grep -E "^\| I$k \|" "$N/RULES.md" >/dev/null || bad "$N/RULES.md's invariant table has no row for I$k"
done
while read -r k; do
  [ -n "$k" ] || continue
  [ "$k" -le "$imax" ] || bad "a doc names I$k; history.sh defines I1 to I$imax"
done <<<"$(alltext | grep -oE '(^|[^A-Za-z0-9])I[0-9]+\b' | sed -E 's/.*I//' | sort -un || true)"
while read -r k; do
  [ -n "$k" ] || continue
  [ "$k" = "$imax" ] || bad "a doc says 'I1 to I$k' for the whole set; history.sh defines I1 to I$imax"
done <<<"$(alltext | grep -oE 'I1( to |-)I[0-9]+([^0-9 ,]|$| [^a]| a[^n])' | sed -E 's/^I1( to |-)I([0-9]+).*/\2/' || true)"

# ---- conf keys
keys=$(sed -nE 's/^#   ([a-z_]+)=.*/\1/p' "$N/lib/policy.sh" | sort -u)
[ -n "$keys" ] || bad "no conf key list in $N/lib/policy.sh"
code=$(cat "$N/rapid" "$N"/lib/*.sh "$N"/hooks/* | grep -oE 'rapid_conf [a-z_]+' | sed 's/^rapid_conf //' | sort -u || true)
for k in $code; do grep -Fx -- "$k" <<<"$keys" >/dev/null || bad "the code reads conf key $k; lib/policy.sh does not list it"; done
table=$(sed -n '/^## Policy/,/^## [^P]/p' "$N/RULES.md" | sed -nE 's/^\| `([a-z_]+)` \|.*/\1/p' | sort -u)
for k in $keys; do grep -Fx -- "$k" <<<"$table" >/dev/null || bad "$N/RULES.md's policy table lacks conf key $k"; done
for k in $table; do grep -Fx -- "$k" <<<"$keys" >/dev/null || bad "$N/RULES.md's policy table names $k, which the code does not know"; done
if [ -f "$N/conf" ]; then
  for k in $(sed -nE 's/^[[:space:]]*([a-z_]+)[[:space:]]*=.*/\1/p' "$N/conf"); do
    grep -Fx -- "$k" <<<"$keys" >/dev/null || bad "$N/conf sets $k, which the code does not know"
  done
fi

# ---- kinds and commit tags: one list in the code, printed the same in the docs
kinds=$(sed -nE 's/^RAPID_KINDS="(.*)"$/\1/p' "$N/lib/core.sh")
grep -F "Kinds: \`$kinds\`" "$N/RULES.md" >/dev/null || bad "$N/RULES.md does not list the kinds as \`$kinds\`"
grep -F "kinds: $kinds" "$N/skill/SKILL.md" >/dev/null || bad "$N/skill/SKILL.md does not list the kinds as '$kinds'"
grep -F "kinds: $kinds." <<<"$usage" >/dev/null || bad "rapid's usage does not list the kinds as '$kinds'"
tags="[$(sed -nE 's/^RAPID_TAGS="(.*)"$/\1/p' "$N/lib/message.sh" | tr ' ' '|')]"
for f in "$N/RULES.md" "$N/skill/SKILL.md"; do
  grep -F -- "$tags" "$f" >/dev/null || bad "$f does not list the commit tags as $tags"
done

# ---- production: main is production and only the owner promotes; every doc says so
for f in "${docs[@]}"; do
  [ -f "$f" ] || continue
  grep -F 'main is production' "$f" >/dev/null || bad "$f does not state that main is production (only the owner promotes dev to main)"
done
grep -F 'main is production' <<<"$usage" >/dev/null || bad "rapid's usage does not state that main is production"

# ---- limits: one number in the code, the same number in every doc that states it
smin=$(sed -nE 's/^RAPID_SUBJ_MIN=([0-9]+)$/\1/p' "$N/lib/message.sh"); smax=$(sed -nE 's/^RAPID_SUBJ_MAX=([0-9]+)$/\1/p' "$N/lib/message.sh")
[ -n "$smin" ] && [ -n "$smax" ] || bad "$N/lib/message.sh names no RAPID_SUBJ_MIN and RAPID_SUBJ_MAX"
for f in "$N/RULES.md" "$N/skill/SKILL.md"; do
  flat=$(tr '\n' ' ' < "$f" | tr -s ' ')
  while read -r a b; do
    [ -n "$a" ] || continue
    [ "$a $b" = "$smin $smax" ] || bad "$f says subjects are $a to $b chars; message.sh says $smin to $smax"
  done <<<"$(grep -oE '[0-9]+ to [0-9]+ chars, no final period' <<<"$flat" | sed -E 's/^([0-9]+) to ([0-9]+).*/\1 \2/' || true)"
  grep -F "$smin to $smax chars" <<<"$flat" >/dev/null || bad "$f does not state the subject limits ($smin to $smax chars)"
done
bt='`'
for kv in "max_commits RAPID_MAX_COMMITS_DEFAULT policy.sh" "max_commit_lines RAPID_MAX_COMMIT_LINES_DEFAULT audit.sh"; do
  set -- $kv
  d=$(sed -nE "s/^$2=([0-9]+)\$/\1/p" "$N/lib/$3")
  [ -n "$d" ] || { bad "$N/lib/$3 names no $2"; continue; }
  row=$(grep -E "^\| $bt$1$bt \|" "$N/RULES.md" || true)
  [ "$(awk -F'|' '{ gsub(/^ +| +$/, "", $4); print $4 }' <<<"$row")" = "$d" ] || bad "$N/RULES.md's policy table gives $1 a default other than $d"
  while read -r k; do
    [ -n "$k" ] || continue
    [ "$k" = "$d" ] || bad "$N/RULES.md says $1 defaults to $k; policy.sh says $d"
  done <<<"$(tr '\n' ' ' < "$N/RULES.md" | tr -s ' ' | grep -oE "$bt$1$bt[^.;]{0,40}\(default [0-9]+" | sed -E 's/.*default ([0-9]+)$/\1/' || true)"
done
codes=$( { echo 0; echo 1; grep -ohE 'RAPID_RC=[0-9]+' "$N/rapid" "$N"/lib/*.sh | sed 's/.*=//'; grep -oE 'return 3$' "$N/rapid" | sed 's/return //'; } | sort -un)
exitline=$(awk '/^Exit codes:/ { on = 1 } on { printf "%s ", $0; if ($0 ~ /\.$/) exit }' <<<"$usage")
[ -n "$exitline" ] || bad "rapid's usage has no 'Exit codes:' line"
for k in $codes; do
  grep -E "(:|,) $k " <<<"$exitline" >/dev/null || bad "rapid exits $k; the usage's Exit codes line does not say what it means"
done

# ---- sections: FLOWS keeps the flow of every verb
flows_heads=$(grep -E '^## ' "$N/FLOWS.md" || true)
for vh in "setup:## Start a repository" "branch:## Work on a change" "land:## Work on a change" "check:## Work on a change" \
          "sync:## When dev moved under you" "release:## Release" "bisect:## Find and undo a regression" \
          "status:## Recover and tidy" "doctor:## Recover and tidy"; do
  v="${vh%%:*}"; h="${vh#*:}"
  grep -Fx -- "$v" <<<"$verbs" >/dev/null || continue
  grep -F -- "$h" <<<"$flows_heads" >/dev/null || bad "$N/FLOWS.md lost the section '$h' that carries the flow of rapid $v"
done
for v in $verbs; do
  grep -F "rapid $v" "$N/FLOWS.md" >/dev/null || bad "$N/FLOWS.md never names rapid $v"
done

# ---- layout: DESIGN names every file of the framework's code
layout=$(sed -n '/^## Layout/,/^## Bootstrap/p' "$N/DESIGN.md")
[ -n "$layout" ] || bad "$N/DESIGN.md has no Layout section"
for f in "$N"/lib/* "$N"/hooks/* "$N"/lint/*; do
  [ -f "$f" ] || continue
  grep -F "${f#$N/}" <<<"$layout" >/dev/null || bad "$N/DESIGN.md's Layout does not name ${f#$N/}"
done

# ---- lenses: the lazy loader resolves both ways, and the rule map points at real homes
if [ -d "$N/skill/lenses" ]; then
  named=$(sed -nE 's/^\| [^|]+ \| `lenses\/([a-z-]+\.md)` \|$/\1/p' "$N/skill/SKILL.md" | sort -u)
  for l in $named; do [ -f "$N/skill/lenses/$l" ] || bad "SKILL.md's lens table names lenses/$l, which does not exist"; done
  for f in "$N"/skill/lenses/*.md; do
    b=$(basename "$f"); [ "$b" = RULE-MAP.md ] && continue
    grep -Fx -- "$b" <<<"$named" >/dev/null || bad "lenses/$b is not in SKILL.md's lens table, so no task loads it"
  done
  if [ -f "$N/skill/lenses/RULE-MAP.md" ]; then
    for h in $(grep -oE '\b[a-z]+\.md\b' "$N/skill/lenses/RULE-MAP.md" | sort -u); do
      case "$h" in SKILL.md) [ -f "$N/skill/SKILL.md" ] ;; RULES.md|FLOWS.md|DESIGN.md|REPLAY.md|README.md) [ -f "$N/$h" ] ;; *) [ -f "$N/skill/lenses/$h" ] ;; esac \
        || bad "RULE-MAP.md names $h as a home; it does not exist"
    done
  fi
fi

# ---- scenarios (the framework source carries its tests)
if [ -d "$N/tests/scenarios" ]; then
  ids=$(ls "$N/tests/scenarios" | sed -nE 's/^(.*)\.sh$/\1/p' | sort)
  nsc=$(wc -w <<<"$ids" | tr -d ' ')
  while read -r k; do
    [ -n "$k" ] || continue
    grep -Fx -- "$k" <<<"$ids" >/dev/null || bad "a doc names scenario $k; no scenario of that slug exists"
  done <<<"$(alltext | grep -oE '(scenario `|tests/scenarios/)[a-z0-9][a-z0-9-]*' | sed -E 's#^(scenario `|tests/scenarios/)##' | sort -u || true)"
  while read -r w; do
    [ -n "$w" ] || continue
    [ "$(num "$w")" = "$nsc" ] || bad "a doc says '$w scenarios'; the matrix has $nsc"
  done <<<"$(alltext | grep -oiE '\b[a-z0-9]+ scenarios\b' | sed -E 's/ scenarios$//' | tr 'A-Z' 'a-z' | grep -vxE "$stop" || true)"
fi
exit "$rc"
