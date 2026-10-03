# n0d3x.agents — project overview

Extended usage-tracking widgets for AI coding subscriptions on Omarchy,
built as a user-owned clone of the stock `omarchy.agents` shell plugin.

## What it is

One bar icon + one panel per AI coding subscription: rate-limit meters,
credit balances, TOKENS BY DAY, TOKENS BY MODEL — plus a **Manage sessions**
view (browse by date, resume in terminal, delete with confirm) for providers
with local session stores.

Stock Omarchy ships 3 providers (Claude, Codex, Fireworks). This project
extends the same panel to **15 providers** without touching stock style or
stock files.

## Where things live (do not move these)

| What | Path |
|---|---|
| The plugin (clone) | `~/.config/omarchy/plugins/n0d3x.agents/` (`Panel.qml`, `Main.qml`, `Agent.qml`, `manifest.json`, `assets/`) |
| Stock original (read-only, never edit) | `/usr/share/omarchy/shell/plugins/agents/` + `/usr/bin/omarchy-agent-usage-*` |
| Our collectors | `~/.local/bin/omarchy-agent-usage-<id>` (one file per provider, executable python3) |
| Refresh wrapper | `~/.local/bin/n0d3x-agents-update` (same CLI contract as stock update) |
| Resume/delete helper | `~/.local/bin/n0d3x-agents-session` (`resume` / `delete` subcommands) |
| Usage records (generated, never hand-edit) | `~/.local/state/omarchy/agents/usage/<id>.json` |
| Scan caches | `~/.cache/omarchy/agent-usage/` |
| Bar placement | `~/.config/omarchy/shell.json` (center section, id `n0d3x.agents`) |

## Architecture (the rules everything follows)

1. **Record contract.** Every collector prints one JSON record:
   `id, name, updatedAt, ready, hasLocalStats, hasPromptStats, today*,
   recentDays[7], total*, activeDays/Dates, modelUsage{model: {input, output,
   cacheRead, cacheWrite}}, limits[{label, percent, resetsAt}], tierLabel,
   usageStatusText, authHelpText`, optional `balance, scope`.
   Session entries (sidecar `sessions` record) carry
   `{id,title,date,timestamp,tokens,model,directory}` plus optional
   `costUsd` (present only when metering reported >$0.005 — OpenCode
   message costs, Hermes actual/estimated).
2. **A tab appears only with data.** `providerHasData()` in `Main.qml`:
   any prompts/sessions/days > 0, or non-empty `limits`, or a `balance`.
   Zero everywhere = no tab. Installing a CLI alone never creates a tab.
3. **Hidden sidecar records never become tabs.** `sessions` (id `sessions`,
   all-zero stats) carries `sessionsByProvider`; `Main.qml sessionLists`
   merges each list into its tab. Same trick is reusable for future metadata.
4. **Refresh chain.** Clone `Main.qml runUpdate()` runs stock
   `omarchy-agent-usage-update` first, then `n0d3x-agents-update` with the
   same args (`--force/--limits-only/--except` + agent filter), then rescans.
   Stock plugin stays disabled so its IPC handler can't shadow the clone's
   (`omarchy.agents` target is kept for muscle-memory compatibility).
5. **Panel is provider-generic.** `Panel.qml` never hardcodes providers (only
   `sessionsManaged()` gates the Manage view per tab). New provider = new
   collector + manifest entry + icons. No panel changes.
6. **Destructive ops are guarded.** The helper validates session ids
   (`ses_` pattern), confines file deletes to known session roots via
   `realpath` prefix checks, uses parameterized SQL, and the UI always
   confirms inline first.
7. **Never edit `/usr/share/omarchy`.** It is package-owned; updates wipe it.

## Provider inventory (15)

| Tab | Source | Limits meter | Sessions view |
|---|---|---|---|
| claude (stock) | CLI + OAuth endpoint | yes (5h + weekly) | no |
| codex (stock) | native files + opencode/openai + pi | yes (RPC windows) | **yes** (sidecar) |
| fireworks (stock) | billing API / estimate | balance ledger | no |
| opencode | `opencode.db` (all providers) | no (no endpoint) | **yes** |
| antigravity | transcripts / state.vscdb | no | no (dormant, none installed) |
| freebuff | session files | no | no (dormant) |
| pi | `~/.pi`, `~/.omp` transcripts | no | **yes** (verified with scratch transcript 2026-10-03; dormant, dirs empty) |
| gemini | `~/.gemini/tmp/*/chats` | no | **yes** (verified with scratch checkpoint 2026-10-03; dormant. Resume = project terminal fallback — upstream resume is index-based, not addressable) |
| crush | `~/.crush/crush.db` (introspected) | no | **yes** (scan+delete verified against scratch DB 2026-10-03; **field-unverified** — no real sessions yet) |
| copilot | `~/.copilot/session-state/*/events.jsonl` (+ `session-store.db` fallback), `$COPILOT_HOME` | no | **yes** (verified with scratch session incl. `workspace.yaml` cwd 2026-10-03; dormant) |
| grok | `~/.grok/sessions/*/*/summary.json` + `signals.json`, `$GROK_HOME` | no | **yes** (verified with scratch session 2026-10-03; dormant) |
| hermes | `~/.hermes/state.db` (`sessions` + `session_model_usage`) | no | **yes** (SQL verified on temp DB 2026-10-03; live DB has 0 sessions) |
| cursor | `~/.cursor/projects/*/agent-transcripts/*/*.jsonl`, `$CURSOR_CONFIG_DIR` | no | **yes** (verified with scratch transcript 2026-10-03; dormant) |
| zai | `api.z.ai` quota monitor (`ZAI_API_KEY` / opencode auth), scope `account` | yes (5h, 7d, search) | no (API-only, nothing local) |
| synthetic | `api.synthetic.new/v2/quotas` (`SYNTHETIC_API_KEY` / opencode auth), scope `account` | yes (5h, weekly, search) | no (API-only, nothing local) |

Live data today: OpenCode (~2.8k prompts), Codex limits only (native file
was cleaned; tab survives on the 720h window). Everything else dormant.

## Conventions for new code

- Collectors: `#!/usr/bin/python3`, `omarchy:` header comments, `--force` /
  `--limits-only` flags, scan cache under `~/.cache/omarchy/agent-usage/`
  with 20s normal / 900s limits-only reuse, never crash (degrade to a valid
  dormant record), 15s API timeouts, no redirect-following with credentials,
  HTTPS-only endpoints.
- QML: reuse `root.foreground/dim/urgent`, `Style.font.*`,
  `Style.spacing.*`, bordered `Button`s; popover-friendly inline confirms,
  never modal dialogs; keyboard shortcuts single letters (`r` refresh,
  `s` sessions).
- Icons: `assets/<id>.svg` (light-on-dark, `#fff`) + `assets/<id>-light.svg`
  (`#111`), 24×24, same pattern as stock `codex.svg`/`codex-light.svg`.
- After any plugin edit: `omarchy plugin validate`, shell hot-reloads on
  save (watch the journal for QML errors), `omarchy restart shell` when in
  doubt. After config/collector changes: quit + restart opencode-style —
  here, restart the shell.

## Roadmap

Batch plans live next to this file, in execution order:

1. `batch-1-search-and-project-groups.md` — QML-only: session search + Date/Project grouping toggle.
2. `batch-2-provider-session-wiring.md` — session scans + resume/delete for the 7 dormant local providers.
3. `batch-3-cost-burn-notify.md` — cost tracking, burn-rate projection, limit-threshold notifications.
