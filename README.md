# n0d3x.agents

15-provider usage tracking for AI coding subscriptions on Omarchy:
rate-limit meters, credit balances, per-day and per-model token history —
plus a Manage sessions view (browse by date or project, fuzzy search,
resume in terminal, delete with confirm).

Built as a user-owned clone of the stock `omarchy.agents` shell plugin.
Same dashboard, same visual language, zero stock files touched.

## Layout

| Path | Installs to | What |
|---|---|---|
| `plugins/n0d3x.agents/` | `~/.config/omarchy/plugins/` | The shell plugin (panel, refresh chain, notifications) |
| `collectors/` | `~/.local/bin/` | 13 usage collectors, one per provider (+ hidden `sessions` sidecar) |
| `bin/` | `~/.local/bin/` | `n0d3x-agents-update` (extras refresh) · `n0d3x-agents-session` (resume/delete) |
| `docs/` | — | Project overview, stock-vs-clone comparison, batch build plans |

## Install

```bash
./install.sh
omarchy plugin disable omarchy.agents   # avoid IPC shadowing (stock stays installed)
omarchy restart shell
```
Tabs: Claude, Codex, Fireworks (stock collectors) + OpenCode, Antigravity,
Freebuff, Pi, Gemini, Crush, Copilot, Grok, Hermes, Cursor, Z.ai, Synthetic.
A tab appears only once its provider records real usage (or a working quota
API key, for Z.ai/Synthetic) — installing a CLI alone never creates one.

## Removal

```bash
omarchy plugin remove n0d3x.agents
rm -f ~/.local/bin/omarchy-agent-usage-* ~/.local/bin/n0d3x-agents-*
rm -f ~/.local/state/omarchy/agents/usage/{opencode,antigravity,freebuff,pi,gemini,crush,copilot,grok,hermes,cursor,zai,synthetic,sessions}.json
omarchy plugin enable omarchy.agents    # restore the stock widget
omarchy restart shell
```

## Dependencies

- Omarchy Quattro (shell, `omarchy` CLI) — the plugin host.
- `python3`, `jq`, `sqlite3` CLI semantics via python's stdlib only
  (collectors use the standard library; no pip packages).
- `notify-send` for limit-threshold toasts.
- Optional per provider: the agent CLIs themselves (`opencode`, `codex`,
  `pi`, `gemini`, `crush`, `copilot`, `cursor-agent`, `grok`, `hermes`),
  plus `ZAI_API_KEY` / `SYNTHETIC_API_KEY` (or matching opencode auth
  entries) for the two API-quota tabs. Missing tools degrade to dormant
  tabs, never errors.

## Docs

- `docs/PROJECT.md` — architecture, record contract, conventions, inventory
- `docs/COMPARISON.md` — stock vs clone, measured by diff
- `docs/batches/` — build plans for search/grouping, provider session
  wiring, and cost/burn-rate/notifications
