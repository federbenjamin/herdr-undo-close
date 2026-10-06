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
gone_pane='{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane"}'
# close.sh leaves promote running detached. Once close.sh is done herdr says the pane is gone, as
# it does after a close, so promote ends at its first poll; the test HOME goes only after that.
teardown() {
  reply pane_get 1 "$gone_pane"
  for _ in {1..40}; do pgrep -f "$REPO_ROOT/internal/remember.sh promote" >/dev/null || break; sleep 0.1; done
  unisolate
}

not_a_plugin='{"error":{"code":"plugin_pane_not_found","message":"plugin pane not found"},"id":"cli:plugin"}'
busy='{"error":{"code":"internal_error","message":"busy"},"id":"cli:plugin"}'

@test "a plugin pane is closed even when its program takes ctrl+d" {
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane close $pane"
  [ "$(calls | grep -c '^pane send-keys')" -eq 0 ]
}

@test "a plugin pane is closed even when herdr reports an agent in it" {
  reply pane_get 0 "$(jq '.result.pane.agent = "claude"' "$fx/pane.json")"
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane close $pane"
  [ "$(calls | grep -c '^pane send-keys')" -eq 0 ]
}

@test "a shell pane whose program takes ctrl+d gets the key, and close.sh logs nothing" {
  reply plugin_pane_focus 1 "$not_a_plugin"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  calls | grep -qx "pane send-keys $pane ctrl+d"
  [ "$(calls | grep -c '^pane close')" -eq 0 ]
}

@test "a plugin pane focus that fails with another code leaves the pane judged by its program" {
  reply plugin_pane_focus 1 "$busy"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  calls | grep -qx "pane send-keys $pane ctrl+d"
  [ "$(calls | grep -c '^pane close')" -eq 0 ]
}

@test "a process-info that fails passes the key through" {
  reply plugin_pane_focus 1 "$not_a_plugin"
  reply pane_process-info 1 "$busy"
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

# close_then_promote_fails: ctrl+d on the plugin pane, then herdr says it is gone; waits for the
# notification the detached promote shows when the stack does not take the pane.
close_then_promote_fails() {
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  reply pane_process-info 0 "$(cat "$(fx lone)/procs.json")"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  reply pane_get 1 "$gone_pane"
  for _ in {1..40}; do calls | grep -q '^notification show Close' && break; sleep 0.1; done
  calls | grep -qx "notification show Close --body Could not remember the closed pane $pane; it cannot be reopened. --sound none"
  [ -z "$(ls "$HERDR_PLUGIN_STATE_DIR/closed")" ]
  [ -d "$HERDR_PLUGIN_STATE_DIR/staging/$pane" ]
}

@test "a closed pane the stack cannot hold is reported in a notification" {
  mkdir -p "$HERDR_PLUGIN_STATE_DIR/closed"
  chmod 500 "$HERDR_PLUGIN_STATE_DIR/closed"
  close_then_promote_fails
  chmod 700 "$HERDR_PLUGIN_STATE_DIR/closed"
}

@test "a closed pane whose push cannot get the stack lock is reported in a notification" {
  ln -s "$$.$(date +%s).1" "$HERDR_PLUGIN_STATE_DIR/seq.lock"
  close_then_promote_fails
}

@test "a snapshot that fails passes the key through, and says so" {
  reply pane_get 1 "$gone_pane"
  run bash "$REPO_ROOT/close.sh" "$pane"
  [ "$status" -eq 0 ]
  [ "$output" = "close: snapshot of $pane failed; ctrl+d passed through" ]
  calls | grep -qx "pane send-keys $pane ctrl+d"
  [ "$(calls | grep -c '^pane close')" -eq 0 ]
}
