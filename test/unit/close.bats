#!/usr/bin/env bats
# What ctrl+d does to a pane (close.sh), decided from its snapshot, against the fake herdr: no
# server.
load ../helpers/common
load ../helpers/fake-herdr
load ../helpers/entry

setup() {
  isolate
  fake_herdr
  fx=$(fx plugin-overlay)
  pane=$(pane_of plugin-overlay)
  reply pane_get 0 "$(cat "$fx/pane.json")"
  reply pane_layout 0 "$(cat "$fx/layout.json")"
  reply tab_get 0 "$(cat "$fx/tab.json")"
  reply workspace_get 0 "$(cat "$fx/workspace.json")"
  reply pane_read 0 ''
  reply pane_send-keys 0 '{"result":{}}'
  reply pane_close 0 '{"result":{}}'
}
# close.sh leaves promote running detached; it polls `pane get` for up to 2 s, so the test HOME
# goes only once it is done.
teardown() {
  for _ in {1..40}; do pgrep -f "$REPO_ROOT/remember.sh promote" >/dev/null || break; sleep 0.1; done
  unisolate
}

not_a_plugin='{"error":{"code":"plugin_pane_not_found","message":"plugin pane not found"},"id":"cli:plugin"}'

@test "a plugin pane is closed even when its program takes ctrl+d" {
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane close $pane"
  [ "$(calls | grep -c '^pane send-keys')" -eq 0 ]
}

@test "a shell pane whose program takes ctrl+d gets the key" {
  reply plugin_pane_focus 1 "$not_a_plugin"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane send-keys $pane ctrl+d"
  [ "$(calls | grep -c '^pane close')" -eq 0 ]
}

@test "a shell pane running anything else is closed" {
  reply plugin_pane_focus 1 "$not_a_plugin"
  reply pane_process-info 0 "$(cat "$fx/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane close $pane"
  [ "$(calls | grep -c '^pane send-keys')" -eq 0 ]
}

@test "a snapshot that fails passes the key through" {
  reply pane_get 1 '{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane"}'
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane send-keys $pane ctrl+d"
  [ "$(calls | grep -c '^pane close')" -eq 0 ]
}
