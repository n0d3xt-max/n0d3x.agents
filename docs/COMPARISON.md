# n0d3x.agents vs stock omarchy.agents — differences

Clone: `~/.config/omarchy/plugins/n0d3x.agents/` (id `n0d3x.agents`,
"My Agents"). Stock: `/usr/share/omarchy/shell/plugins/agents/` (read-only,
never edited). Measured 2026-10-03 by direct diff.

## At a glance

| | Stock `omarchy.agents` | `n0d3x.agents` |
|---|---|---|
| Provider tabs | 3 (Claude, Codex, Fireworks) | 15 (+ OpenCode, Antigravity, Freebuff, Pi, Gemini, Crush, Copilot, Grok, Hermes, Cursor, Z.ai, Synthetic) |
| Settings keys | 5 (`refreshIntervalSec`, sync ×4) | 6 (+ `notifyOnLimits` On/Off) |
| Manage sessions view | none | date/project grouped list + resume + delete (9 providers) |
| Session search | none | `/`-focused fuzzy filter with `N of M` header |
| Cost display | balance ledger only (Fireworks) | per-session cost + view total wherever metering exists |
| Limit pace | reset countdown only | + burn-rate projection line |
| Limit alerts | red highlight ≥90% | + one desktop toast per window (latched on reset stamp) |
| Icons | 4 files | 28 files (same `.svg` + `-light.svg` convention) |
| Helper scripts | 0 | 15 files in `~/.local/bin` (13 collectors + update wrapper + session helper) |
| `Panel.qml` delta | — | +577 / −5 lines |
| `Main.qml` delta | — | +123 / −1 lines |
| `Agent.qml` | — | identical, untouched |

## What is identical (deliberately)

- The entire dashboard: hero, provider switch chips, status card, LIMITS
  meters, TOKENS BY DAY chart, TOKENS BY MODEL rows, footer. Same
  components, same spacing, same colors — `Meter`, `DayRow`, `ModelRow`
  untouched; `LimitRow` gained one pace line under the existing reset line.
- The record contract: every new collector emits the stock JSON shape
  (only additive fields: `spanMs` in limits, `sessionsByProvider` in the
  hidden sidecar, optional `costUsd` in session entries).
- Tab admission rule: a tab appears only with real numbers. Zero-data
  providers stay hidden; installing a CLI alone never creates a tab.
- Sync/merge logic, IPC target (`omarchy.agents`), bar glyph, keyboard map
  (`h/l/j/k/r/Enter/Esc/Tab`) — all preserved. Two keys added: `s`
  (sessions), `/` (search focus).

## What changed, file by file

**`manifest.json`** — new `id`/`name`/`displayName`, broader description,
12 providers added to `defaults.providers` (all enabled), one new setting
(`notifyOnLimits`, On/Off enum mirroring `syncMode`, default On),
`omarchy.clonedFrom: omarchy.agents` (added automatically by the clone
command, routes the stock IPC target to this copy).

**`Main.qml` (+123/−1)** — three additive blocks, stock flow untouched:
1. Extras refresh chain: after stock `omarchy-agent-usage-update` exits,
   `n0d3x-agents-update` reruns with identical args
   (`--force/--limits-only/--except`/filters), then rescan.
2. Session merge: the hidden `sessions` record (all-zero stats, never a
   tab) carries `sessionsByProvider`; `sessionLists` exposes it and each
   tab's display object gains its `recentSessions` list. Local-only, never
   synced.
3. Threshold notify: on every record change, each enabled tab's fullest
   window ≥90% fires one `notify-send`, latched per reset stamp (a new
   cycle re-arms; a shell restart may repeat a still-hot window once).

**`Panel.qml` (+577/−5)** — dashboard code paths unchanged; additions:
footer "Manage sessions" button (standard popover footer-action pattern);
sessions sub-view (‹ Back header, Date/Project segmented toggle reusing the
provider-switch pattern, search row with `qs.Ui TextField` + `PanelKeyCatcher
blocked`-while-typing, Today/Yesterday/date groups, per-row Resume/Delete
with inline confirm instead of a modal); `limitWindow` records now carry
`spanMs` (parsed from the raw label, not the display title) for the pace
line; session meta + view caption show cost only when >$0.005.

**New executables (15, all `~/.local/bin/`)** — 13 collectors
(`omarchy-agent-usage-<opencode, antigravity, freebuff, pi, gemini, crush,
copilot, grok, hermes, cursor, zai, synthetic, sessions>`), each with the
stock CLI contract (`--force/--limits-only`), scan caches (20s/900s reuse),
and graceful dormant records; `n0d3x-agents-update` (extras wrapper, same
contract as stock update); `n0d3x-agents-session` (`resume`/`delete` with
id allow-lists, `realpath` confinement, parameterized SQL, inline-confirm
upstream in the UI).

**Operational difference.** Stock `omarchy.agents` is explicitly disabled
so its IPC handler can't shadow the clone's (both register the
`omarchy.agents` target; the loser logs "will not be used"). Bar shows only
`n0d3x.agents`. After logic edits to `Main.qml`, `omarchy restart shell`
is required — hot-reload has been observed running stale code despite
"reloading" logs.

## Live state (2026-10-03)

Tabs with data: OpenCode (~2.8k prompts, full session management), Codex
(limits only — its native session file was cleaned; tab survives on the
720h window). The other 10 collectors refresh every cycle and stay hidden
until first use. Z.ai/Synthetic appear as soon as their API keys work
(quota limits count as data). Session wiring verified end-to-end (scratch
scan+delete cycles) for pi, gemini, crush, copilot, grok, hermes, cursor;
crush parsers remain field-unverified (no real `crush.db` on disk yet).
