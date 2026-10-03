#!/bin/bash
# Install n0d3x.agents: plugin + collectors + helpers, then validate.
# No network, no sudo, no hooks — plain file copies you can read first.
set -euo pipefail
cd "$(dirname "$0")"

PLUGIN_DIR="$HOME/.config/omarchy/plugins/n0d3x.agents"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$PLUGIN_DIR" "$BIN_DIR"
cp -a manifest.json Panel.qml Main.qml Agent.qml "$PLUGIN_DIR/"
rm -rf "$PLUGIN_DIR/assets"
cp -a assets "$PLUGIN_DIR/"
cp -a collectors/. "$BIN_DIR/"
cp -a bin/. "$BIN_DIR/"
chmod +x "$BIN_DIR"/omarchy-agent-usage-* "$BIN_DIR"/n0d3x-agents-*

omarchy plugin validate "$PLUGIN_DIR"
echo "Installed. Next:"
echo "  omarchy plugin disable omarchy.agents   # avoid IPC shadowing"
echo "  omarchy restart shell"
