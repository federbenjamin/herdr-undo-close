#!/usr/bin/env bash
# Prints one flat entry (entry.jq: the snapshot contract reopen.sh reads) built from the raw herdr
# replies remember.sh saved in <dir>: the replies the loop below reads, a missing one read as
# empty. The one place the entry.jq command is written; remember.sh and the tests both run it.
# Usage: build_entry.sh <dir>
set -euo pipefail
dir=${1:?usage: build_entry.sh <dir>}
here=$(cd "$(dirname "$0")" && pwd)
args=()
for r in pane layout procs tab workspace agent plugin; do
  f="$dir/$r.json"
  [ -e "$f" ] || f=/dev/null
  args+=(--slurpfile "$r" "$f")
done
exec jq -n -L "$here" -f "$here/entry.jq" "${args[@]}"
