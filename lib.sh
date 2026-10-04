# Shared by close.sh, remember.sh, reopen.sh and setup.sh. Source it; never run it.
# Sets: herdr, plugin, here, state; loads the settings; defines notify, fail, valid_id.
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
_config_dir=$("$herdr" plugin config-dir "$plugin" 2>/dev/null || true)
# shellcheck disable=SC1091
[ -n "$_config_dir" ] && [ -f "$_config_dir/config" ] && . "$_config_dir/config"
unset _config_dir

# An action runs on the server with no terminal: stdout goes to `herdr plugin log`, and a
# notification goes to the screen for setups that have them on.
notify() { echo "$2"; "$herdr" notification show "$1" --body "$2" --sound none >/dev/null 2>&1 || true; }
fail() { echo "$2" >&2; "$herdr" notification show "$1" --body "$2" --sound none >/dev/null 2>&1 || true; exit 1; }

# A herdr id (w3:pB) or an entry name built from one: safe to put in a path.
valid_id() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9:_.-]+$'; }
