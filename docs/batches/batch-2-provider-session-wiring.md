# Batch 2 — Session wiring for the 7 dormant local providers

Give Pi, Gemini, Crush, Copilot, Grok, Hermes, and Cursor the same Manage
view OpenCode/Codex have: session list → resume → delete. Z.ai/Synthetic
are API-only (no local sessions) and stay out of scope permanently.

Pattern per provider (same three pieces every time):

1. **Scan** — new function in `~/.local/bin/omarchy-agent-usage-sessions`
   emitting the standard session fields
   `{id,title,date,timestamp,tokens,model,directory}`, newest 30.
2. **Resume/delete** — new branches in `~/.local/bin/n0d3x-agents-session`
   with the same guards as existing ones (id allow-list patterns,
   `realpath` prefix confinement for files, parameterized SQL).
3. **Gate** — add the provider id to `sessionsManaged()` in the clone's
   `Panel.qml`. Nothing else in the panel changes.

## Provider work orders (verify resume flags with `<cli> --help` first —
CLIs drift; never trust memory over the installed binary)

| Provider | Session source (already known) | Resume (verify!) | Delete |
|---|---|---|---|
| pi | `~/.pi` + `~/.omp` JSONL assistant turns | check `pi --help` for resume/continue flag; fallback: terminal in session dir running `pi` | rm transcript file (prefix-confined) |
| gemini | `~/.gemini/tmp/*/chats/*.json` | check `gemini --help` (`/resume` exists in-TUI; need CLI flag) | rm checkpoint file |
| crush | `~/.crush/crush.db` (introspect schema at runtime like the crush collector does) | `crush session …` verbs exist upstream — verify exact resume spelling | SQL DELETE by session key (schema read live; wrap in transaction) |
| copilot | `~/.copilot/session-state/<id>/events.jsonl` (legacy flat `*.jsonl`), `$COPILOT_HOME` | verify `copilot --resume` / `--continue` spelling | rm session dir (must contain `events.jsonl` — refuse otherwise) |
| grok | `~/.grok/sessions/<cwd>/<id>/` (`summary.json` + `signals.json`), `$GROK_HOME` | `grok --resume <id>` (documented upstream) | rm session dir (must contain `summary.json`) |
| hermes | `~/.hermes/state.db` (`sessions` + `session_model_usage` — schema already mapped) | `hermes --resume` / `--continue` (flags exist) | SQL across `messages` → `session_model_usage` → `sessions` by id, one transaction |
| cursor | `~/.cursor/projects/*/agent-transcripts/*/*.jsonl`, `$CURSOR_CONFIG_DIR` | `cursor-agent --resume <id>` (documented upstream) | rm transcript dir (must contain the `<id>.jsonl`) |

Session-id scheme per provider (keys the helper parses back — keep the
existing convention: `opencode:<sid>` stays, native/file-backed use
`file:<absolute-path>`, DB-backed use the plain row id with a provider
prefix only where ambiguous).

## Order of implementation (easiest verification first)

1. grok, cursor — resume syntax documented upstream; verify locally.
2. hermes — schema fully mapped, DB present (0 sessions); parser testable
   the moment one session exists. SQL delete reviewable today.
3. copilot, pi, gemini — file-based; formats best-effort with graceful
   skip (same discipline as their collectors).
4. crush — DB absent locally: implement against the documented location
   with runtime schema introspection, mark **field-unverified** until a
   first `crush` run creates `crush.db`.

## Verification rules (strict — deletes are destructive)

- Every collector change: valid JSON, correct dormant record when the tool
  was never run (no tab, no Manage button change).
- Every helper branch: refusal cases first (bad id, outside-roots path,
  missing file/row) — all must exit non-zero with zero side effects.
- Live resume/delete tested ONLY where real sessions exist. Providers with
  no local data ship as **implemented, field-unverified** — noted inline
  in code comments AND in the README inventory table (flip the Sessions
  column per provider as each gets verified).
- After wiring: `omarchy plugin validate`, shell restart, journal clean,
  `omarchy-shell omarchy.agents refresh` regenerates all records including
  extended `sessions.json`.
- Spot-check the Manage view on any tab with sessions: rows render,
  Resume opens a terminal in the right directory, Delete→confirm→row gone
  after refresh.

## Risks

- Unverifiable parsers (crush, and any provider still never-run): mitigate
  with conservative parsing (skip don't crash), empty-state fallbacks, and
  explicit `field-unverified` marking. Never fake confidence in the docs.
- CLI resume flags differing from docs: the `--help` verification step is
  mandatory per provider, not optional.
- Scope creep into cost fields: session entries gain `costUsd` ONLY in
  batch 3. Batch 2 touches the exact current field set.

## Completion notes (2026-10-03)

Implemented as planned with two deviations:

- **Gemini resume is a project-terminal fallback**, not a true resume:
  upstream `--resume` takes `latest|N` ( shifting list indices), not a
  stable session id, so the helper opens the session's project directory
  in a terminal on plain `gemini` for the in-TUI `/resume` picker.
- **Crush ships field-unverified** (no local `crush.db` exists): scan and
  delete were proven against a scratch DB with a sessions-like table, and
  the code refuses on any unrecognized schema.

Verified: sidecar emits all 9 lists; all 15 refusal cases exit non-zero
with no side effects; scratch scan+delete cycles passed for pi, gemini,
copilot, grok, cursor, crush; hermes SQL proven on a temp DB; fixtures
removed afterwards; `omarchy plugin validate` passes; shell reloads with
zero QML errors; full refresh regenerates all 16 records.
