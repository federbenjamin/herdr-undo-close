# Shared by close.sh, remember.sh, reopen.sh and setup.sh. Source it; never run it.
# Sets: herdr, plugin, here, state; loads the settings; defines notify, fail, valid_id, gone,
# herdr_error.
set -euo pipefail
umask 077   # everything the plugin writes (snapshots hold scrollback) is owner-only

herdr="${HERDR_BIN_PATH:-herdr}"
plugin="${HERDR_PLUGIN_ID:-herdr-undo-close}"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034  # state is read by the scripts that source this file
state="${HERDR_PLUGIN_STATE_DIR:-}"

# Settings: the defaults in config.example, then the user's config (README: Configuration).
# shellcheck source=config.example
. "$here/config.example"
# Exported, so close.sh's children (snapshot, promote) do not ask herdr again.
if [ -z "${UNDO_CLOSE_CONFIG_DIR+set}" ]; then
  UNDO_CLOSE_CONFIG_DIR=$("$herdr" plugin config-dir "$plugin" 2>/dev/null || true)
  export UNDO_CLOSE_CONFIG_DIR
fi
# shellcheck disable=SC1091
[ -n "$UNDO_CLOSE_CONFIG_DIR" ] && [ -f "$UNDO_CLOSE_CONFIG_DIR/config" ] && . "$UNDO_CLOSE_CONFIG_DIR/config"

# An action runs on the server with no terminal: stdout goes to `herdr plugin log`, and a
# notification goes to the screen for setups that have them on.
notify() { echo "$2"; "$herdr" notification show "$1" --body "$2" --sound none >/dev/null 2>&1 || true; }
fail() { notify "$1" "$2" >&2; exit 1; }

# A herdr id (w3:pB) or an entry name built from one: safe to put in a path.
valid_id() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9:_.-]+$'; }

# gone <pane|tab|workspace> <id>: herdr itself answers <kind>_not_found (its error JSON goes to
# stderr). Any other failure (a dead server, a timeout, no JSON) is not gone.
gone() {
  local err
  if err=$("$herdr" "$1" get "$2" 2>&1 >/dev/null); then return 1; fi
  printf '%s' "$err" | jq -e --arg c "$1_not_found" '.error.code == $c' >/dev/null 2>&1
}

# herdr_error <stderr of a failed herdr call>: sets code (herdr's error code; empty when there is
# none or it is not id-shaped) and why (code and message, control characters blanked). A log
# line written on a routine close names code only, since a message can hold a path; a failure
# the user pressed a key for reports why.
herdr_error() {
  code=$(printf '%s' "$1" | jq -r '.error.code // empty' 2>/dev/null || true)
  valid_id "$code" || code=""
  if [ -z "$code" ]; then why="herdr gave no error code"; return 0; fi
  why=$(printf '%s' "$1" | jq -r '.error | "\(.code)\(if .message then ": " + .message else "" end)" | gsub("[[:cntrl:]]"; " ")' 2>/dev/null || true)
  why=${why:-$code}
}
