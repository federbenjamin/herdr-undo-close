#!/usr/bin/env bats
# What remember.sh and reopen.sh do with herdr's errors around plugin panes, against the fake
# herdr (test/helpers/fake-herdr.bash): no server.
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
  reply pane_process-info 0 "$(cat "$fx/procs.json")"
  reply tab_get 0 "$(cat "$fx/tab.json")"
  reply workspace_get 0 "$(cat "$fx/workspace.json")"
  reply pane_read 0 ''
  reply pane_rename 0 '{"result":{}}'
}
teardown() { unisolate; }

staged() { echo "$HERDR_PLUGIN_STATE_DIR/staging/$pane"; }

# stack_plugin <plugin id> [placement]: the plugin-overlay fixture's entry pushed onto the stack,
# as <plugin id>, with <placement> (default overlay).
stack_plugin() { stack_entry "$fx" '.plugin.id = $id | .plugin.placement = $pl' --arg id "$1" --arg pl "${2:-overlay}"; }
stack() { ls "$HERDR_PLUGIN_STATE_DIR/closed"; }

@test "snapshot saves {} when herdr says no plugin owns the pane, and logs nothing" {
  reply plugin_pane_focus 1 '{"error":{"code":"plugin_pane_not_found","message":"plugin pane not found"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ "$(cat "$(staged)/plugin.json")" = "{}" ]
}

@test "snapshot saves herdr's reply for a plugin pane" {
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  run bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  [ "$status" -eq 0 ]
  jq -e '.result.plugin_pane.plugin_id == "test.overlay"' "$(staged)/plugin.json"
}

@test "any other plugin pane focus error is logged with the pane and the code only, and leaves no plugin.json" {
  mkdir -p "$(staged)"
  echo '{}' > "$(staged)/plugin.json"
  reply plugin_pane_focus 1 '{"error":{"code":"internal_error","message":"socket hiccup in /home/user/secret"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  [ "$status" -eq 0 ]
  [ "$output" = "remember: plugin pane focus $pane failed (internal_error); not recorded as a plugin pane" ]
  [ ! -e "$(staged)/plugin.json" ]
  [ ! -e "$(staged)/plugin.json.tmp" ]
}

@test "a plugin pane focus failure with no error code (an older herdr) is logged as such" {
  reply plugin_pane_focus 2 'herdr plugin pane commands:'
  run bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  [ "$status" -eq 0 ]
  [ "$output" = "remember: plugin pane focus $pane failed (no error code); not recorded as a plugin pane" ]
  [ ! -e "$(staged)/plugin.json" ]
}

@test "a plugin that is gone drops its entry with herdr's reason, and the next reopen reaches the entry below" {
  stack_plugin other.tool
  stack_plugin acme.tool
  reply plugin_pane_open 1 '{"error":{"code":"plugin_not_found","message":"plugin not found"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not reopen the acme.tool pane (plugin_not_found: plugin not found); it is dropped from the stack."* ]]
  [ "$(stack)" = "0000000001-$pane" ]
  [ -z "$(ls "$HERDR_PLUGIN_STATE_DIR/reopening")" ]

  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w8:p9"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [[ "$(calls | grep '^plugin pane open' | tail -n 1)" == *"--plugin other.tool "* ]]
  [ -z "$(stack)" ]
}

@test "an entrypoint that is gone drops its entry with herdr's reason" {
  stack_plugin acme.tool
  reply plugin_pane_open 1 "{\"error\":{\"code\":\"plugin_pane_not_found\",\"message\":\"plugin pane entrypoint 'view' not found\"},\"id\":\"cli:plugin\"}"
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(plugin_pane_not_found: plugin pane entrypoint 'view' not found); it is dropped from the stack."* ]]
  [ -z "$(stack)" ]
}

@test "any other open failure keeps the entry and names herdr's reason on every press" {
  stack_plugin acme.tool
  reply plugin_pane_open 1 '{"error":{"code":"plugin_pane_open_failed","message":"no active workspace"},"id":"cli:plugin"}'
  for _ in 1 2; do
    run bash "$REPO_ROOT/reopen.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not reopen the acme.tool pane (plugin_pane_open_failed: no active workspace); it is back on the stack."* ]]
    [ "$(stack)" = "0000000001-$pane" ]
    [ "$(ls "$HERDR_PLUGIN_STATE_DIR/closed/0000000001-$pane")" = "$(printf 'entry.json\nscrollback.ansi')" ]
  done
}

@test "an open failure with no error code keeps the entry and says herdr gave none" {
  stack_plugin acme.tool
  reply plugin_pane_open 2 'invalid pane placement: overlay'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not reopen the acme.tool pane (herdr gave no error code); it is back on the stack."* ]]
  [ "$(stack)" = "0000000001-$pane" ]
}

# A tiled entry whose sibling, tab, and workspace are all gone: reopen makes a workspace to host it.
gone_workspace() {
  reply pane_get 1 '{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane"}'
  reply pane_list 0 '{"result":{"panes":[]}}'
  reply workspace_get 1 '{"error":{"code":"workspace_not_found","message":"workspace not found"},"id":"cli:workspace"}'
  reply workspace_create 0 '{"result":{"workspace":{"workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1"}}}'
  reply workspace_close 0 '{"result":{}}'
}

@test "an open failure that keeps the entry closes the workspace reopen made for it, on every press" {
  stack_plugin acme.tool tiled
  gone_workspace
  reply plugin_pane_open 1 '{"error":{"code":"plugin_pane_open_failed","message":"busy"},"id":"cli:plugin"}'
  for n in 1 2; do
    run bash "$REPO_ROOT/reopen.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"it is back on the stack."* ]]
    [ "$(calls | grep -c '^workspace create')" -eq "$n" ]
    [ "$(calls | grep -c '^workspace close w9$')" -eq "$n" ]
  done

  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w9:p2"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^workspace close')" -eq 2 ]
}

@test "an open failure that drops the entry closes the workspace reopen made for it" {
  stack_plugin acme.tool tiled
  gone_workspace
  reply plugin_pane_open 1 '{"error":{"code":"plugin_not_found","message":"plugin not found"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is dropped from the stack."* ]]
  [ "$(calls | grep -c '^workspace close w9$')" -eq 1 ]
  [ -z "$(stack)" ]
}

@test "a workspace reopen made and could not close hosts the next press, which makes none" {
  stack_plugin acme.tool tiled
  gone_workspace
  reply workspace_close 1 '{"error":{"code":"internal","message":"busy"},"id":"cli:workspace"}'
  reply plugin_pane_open 1 '{"error":{"code":"plugin_pane_open_failed","message":"busy"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is back on the stack."* ]]

  reply workspace_get_w9 0 '{"result":{"workspace":{"workspace_id":"w9"}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is back on the stack."* ]]
  [ "$(calls | grep -c '^workspace create')" -eq 1 ]
  [ "$(calls | grep -c '^plugin pane open .*--placement tab --workspace w9')" -eq 2 ]

  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w9:p2"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^workspace create')" -eq 1 ]
  [ -z "$(stack)" ]
}

@test "a workspace get that fails with another code places the pane as a tab and creates no workspace" {
  stack_plugin acme.tool tiled
  reply pane_get 1 '{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane"}'
  reply pane_list 0 '{"result":{"panes":[]}}'
  reply workspace_get 1 '{"error":{"code":"internal_error","message":"busy"},"id":"cli:workspace"}'
  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w8:p9"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^plugin pane open .*--placement tab --workspace w8')" -eq 1 ]
  [ "$(calls | grep -c '^workspace create')" -eq 0 ]
  [ -z "$(stack)" ]
}
