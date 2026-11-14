# Lens: merge bodies

`rapid land` writes the subject (`[MERGE] pool/v<series>/<number>.<kind>.<slug> into dev: vYYYY.S.N`),
the version, the tag and the trailers; never type them. You write the body,
always with `rapid land -F <body>` (the default body lists shas and breaks the
tone rules), and check it first with `rapid land --dry-run -F <body>`.

## Shape
- A 1 to 3 sentence paragraph, a blank line, then a nested list:
  `- <Topic>.` with indented `    - <label>: <summary>.` leaves. Every list
  line ends with a period. No `Changes:` header. Enforced: paragraph then
  list, a paragraph of three words, an item of two words.
- Failing shapes: a paragraph alone, bullets alone, flat bullets, a missing
  period, a header, method names, a comma-separated inline enumeration.
- A revert inside the branch gets its own `- Reverts within the branch.` topic.
- Altitude: topics group the branch's commits by what they change for the
  project. A closing paragraph of `Key: value` lines (`Replays:`, `Fixes:`)
  becomes trailers.

## Tone
- The list is a literal recap of what merged, not a story; read aloud it is
  neither code nor marketing.
- Never the code pole: file or directory names, byte counts or timeouts,
  protocol or RFC references, code construct names, reviewer verbs about the
  implementation, token literals.
- Never the manual pole: outcome pitch (`actually works`, `just works`,
  `becomes usable`), assistant verbs about itself, end-user benefit framing
  (`so you can`, `lets you`), filler (`finally`, `actually`, `now`).
- This merge only: no prior merges, siblings or future work; absolute terms
  (`on top of`, `extending`, `building on`, other versions, other branches
  are refused by review).
- Never: `BAK`, `bak import`, `historical import`, `pre ATM role`,
  `captured in`, `from the zip`, `recovered from`, `reconstructed`,
  `WIP snapshot`, `in this zip`, `preflight`, `rebuild` (as a noun),
  `import`, `snapshot`, `recovered`, `WIP`; no hyphenated prose compounds, no
  `plus`, no em dash (enforced), no `Co-Authored-By` (enforced).

## Before `rapid land`
`rapid land --dry-run -F <body>` prints the message: check the shape, the
tone poles, this-merge-only, `git diff --stat dev...HEAD` against the topics,
and that the first-parent log line reads right. A release is the owner's
`rapid release`; its tag lists the branches still open.

## Many agents, many branches
- Several agents or many branches landing together: `rapid land --batch` in
  each (the close deferred), then one `rapid land` for the last, or from dev (one test, one push); a branch
  that joins while a close tests stops it, so the land of the last branch closes.
- A single `rapid land` that lost a race for its version stops with dev
  unchanged: `rapid sync`, then land again.
