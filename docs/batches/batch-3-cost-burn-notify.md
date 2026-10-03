# Batch 3 — Cost tracking, burn-rate projection, limit notifications

Three independent features, one batch because they all read data that
already flows today. Implement in 3A → 3B → 3C order, verifying each.

## 3A. Cost tracking (data layer + display)

**Goal.** Per-session cost in the Manage view + a period total. Show it
only where the data exists; everywhere else the UI is byte-identical.

**Data (verify schemas live before coding — memory is not a source).**

- OpenCode: per-message `cost` exists in `message.data` JSON. Per-session
  cost = `SUM` over the session's messages. Do it as ONE `GROUP BY
  session_id` query in the sessions collector (not per-session queries —
  the DB is 120MB+). Round to cents. If a `session.cost` column exists by
  then, prefer it and note the switch.
- Hermes: `session_model_usage.estimated_cost_usd` / `actual_cost_usd`
  (prefer actual when `cost_status` says so; sum across the session's
  model rows). Windows from `first_seen`/`last_seen` stay as-is.
- Everyone else: no cost source → field absent, UI hides itself. No
  estimates, no faking.

**Contract change (additive only).** Session entries gain optional
`costUsd` (number, USD). Absent/zero = hidden. The record contract in the
README gets one appended line; nothing else changes shape.

**Display.**

- Session row meta line becomes `time · tokens · model · $X.XX` — cost
  segment appended only when `costUsd > 0`. Same dim caption style, no new
  colors.
- View header caption gains a period total: `"N sessions · $Y.YY"` for the
  currently listed set (respecting search filter from batch 1 — total what
  you see). Compute in QML by summing the displayed list; no collector
  round-trip.

**Verify.** Cost math checked against a COPY of `opencode.db` (never the
live DB — same discipline as the delete tests): collector sum vs direct
SQL `SUM`, must match to the cent. Hermes math reviewable by query once
sessions exist. Zero-cost providers render exactly as today.

## 3B. Burn-rate projection (panel math, no new data)

**Goal.** Under each LIMITS meter, one dim line answering "at this pace,
when does the window run out".

**Math (per limit window with known `resetsAt` and `percent`).**

- `span` = existing `windowSpanMs(label)` (already handles session/weekly/
  monthly shapes — reuse it, don't re-derive).
- `elapsed = span - remainingMs`, `remainingMs` from existing
  `resetMsFor()`.
- Guard: if `percent <= 0`, `remainingMs <= 0`, or `elapsed <= 0` → show
  nothing (a fresh window has no pace yet — saying so would be noise).
- `rate = percent / elapsed`; `projected = percent + rate * remainingMs`.
- Text: if `projected >= 1` → `"≈ full by reset"`; else
  `"≈ NN% by reset"` (round, no decimals). Prefix with the hourly pace
  when the span is ≥ 1h: `"MM%/h · …"`. Keep it to one short line in
  `Style.font.caption`, `root.dim`, under the existing "Resets in …" line
  inside `LimitRow`.

**Verify.** Sanity table by hand: 50% at half-window → ≈100%; 10% at
half-window → ≈20%; fresh window → hidden. Prepaid `balance` blocks are
out of scope (different semantics — depletion, not windows).

## 3C. Limit-threshold notification (one toast per window)

**Goal.** A desktop toast the first time any tracked window crosses 90%,
so a filling cap is noticed without staring at the bar.

**Mechanism.**

- In clone `Main.qml`: `property var notifiedWindows: ({})` mapping
  `"providerId::label" → resetsAt-string-notified-for`.
- Evaluation point: wherever `bindingWindow`-style "fullest window" logic
  already runs per provider (reuse, don't re-walk limits). Condition:
  `headline.percent >= 0.9` (same threshold as the existing `alarming`
  state — one threshold everywhere) AND stored reset differs from the
  window's current `resetsAt` → fire once, store the new stamp. A fresh
  `resetsAt` (window rolled over) naturally re-arms.
- Firing = a `Process` running
  `notify-send "Agents: <Provider> <Title> at NN%" "<reset line>"`.
  One-shot process per event; no daemon, no new dependencies
  (`notify-send` is already on the system).
- Default ON. Add a manifest toggle for opt-out: `defaults.notifyOnLimits:
  true` + matching `schema` bool entry + `setting("notifyOnLimits", true)`
  gate in `Main.qml`. Validate the manifest after editing.
- Scope: subscription windows only (`limits[]`). Prepaid balances already
  alarm visually via `balanceAlarming`; leave them out to keep the first
  version predictable.

**Verify.** Temporarily lower the threshold constant to `0.0` in a scratch
copy? No — never experiment in the live plugin. Instead: trigger with the
real Codex 720h window by… it sits at 8%, not fir-able. Test path: unit-ish
check of the latch logic by code review + a dry `notify-send` command by
hand to confirm toasts render. First real firing will be observed live;
the journal logs each fire (one `console.log` at fire time — the single
allowed log line, kept permanently for diagnosability).

## Batch exit criteria

- README record contract documents `costUsd`; inventory table gains cost
  availability per provider.
- All three features degrade to invisible when their data is absent
  (fresh clone on a new machine shows today's exact UI).
- Full pass: validate → restart → refresh → journal clean → Manage view on
  OpenCode shows costs, limit rows show pace lines, no toast spam (at most
  one per window per reset cycle).

## Completion notes (2026-10-03)

All three shipped, all verified:

- **Cost.** Sidecar adds `costUsd` (OpenCode `SUM(message.data.cost)`,
  Hermes actual-preferred). Live data is $0.00 everywhere (free-tier
  models) so cost lines correctly stay hidden; aggregation proven exact
  via nonzero injection on a DB copy (0.30 expected, 0.30 computed).
- **Burn-rate.** Pace line under each meter (live Codex window reads
  "≈ 18% by reset" — hand-verified math). Span travels in the limit
  record (`spanMs`, derived from the raw label, not the display title).
- **Notify.** Fired end-to-end on a scratch 95% record
  ("limit threshold crossed: codex::720h window 95%" + desktop toast);
  latch re-test (same-stamp rewrite) stayed silent; real 8% record
  restored afterwards. One operational lesson, twice learned: shell
  hot-reload sometimes runs stale `Main.qml` despite "reloading" logs —
  `omarchy restart shell` is the only trustworthy reload for logic
  changes. Manifest gains `notifyOnLimits` (On/Off enum, default On).
