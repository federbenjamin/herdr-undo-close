#!/usr/bin/env bats
# A pane closed while it ran a command gets that command typed back at the prompt, never run,
# and never typed when it holds a control character.
load live_helpers

setup_file() { live_setup_file bash; }
teardown_file() { live_teardown_file; }
setup() { live_setup; }
teardown() { live_teardown; }

# wait_leader <pane> <name>: the pane's foreground process group leader is <name>.
wait_leader() {
  for _ in $(seq 1 50); do
    h pane process-info --pane "$1" | jq -e --arg n "$2" '.result.process_info
      | .foreground_process_group_id as $g | any(.foreground_processes[]?; .pid == $g and (.argv[0] | split("/") | last) == $n)' >/dev/null && return 0
    sleep 0.1
  done
  echo "wait_leader: $2 never led $1" >&2
  return 1
}

@test "a pane running tail -F '<dir>/a;b' reopens with that command typed, not run" {
  new_workspace
  b=$(split_pane "$ROOT_PANE" right)
  h pane run "$b" "tail -F '$HOME/a;b'"
  wait_leader "$b" tail
  close_pane "$b"

  new=$(reopen_pane)

  wait_for "$new" "$REOPEN_MARK"
  line=$(wait_last_line "$new" "tail -F '$HOME/a;b'")
  [ "$line" = "$PROMPT_MARK tail -F '$HOME/a;b'" ]
  not_running "$new" tail
}

@test "a command holding a control character is not typed back" {
  new_workspace
  b=$(split_pane "$ROOT_PANE" right)
  # bash turns $'...\001...' into a real ^A byte in tail's argv.
  h pane run "$b" "tail -F \$'$HOME/x\\001y'"
  wait_leader "$b" tail
  close_pane "$b"
  # "Nothing typed" below is the guard's doing only if the saved argv really holds the ^A byte.
  jq -e 'any(.argv[]?; test("[[:cntrl:]]"))' "$HERDR_PLUGIN_STATE_DIR"/closed/*/entry.json >/dev/null

  new=$(reopen_pane)

  wait_for "$new" "$REOPEN_MARK"
  # reopen.sh types before it returns, so a sentinel typed now lands after anything it typed.
  h pane send-text "$new" uc-sentinel
  line=$(wait_last_line "$new" uc-sentinel)
  [ "$line" = "$PROMPT_MARK uc-sentinel" ]
}
