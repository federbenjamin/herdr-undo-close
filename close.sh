#!/usr/bin/env bash
# The close half (action `close`, ctrl+d): close whatever is in the focused pane the right way,
# and remember it first. Decided from the snapshot remember.sh takes:
#   a plugin pane                                   -> herdr closes the pane
#   an agent, or a program that takes ctrl+d itself
#   ($passthrough_regex: shells, REPLs, pagers,
#   editors)                                        -> send ctrl+d, it exits (or scrolls) itself
#   anything else (a file viewer, lazygit, a popup) -> herdr closes the pane
# A snapshot that fails passes the key through: ctrl+d must never do nothing.
# Usage: close.sh [pane_id]   (pane_id defaults to the focused pane)
. "$(cd "$(dirname "$0")" && pwd)/internal/lib.sh"
# shellcheck source=internal/stack.sh
. "$here/internal/stack.sh"

pane="${1:-}"
if [ -z "$pane" ]; then
  pane=$(printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)
  pane=${pane:-${HERDR_PANE_ID:-}}
fi
[ -n "$pane" ] || fail "undo-close" "No focused pane to close."

# A popup (a plugin pane with placement = "popup") is session-modal, has no pane id, and closes
# only through the API's popup.close, which has no CLI. Try it first: success means a popup was
# up and is now gone; otherwise fall through to the focused pane. Needs python3; on a Mac
# without the developer tools the python3 stub would open an install dialog, so skip it there.
popup_close() {
  [ -n "${HERDR_SOCKET_PATH:-}" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  [ "$(uname)" != Darwin ] || xcode-select -p >/dev/null 2>&1 || return 1
  python3 - "$HERDR_SOCKET_PATH" <<'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(3)
s.connect(sys.argv[1])
s.sendall((json.dumps({"id": "undo-close", "method": "popup.close", "params": {}}) + "\n").encode())
r = json.loads(s.recv(65536).decode().splitlines()[0])
sys.exit(0 if "result" in r else 1)
PY
}
if popup_close 2>/dev/null; then exit 0; fi

# Remember first: after the key the process may be gone.
decision=pass
dir=$(stack_staging "$pane")
if bash "$here/internal/remember.sh" snapshot "$pane" 2>/dev/null && [ -s "$dir/pane.json" ]; then
  if jq -e '.result.plugin_pane != null' "$dir/plugin.json" >/dev/null 2>&1; then
    decision=close
  elif [ -z "$(jq -r '.result.pane.agent // empty' "$dir/pane.json" 2>/dev/null || true)" ]; then
    names=$(jq -L "$here/internal" -r 'include "names"; .result.process_info.foreground_processes[]? | pname' "$dir/procs.json" 2>/dev/null || true)
    if [ -n "$names" ] && ! printf '%s\n' "$names" | grep -Eq "$passthrough_regex"; then
      decision=close
    fi
  fi
else
  echo "close: snapshot of $pane failed; ctrl+d passed through"
fi

case "$decision" in
  pass)  "$herdr" pane send-keys "$pane" ctrl+d >/dev/null ;;
  close) "$herdr" pane close "$pane" >/dev/null ;;
esac
# Detached: promote waits up to 2s for the pane to vanish, and the next ctrl+d must not queue
# behind it (Claude Code exits only on two presses within about a second).
(nohup bash "$here/internal/remember.sh" promote "$pane" >/dev/null 2>&1 &)
