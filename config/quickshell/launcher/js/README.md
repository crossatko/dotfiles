# Launcher logic (pure JS, QML `.pragma library`)

Import in QML: `import "launcher/js/Ranker.js" as Ranker` (Ranker imports Frecency.js itself).

## API
- `Ranker.rank(items, query, usage, now, opts)` -> `[{item, score}]`, sorted desc.
  opts: `limit` (50), `includeHidden` (false). Non-matches dropped for non-empty query.
  Item: `{id, name, subtitle?, keywords?[], aliases?[], kind, source, ...}`.
- `Frecency.frecency(entry, now)` -> number
- `Frecency.record(usage, id, query, now)` -> new usage (count++, times capped 10, terms capped 20)
- `Frecency.setPinned(usage, id, bool)`, `setHidden(usage, id, bool)` -> new usage
- `Frecency.prune(usage, now)` -> new usage without entries unused > 180 days (pinned/hidden kept)
- usage: `{[id]: {count, times:[ms], terms:{[q]:n}, pinned?, hidden?}}` (plain JSON, never mutated)

## Scoring
Per query token, best of: exact alias 1000, exact name 950, name prefix ~800,
alias prefix 750, word/camelCase prefix 600 (-10 per word index), acronym of
initials 550, substring 450, fuzzy subsequence 50..400 (consecutive +15,
boundary +12, gap penalty), keyword 250, subtitle 150.
Multi-word query: every token must match; text score = mean of token scores.
Final = text + 900 if `usage[id].terms[query]` exists + min(80, frecency/5).
Frecency = mean bucket weight of last <=10 launches (100 <=4d, 70 <=14d,
50 <=31d, 30 <=90d, else 10) * ln(1 + count).
Empty query: pinned (10000 + frecency), then used (1000 + frecency), then
the rest by name. Hidden items excluded unless `includeHidden`.

## Tests
`node --test config/quickshell/launcher/js/tests/*.test.js`
(tests/load.js loads the pragma files into a vm context; dev-time only.)
