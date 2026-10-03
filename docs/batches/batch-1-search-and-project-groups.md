# Batch 1 — Session search + Date/Project grouping (QML-only)

No collector, helper, or manifest changes. Everything happens in
`~/.config/omarchy/plugins/n0d3x.agents/Panel.qml` (clone only).

## 1A. Search field

**Goal.** Fuzzy-filter the sessions list by title as you type, vim-style.

**Steps.**

1. Check what text-input components exist: list
   `/usr/share/omarchy/shell/Ui/` (or wherever `qs.Ui` resolves) for
   `TextField`-like exports. If a styled one exists, use it with the same
   props pattern as `Button` (foreground/fontFamily/fontSize). If none,
   fall back to a bare QtQuick `TextField` styled manually
   (`color: root.foreground`, `font.family/pixelSize`, transparent
   background + bottom `Rectangle` border in `root.track` color).
2. Add state + helpers on root:
   - `property string sessionQuery: ""`
   - Extend `sessionGroups()`: skip sessions whose title does not contain
     the query (case-insensitive). When the query is non-empty, return ONE
     flat group (`{ date: "", items: [...] }`) instead of date groups —
     mixed-date results under date headers are confusing.
   - `groupLabel("")` must handle the flat case: return `"N results"`.
3. UI placement: a search row directly under the sessions header
   (magnifier glyph `` + field + ✕ clear button visible only when the
   query is non-empty). This matches the popover-search pattern (filter
   belongs to the list it filters, above it, full width).
4. Focus discipline (important — get this wrong and panel navigation breaks):
   - Pressing `/` with the sessions view open moves focus into the field.
     Add the `/` branch to the existing `onTextKey` handler next to
     `r`/`s`. Guard: only when `root.showingSessions` is true.
   - While the field has focus, single-letter shortcuts must NOT fire
     (typing "s" in the query must not reopen anything). Gate `onTextKey`
     branches on `searchField.activeFocus`: if the field is focused,
     only `Esc` handling applies — and Esc already closes the panel
     (`onCloseRequested`), which doubles as "leave search". Clearing is
     via the ✕ button (also clears focus back to `keyCatcher`).
   - Reset `sessionQuery = ""` inside the existing `closeSessions()` so a
     reopened view never inherits a stale filter.
5. Result count: when the query is non-empty, the flat group header shows
   `"N of M"` (filtered of total) — compute both in `sessionGroups()` or a
   tiny `sessionCounts()` helper reading the same filtered list.

**Verify.** Validate plugin; reload; open view; `/`, type 3 letters, list
shrinks live; ✕ clears; close/reopen resets; `h/l/r/Esc` still behave with
the field unfocused; no journal QML errors.

**Risks.** `qs.Ui` may not export a text field (→ manual styling fallback
above). `onTextKey` may not receive `/` if `PanelKeyCatcher` filters
punctuation — if so, attach `Keys.onPressed` handling for `/` (check how
the catcher forwards keys first; read its source in the shell before
writing code).

## 1B. Date / Project grouping toggle

**Goal.** A two-option segmented switch in the sessions header flipping the
list between date groups (current behavior) and project groups.

**Steps.**

1. State: `property string sessionGroupBy: "date"` (`"date" | "project"`),
   reset to `"date"` in `closeSessions()`.
2. UI: reuse the provider-switch pattern already in the file — a `Row` of
   two bordered `Button`s (`Date`, `Project`) with the `selected` prop
   bound to the state, placed under the sessions header (above the search
   row from 1A). Same component, same props, zero new visual language.
3. Grouping logic: generalize `sessionGroups()` on the mode:
   - `date`: unchanged (newest day first).
   - `project`: key = session `directory`, label = last path segment
     (basename); tie-break/full path goes into the row meta line so
     same-named projects stay distinguishable. Sort groups by most recent
     session timestamp descending (use `timestamp`, not name).
   - Sessions with empty directory fall into an `"Elsewhere"` group, last.
   - `groupLabel()` gains a project branch: return the basename as-is
     (no Today/Yesterday logic).
4. Search (1A) composes with both modes: non-empty query still flattens to
   one `"N of M"` group regardless of the toggle. Implement the filter
   FIRST inside `sessionGroups()`, then branch on mode.
5. Row meta line (`sessionMeta()`): unchanged in date mode. In project
   mode, the project is the group — swap the model token segment order to
   `time · tokens · model` (already the case) and rely on the group header
   for location; no change needed. (If headers feel ambiguous during
   testing, append the full path as a dim second line — decide at review.)

**Verify.** Toggle regroups instantly on both tabs; project groups ordered
by recency; empty-directory sessions land in `Elsewhere`; search flattens
correctly in both modes; state resets on close/provider switch.

**Risks.** None structural. Only judgment call is basename-vs-full-path in
headers — default to basename, full path stays one glance away in the
session's own data if needed later.

## Batch exit criteria

- `omarchy plugin validate` passes.
- Shell reloads with zero QML errors/warnings for `n0d3x.agents`.
- Dashboard untouched (diff `Panel.qml` against stock shows only
  sessions-view additions, as before).
- Keyboard map after batch 1: `r` refresh, `s` sessions, `/` search focus,
  `h/l` providers, `j/k` scroll, `Enter` refresh, `Esc` close.
