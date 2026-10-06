#!/usr/bin/env bats
# The live harness's own checks (test/live/live_helpers.bash, test/helpers/live.bash), against the
# fake herdr (test/helpers/fake-herdr.bash): no server, and no call reaches any herdr.
load ../live/live_helpers
load ../helpers/fake-herdr

setup() {
  isolate
  fake_herdr
}
teardown() { unisolate; }

@test "stop_server does not count a failing status call as stopped" {
  reply 1 0 ''
  reply 2 1 '{"error":{"code":"internal","message":"boom"}}'
  reply 3 0 $'status: not running\nsocket: /x'
  run stop_server
  [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^status server$')" -eq 2 ]
}

@test "live_teardown_file fails when the server will not stop, after removing the test HOME" {
  stop_server() { return 1; }
  home=$UNDO_CLOSE_TEST_HOME
  # The way bats calls teardown_file (bats-exec-file): errexit is off inside it.
  rc=0
  live_teardown_file || rc=$?
  [ "$rc" -ne 0 ]
  [ ! -e "$home" ]
}

@test "require_shell fails on CI when the shell is missing" {
  mkdir "$HOME/empty-path"
  # Only require_shell sees the empty PATH; it uses builtins alone on this path.
  no_zsh_on_ci() { CI=true PATH="$HOME/empty-path" require_shell zsh; }
  run no_zsh_on_ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"zsh is not installed; CI must run the zsh case"* ]]
}

@test "not_found holds only on herdr's own not-found answer" {
  reply 1 1 '{"error":{"code":"tab_not_found","message":"tab w1:t2 not found"},"id":"cli:tab:get"}'
  run not_found tab w1:t2
  [ "$status" -eq 0 ]
  reply 2 97 'herdr-guard: refused'
  run not_found tab w1:t2
  [ "$status" -ne 0 ]
}

@test "not_running fails when process-info fails, and passes only on a parsed reply without the name" {
  reply 1 1 '{"error":{"code":"pane_not_found","message":"pane not found"}}'
  run not_running w1:p1 tail
  [ "$status" -ne 0 ]
  reply 2 0 '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/tail","-F","x"]}]}}}'
  run not_running w1:p1 tail
  [ "$status" -ne 0 ]
  reply 3 0 '{"result":{"process_info":{"foreground_processes":[{"argv":["-bash"]}]}}}'
  run not_running w1:p1 tail
  [ "$status" -eq 0 ]
}

@test "pane_field fails on a field the pane reply does not hold" {
  reply default 0 '{"result":{"pane":{"pane_id":"w1:p1"}}}'
  run pane_field w1:p1 tab_id
  [ "$status" -ne 0 ]
}

@test "close_pane refuses a pane herdr does not report open, without running close.sh" {
  reply default 1 '{"error":{"code":"pane_not_found","message":"pane w1:p9 not found"}}'
  run close_pane w1:p9
  [ "$status" -ne 0 ]
  [ "$(calls)" = "pane get w1:p9" ]
}
