# Shared by the test/live files: one herdr server per file under the HOME `isolate` made, its
# pane shell (bash or zsh, login) reading a test profile that holds the plugin's hook, and
# small waits over herdr's own polling. Every herdr call goes through "$HERDR_BIN_PATH".
bats_require_minimum_version 1.5.0
load ../helpers/common
load ../helpers/live

# Read by the .bats files. PROMPT_MARK is the prompt every test pane shows (`wait-output` trims
# trailing spaces, so it has none); REOPEN_MARK is the line reopen_entry.sh prints.
# shellcheck disable=SC2034
PROMPT_MARK='uc$' REOPEN_MARK='reopened by undo-close'

# live_setup_file bash|zsh: isolate, write the herdr config and the shell profile, start the
# server (it checks the socket is under the test HOME), then install the hook with setup.sh.
live_setup_file() {
  local shell_bin
  shell_bin=$(command -v "$1") || return 1
  isolate
  # macOS /bin/bash otherwise prints its zsh notice in every pane.
  export BASH_SILENCE_DEPRECATION_WARNING=1
  mkdir -p "$HOME/.config/herdr"
  printf '[terminal]\ndefault_shell = "%s"\nshell_mode = "login"\n' "$shell_bin" > "$HOME/.config/herdr/config.toml"
  case "$1" in
    bash) printf "PS1='%s '\n" "$PROMPT_MARK" > "$HOME/.bash_profile" ;;
    # .zshrc: macOS /etc/zshrc runs after .zprofile and would reset PS1. .zshenv: Ubuntu's
    # /etc/zsh/zshrc runs compinit, which stops at an "insecure directories" prompt on CI runners.
    zsh)
      printf "PS1='%s '\n" "$PROMPT_MARK" > "$HOME/.zshrc"
      printf 'skip_global_compinit=1\n' > "$HOME/.zshenv" ;;
  esac
  start_server || return 1
  bash "$REPO_ROOT/setup.sh" shell >/dev/null
}

# bats runs teardown_file with errexit off, so a stop_server failure is kept and returned once
# unisolate has also run: a server still running at teardown fails the file.
live_teardown_file() {
  local rc=0
  stop_server || rc=1
  unisolate || rc=1
  return "$rc"
}

# require_shell <name>: skips the test when the shell is missing, except on CI (CI is set), where
# a skip would leave the check green with the case never run, so it fails instead.
require_shell() {
  command -v "$1" >/dev/null && return 0
  if [ -n "${CI:-}" ]; then
    echo "$1 is not installed; CI must run the $1 case" >&2
    return 1
  fi
  skip "$1 is not installed"
}

# One closed-pane stack per test, so a failed test's entry never reopens in the next.
live_setup() {
  export HERDR_PLUGIN_STATE_DIR="$HOME/state/$BATS_TEST_NUMBER"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  TEST_WS=""
}

live_teardown() {
  [ -z "$TEST_WS" ] || "$HERDR_BIN_PATH" workspace close "$TEST_WS" >/dev/null 2>&1 || true
}

h() { "$HERDR_BIN_PATH" "$@"; }

# new_workspace [label]: sets TEST_WS and ROOT_PANE, and waits for the root pane's prompt.
new_workspace() {
  local r args=(--cwd "$HOME" --no-focus)
  [ -z "${1:-}" ] || args+=(--label "$1")
  r=$(h workspace create "${args[@]}") || return 1
  TEST_WS=$(printf '%s' "$r" | jq -r '.result.workspace.workspace_id')
  ROOT_PANE=$(printf '%s' "$r" | jq -r '.result.root_pane.pane_id')
  wait_for "$ROOT_PANE" "$PROMPT_MARK"
}

# split_pane <pane> right|down: prints the new pane's id once its prompt is up.
split_pane() {
  local p
  p=$(h pane split "$1" --direction "$2" --no-focus | jq -r '.result.pane.pane_id') || return 1
  wait_for "$p" "$PROMPT_MARK" || return 1
  printf '%s' "$p"
}

