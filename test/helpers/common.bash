# Loaded by every test file (`load ../helpers/common`) and sourced by test/fixtures/capture.sh.
# Call `isolate` first in setup() or setup_file(): it gives the test its own HOME and removes
# every variable that could point a herdr call at the developer's own herdr (a herdr pane
# exports HERDR_SOCKET_PATH, which wins over HOME). Every `herdr` call then goes through
# test/helpers/herdr-guard; close.sh's popup check, which talks to the socket directly, connects
# only to HERDR_SOCKET_PATH, which is gone, so no test may set HERDR_SOCKET_PATH.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export REPO_ROOT

isolate() {
  local v real
  real=$(command -v herdr || true)
  for v in $(compgen -e); do
    case "$v" in HERDR_*|XDG_*|ZDOTDIR|BASH_ENV|ENV|CLAUDE_CONFIG_DIR|UNDO_CLOSE_CONFIG_DIR) unset "$v" ;; esac
  done
  # Short on purpose: herdr's socket path must fit sun_path (104 bytes on macOS).
  export UNDO_CLOSE_TEST_TMP=${UNDO_CLOSE_TEST_TMP:-/tmp}
  UNDO_CLOSE_TEST_HOME=$(mktemp -d "$UNDO_CLOSE_TEST_TMP/uc.XXXXXX")
  export UNDO_CLOSE_TEST_HOME HOME=$UNDO_CLOSE_TEST_HOME
  export UNDO_CLOSE_REAL_HERDR=$real
  export HERDR_BIN_PATH="$REPO_ROOT/test/helpers/herdr-guard"
  export HERDR_PLUGIN_STATE_DIR="$HOME/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
}

unisolate() {
  local refused=""
  [ -f "${UNDO_CLOSE_TEST_HOME:-}/guard-refusals" ] && refused=$(cat "$UNDO_CLOSE_TEST_HOME/guard-refusals")
  case "${UNDO_CLOSE_TEST_HOME:-}" in
    "$UNDO_CLOSE_TEST_TMP"/uc.??????) rm -rf -- "$UNDO_CLOSE_TEST_HOME" ;;
  esac
  if [ -n "$refused" ]; then
    echo "herdr-guard refused calls during this test:" >&2
    echo "$refused" >&2
    return 1
  fi
}
