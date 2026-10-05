#!/usr/bin/env bash
# Prints one flat entry (entry.jq: the snapshot contract reopen.sh reads) built from the raw herdr
# replies remember.sh saved in <dir>: pane.json, layout.json, procs.json, tab.json,
# workspace.json, agent.json (absent or empty when the pane held no agent), and plugin.json
# (absent or {} when no plugin owns the pane). The one place the entry.jq command is written;
# remember.sh and the tests both run it.
# Usage: build_entry.sh <dir>
set -euo pipefail
dir=${1:?usage: build_entry.sh <dir>}
here=$(cd "$(dirname "$0")" && pwd)
agent="$dir/agent.json"
[ -e "$agent" ] || agent=/dev/null
plugin="$dir/plugin.json"
[ -e "$plugin" ] || plugin=/dev/null
exec jq -n -f "$here/entry.jq" --slurpfile pane "$dir/pane.json" --slurpfile layout "$dir/layout.json" \
  --slurpfile procs "$dir/procs.json" --slurpfile tab "$dir/tab.json" --slurpfile ws "$dir/workspace.json" \
  --slurpfile agent "$agent" --slurpfile plugin "$plugin"