# wait_for <pane> <text> [timeout ms]: the text shows in the pane's recent output.
wait_for() {
  h pane wait-output "$1" --match "$2" --source recent --timeout "${3:-10000}" >/dev/null || {
    echo "wait_for: '$2' never showed in $1; it shows:" >&2
    h pane read "$1" --source recent >&2
    return 1
  }
}

# put_output <pane>: runs a command whose output (uc-out-42) is not in its own command line.
put_output() {
  # shellcheck disable=SC2016  # expanded by the pane's shell
  h pane run "$1" 'echo "uc-out-$((40 + 2))"' >/dev/null && wait_for "$1" uc-out-42
}

# not_found pane|tab|workspace <id>: herdr itself answers "<kind>_not_found" for the id. Any
# other failure (a dead server, a guard refusal) is not "gone", so it fails here.
not_found() {
  local out
  if out=$(h "$1" get "$2" 2>&1); then
    echo "not_found: $1 $2 still exists" >&2
    return 1
  fi
  printf '%s' "$out" | jq -e --arg c "$1_not_found" '.error.code == $c' >/dev/null 2>&1 || {
    echo "not_found: $1 get $2 failed with something other than $1_not_found: $out" >&2
    return 1
  }
}

# not_running <pane> <name>: process-info answers for the pane, and no foreground process is
# <name>. A failed or unparsed process-info call fails here instead of reading as "not running".
not_running() {
  local out
  out=$(h pane process-info --pane "$1") || return 1
  printf '%s' "$out" | jq -e --arg n "$2" '.result.process_info.foreground_processes
    | type == "array" and (any(.[]; (.argv[0] // "" | split("/") | last) == $n) | not)' >/dev/null
}

# close_pane <pane>: close.sh on an open pane, then wait until herdr reports the pane not found
# and its entry is on the stack.
close_pane() {
  h pane get "$1" >/dev/null || { echo "close_pane: $1 is not an open pane" >&2; return 1; }
  bash "$REPO_ROOT/close.sh" "$1" || return 1
  for _ in $(seq 1 60); do
    if not_found pane "$1" 2>/dev/null && compgen -G "$HERDR_PLUGIN_STATE_DIR/closed/*/entry.json" >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  not_found pane "$1" || true
  echo "close_pane: $1 not reported gone, or no entry, after 6s" >&2
  return 1
}

# reopen_pane: reopen.sh, then print the one pane that is new since the call.
reopen_pane() {
  local before after
  before=$(all_panes)
  bash "$REPO_ROOT/reopen.sh" >/dev/null || return 1
  after=$(all_panes)
  comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || {
    echo "reopen_pane: no new pane" >&2
    return 1
  }
}

all_panes() {
  local ws
  for ws in $(h workspace list | jq -r '.result.workspaces[].workspace_id'); do
    h pane list --workspace "$ws" | jq -r '.result.panes[].pane_id'
  done | sort
}

# rect <pane> x|y|width|height
rect() {
  h pane layout --pane "$1" | jq -r --arg p "$1" --arg k "$2" '.result.layout.panes[] | select(.pane_id == $p) | .rect[$k]'
}

# pane_field <pane> <field>: fails when the pane is not found or the field is null, so a later
# "gone" check never runs on an empty id.
pane_field() {
  local out
  out=$(h pane get "$1") || return 1
  printf '%s' "$out" | jq -er ".result.pane.$2"
}

# last_line <pane>: the pane's last non-blank screen line, trailing spaces dropped.
last_line() {
  h pane read "$1" --source visible | sed 's/[[:space:]]*$//' | grep . | tail -n 1
}

# wait_last_line <pane> <suffix>: prints the last line once it ends with <suffix> (the replayed
# scrollback can hold the same text higher up, so wait_for alone cannot tell).
wait_last_line() {
  local l
  for _ in $(seq 1 50); do
    l=$(last_line "$1")
    case "$l" in *"$2") printf '%s' "$l"; return 0 ;; esac
    sleep 0.1
  done
  echo "wait_last_line: $1 ends with '$l', not '$2'" >&2
  return 1
}
