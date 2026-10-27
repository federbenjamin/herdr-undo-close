# Loaded by every test file (`load ../helpers/common`) and sourced by test/fixtures/capture.sh.
# Call `isolate` first in setup() or setup_file(): it gives the test its own HOME and a clean
# environment, so nothing in the caller's shell changes a result. It keeps only PATH (to find
# bash, jq, herdr), CI, UNDO_CLOSE_TEST_TMP, REPO_ROOT and bats's own variables; pins the locale
# to C.UTF-8; drops every alias; and drops every function that neither bats nor this repo defined (one the caller
# exported, or one the BASH_ENV that bats started with defined). That also removes
# HERDR_SOCKET_PATH, which a herdr pane exports and which wins over HOME: every `herdr` call
# then goes through test/helpers/herdr-guard; close.sh's popup check, which talks to the socket
# directly, connects only to HERDR_SOCKET_PATH, so no test may set HERDR_SOCKET_PATH.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export REPO_ROOT

isolate() {
  local v f src real extdebug
  real=$(command -v herdr || true)
  for v in $(compgen -e); do
    case "$v" in
      # Unsetting a locale variable in a running bash 5.3 can make it crash at its next
      # localized error message, so LC_ALL below overrides them instead.
      PATH|CI|UNDO_CLOSE_TEST_TMP|REPO_ROOT|BATS_*|PWD|OLDPWD|SHLVL) ;;
      LANG|LC_ALL|LC_COLLATE|LC_CTYPE|LC_MESSAGES|LC_NUMERIC|LC_TIME) ;;
      # A readonly variable (SHELLOPTS, BASHOPTS) cannot be unset, only kept from children.
      *) unset "$v" 2>/dev/null || export -n "${v?}" ;;
    esac
  done
  export LC_ALL=C.UTF-8
  unalias -a
  extdebug=$(shopt -p extdebug || true)
  shopt -s extdebug
  for f in $(compgen -A function); do
    read -r _ _ src < <(declare -F "$f")
    case "$src" in
      "${BATS_ROOT:-$REPO_ROOT}"/*|"${BATS_RUN_TMPDIR:-$REPO_ROOT}"/*|"$REPO_ROOT"/*) ;;
      # bats exports bats_readlinkf for its own child processes.
      environment) [[ $f == bats_* ]] || unset -f "$f" ;;
      *) unset -f "$f" ;;
    esac
  done
  $extdebug
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
