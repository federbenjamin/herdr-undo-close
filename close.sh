#!/usr/bin/env bash
# The close half (action `close`, ctrl+d): close whatever is in the focused pane the right way,
# and remember it first.
#   a program that takes ctrl+d itself ($passthrough_regex: shells, REPLs, agents, pagers,
#   editors)                                        -> send ctrl+d, it exits (or scrolls) itself
#   anything else (a file viewer, lazygit, a popup) -> herdr closes the pane
# Usage: close.sh [--dry-run] [pane_id]   (pane_id defaults to the focused pane)
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
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
  command -v python3 >/dev/null 2>&1 || return 1
  [ "$(uname)" != Darwin ] || xcode-select -p >/dev/null 2>&1 || return 1
  python3 - "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" <<'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(3)
s.connect(sys.argv[1])
s.sendall((json.dumps({"id": "undo-close", "method": "popup.close", "params": {}}) + "\n").encode())
r = json.loads(s.recv(65536).decode().splitlines()[0])
sys.exit(0 if "result" in r else 1)
PY
}
if [ "$dry" = 0 ] && popup_close 2>/dev/null; then exit 0; fi

# Pass the key through when the pane runs an agent or a program on the list; else close.
# Any failure while deciding falls back to passing the key through: ctrl+d must never do nothing.
decision=pass
agent=$("$herdr" pane get "$pane" 2>/dev/null | jq -r '.result.pane.agent // empty' 2>/dev/null || true)
if [ -z "$agent" ]; then
  names=$("$herdr" pane process-info --pane "$pane" 2>/dev/null \
    | jq -r '.result.process_info.foreground_processes[]? | (.argv0 // .argv[0] // "") | split("/") | last | ltrimstr("-")' 2>/dev/null || true)
  if [ -n "$names" ] && ! printf '%s\n' "$names" | grep -Eq "$passthrough_regex"; then
    decision=close
  fi
fi

if [ "$dry" = 1 ]; then
  echo "$pane: agent=${agent:-none} -> $decision"
  exit 0
fi
# Remember first: after the key the process may be gone. A snapshot failure never blocks the close.
bash "$here/remember.sh" snapshot "$pane" 2>/dev/null || true
case "$decision" in
  pass)  "$herdr" pane send-keys "$pane" ctrl+d >/dev/null ;;
  close) "$herdr" pane close "$pane" >/dev/null ;;
esac
# Detached: promote waits up to 2s for the pane to vanish, and the next ctrl+d must not queue
# behind it (Claude Code exits only on two presses within about a second).
(nohup bash "$here/remember.sh" promote "$pane" >/dev/null 2>&1 &)
