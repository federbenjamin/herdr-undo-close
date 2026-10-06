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
  [ "$(calls | grep -c 'close it by hand')" -eq 0 ]
  [ -z "$(stack)" ]
}

@test "an open failure that drops the entry, with a workspace reopen made and cannot close, reports that workspace" {
  stack_plugin acme.tool tiled
  gone_workspace
  reply workspace_close 1 '{"error":{"code":"internal","message":"busy"},"id":"cli:workspace"}'
  reply plugin_pane_open 1 '{"error":{"code":"plugin_not_found","message":"plugin not found"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is dropped from the stack."* ]]
  calls | grep -qx 'notification show Reopen --body Could not close the workspace w9 that reopen made; close it by hand. --sound none'
  [ -z "$(stack)" ]
}

@test "a workspace reopen made and can neither close nor name in the kept entry is reported" {
  stack_plugin acme.tool tiled
  gone_workspace
  reply workspace_close 1 '{"error":{"code":"internal","message":"busy"},"id":"cli:workspace"}'
  reply plugin_pane_open 1 '{"error":{"code":"plugin_pane_open_failed","message":"busy"},"id":"cli:plugin"}'
  mkdir "$HERDR_PLUGIN_STATE_DIR/closed/0000000001-$pane/entry.json.new"
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is back on the stack."* ]]
  calls | grep -qx 'notification show Reopen --body Could not close the workspace w9 that reopen made; close it by hand. --sound none'
  [ "$(stack)" = "0000000001-$pane" ]
  [ "$(jq -r .workspace_id "$HERDR_PLUGIN_STATE_DIR/closed/0000000001-$pane/entry.json")" != w9 ]
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

@test "a temporary file reopen cannot make fails the reopen, closes the workspace it made, and keeps the entry" {
  stack_plugin acme.tool tiled
  gone_workspace
  run env TMPDIR="$HOME/no-tmp" bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not reopen the acme.tool pane (could not make a temporary file); it is back on the stack."* ]]
  calls | grep -qx 'notification show Reopen --body Could not reopen the acme.tool pane (could not make a temporary file); it is back on the stack. --sound none'
  [ "$(calls | grep -c '^workspace close w9$')" -eq 1 ]
  [ "$(calls | grep -c '^plugin pane open')" -eq 0 ]
  [ "$(stack)" = "0000000001-$pane" ]
}

@test "a temporary file reopen cannot make, with a workspace it made and cannot close, points the entry there" {
  stack_plugin acme.tool tiled
  gone_workspace
  reply workspace_close 1 '{"error":{"code":"internal","message":"busy"},"id":"cli:workspace"}'
  run env TMPDIR="$HOME/no-tmp" bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(could not make a temporary file); it is back on the stack."* ]]
  [ "$(jq -r .workspace_id "$HERDR_PLUGIN_STATE_DIR/closed/0000000001-$pane/entry.json")" = w9 ]
  [ "$(calls | grep -c 'close it by hand')" -eq 0 ]
}

@test "a temporary file reopen cannot make for an overlay fails the reopen and keeps the entry" {
  stack_plugin acme.tool
  run env TMPDIR="$HOME/no-tmp" bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not reopen the acme.tool pane (could not make a temporary file); it is back on the stack."* ]]
  [ "$(calls | grep -c '^workspace')" -eq 0 ]
  [ "$(stack)" = "0000000001-$pane" ]
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

@test "a sibling that pane get fails on with another code still takes the split" {
  stack_entry "$(fx plugin-split)"
  reply pane_get 1 '{"error":{"code":"internal_error","message":"busy"},"id":"cli:pane"}'
  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w7:p9"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^plugin pane open .*--placement split --direction right --target-pane w7:p1')" -eq 1 ]
  [ "$(calls | grep -c '^pane list')" -eq 0 ]
}

@test "promote does not push a pane that pane get fails on with another code" {
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  reply pane_get 1 '{"error":{"code":"internal_error","message":"busy"},"id":"cli:pane"}'
  run bash "$REPO_ROOT/remember.sh" promote "$pane"
  [ "$status" -eq 0 ]
  [ -z "$(ls "$HERDR_PLUGIN_STATE_DIR/closed" 2>/dev/null)" ]
  [ -f "$(staged)/pane.json" ]
}

@test "promote says so and fails when the entry cannot be put on the stack" {
  reply plugin_pane_focus 0 "$(cat "$fx/plugin.json")"
  bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  reply pane_get 1 '{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane"}'
  mkdir -p "$HERDR_PLUGIN_STATE_DIR/closed"
  chmod 500 "$HERDR_PLUGIN_STATE_DIR/closed"
  run bash "$REPO_ROOT/remember.sh" promote "$pane"
  chmod 700 "$HERDR_PLUGIN_STATE_DIR/closed"
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "Could not remember the closed pane $pane; it cannot be reopened." ]
  calls | grep -qx "notification show Close --body Could not remember the closed pane $pane; it cannot be reopened. --sound none"
  [ -z "$(stack)" ]
}

# noisy_open <stdout|stderr> <line>: herdr also prints <line> on that stream at every plugin pane
# open, beside its reply.
noisy_open() {
  local fd=1
  [ "$1" = stdout ] || fd=2
  printf '%s\n' "$2" > "$HOME/fake/noise"
  printf '#!/usr/bin/env bash\ncase "$*" in "plugin pane open "*) cat "$HOME/fake/noise" >&%s ;; esac\nexec "$HOME/fake/herdr" "$@"\n' "$fd" > "$HOME/fake/noisy"
  chmod +x "$HOME/fake/noisy"
  export HERDR_BIN_PATH="$HOME/fake/noisy"
}

@test "a warning on stderr beside a successful open still reopens the pane" {
  stack_plugin acme.tool
  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w8:p9"}}}}'
  noisy_open stderr 'warning: a newer herdr is available'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ -z "$(stack)" ]
  [ -z "$(ls "$HERDR_PLUGIN_STATE_DIR/reopening")" ]
}

@test "text on stdout beside a failed open does not hide herdr's error code" {
  stack_plugin acme.tool
  reply plugin_pane_open 1 '{"error":{"code":"plugin_not_found","message":"plugin not found"},"id":"cli:plugin"}'
  noisy_open stdout 'opening acme.tool'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(plugin_not_found: plugin not found); it is dropped from the stack."* ]]
  [ -z "$(stack)" ]
}

@test "an empty stack is nothing to reopen" {
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "Nothing to reopen." ]
}

@test "a newest entry that cannot be taken off the stack fails the reopen and stays on top" {
  stack_plugin acme.tool
  mkdir -p "$HERDR_PLUGIN_STATE_DIR/reopening/$(stack)/left-over"
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not take the last closed pane off the stack; it is still there."* ]]
  [[ "$output" != *"Nothing to reopen"* ]]
  [ "$(stack)" = "0000000001-$pane" ]
  [ "$(calls | grep -c '^plugin pane open')" -eq 0 ]
}
