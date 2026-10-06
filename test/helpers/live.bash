# A real headless herdr for one test file, under the HOME `isolate` made. Sourced by the live
# tests and by test/fixtures/capture.sh, so plain bash: each function returns non-zero with a
# message on stderr instead of using bats helpers.

h() { "$HERDR_BIN_PATH" "$@"; }

# poll <tries> <seconds> <cmd...>: runs <cmd> until it succeeds, up to <tries> times, <seconds>
# apart. Prints nothing; a check that needs a pipe is a function.
poll() {
  local tries=$1 pause=$2 i; shift 2
  for ((i = 1; i <= tries; i++)); do
    "$@" >/dev/null 2>&1 && return 0
    [ "$i" -eq "$tries" ] || sleep "$pause"
  done
  return 1
}

# fg_procs <pane>: herdr's process-info reply for the pane; fails when the call does.
fg_procs() { h pane process-info --pane "$1"; }

server_running() { h status server 2>/dev/null | grep -q '^status: running'; }

# Sets out (stop_server's), the last answer, for the failure message.
server_stopped() { out=$(h status server 2>&1) && grep -qx 'status: not running' <<<"$out"; }

# Starts `herdr server`, waits until it answers, and checks its socket is under the test HOME
# (both sides resolved: on macOS /tmp is a link to /private/tmp).
start_server() {
  local sock home_real
  (nohup "$HERDR_BIN_PATH" server > "$HOME/server.log" 2>&1 &)
  poll 40 0.25 server_running || {
    echo "start_server: herdr server did not answer; its log:" >&2
    cat "$HOME/server.log" >&2
    return 1
  }
  sock=$(h status server 2>/dev/null | sed -n 's/^socket: //p')
  [ -n "$sock" ] || { echo "start_server: status server names no socket" >&2; return 1; }
  home_real=$(cd -P "$HOME" && pwd)
  case "$(cd -P "$(dirname "$sock")" && pwd)/" in
    "$home_real"/*) ;;
    *) echo "start_server: socket $sock is not under the test HOME $HOME" >&2; return 1 ;;
  esac
}

# Stops the server and waits until `status server` answers "not running", so the test HOME can be
# removed. A failing `status` call is not an answer, so it never counts as stopped.
stop_server() {
  local out=""
  h server stop >/dev/null 2>&1 || true
  poll 40 0.25 server_stopped && return 0
  echo "stop_server: herdr server not confirmed stopped; status server said: $out" >&2
  return 1
}

# link_plugin <dir> <plugin id> <pane id> <placement> <command toml array> writes a one-pane
# manifest into <dir> and links it as a local plugin of the test server.
link_plugin() {
  local dir=$1 id=$2 pane=$3 placement=$4 command=$5
  mkdir -p "$dir" || return 1
  cat > "$dir/herdr-plugin.toml" <<TOML || return 1
id = "$id"
name = "$id"
version = "0.1.0"
min_herdr_version = "0.9.0"
platforms = ["macos", "linux"]

[[panes]]
id = "$pane"
title = "$pane"
placement = "$placement"
command = $command
TOML
  h plugin link "$dir"
}
