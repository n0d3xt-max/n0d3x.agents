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

## Docs

- `docs/PROJECT.md` — architecture, record contract, conventions, inventory
- `docs/COMPARISON.md` — stock vs clone, measured by diff
- `docs/batches/` — build plans for search/grouping, provider session
  wiring, and cost/burn-rate/notifications
