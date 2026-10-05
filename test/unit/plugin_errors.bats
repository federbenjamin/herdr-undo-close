#!/usr/bin/env bats
# What remember.sh and reopen.sh do with herdr's errors around plugin panes, against a fake herdr
# at HERDR_BIN_PATH that answers by command (`plugin pane focus`, `pane get`): no server.
load ../helpers/common

setup() {
  isolate
  mkdir -p "$HOME/fake"
  # shellcheck disable=SC2016  # the fake's script text, expanded when the fake runs
  printf '%s\n' '#!/usr/bin/env bash' \
    'd="$HOME/fake"; echo "$*" >> "$d/calls"' \
    'k="$1_$2_$3"; [ -e "$d/$k.rc" ] || k="$1_$2"; [ -e "$d/$k.rc" ] || exit 1' \
    'rc=$(cat "$d/$k.rc"); if [ "$rc" = 0 ]; then cat "$d/$k.out"; else cat "$d/$k.out" >&2; fi; exit "$rc"' \
    > "$HOME/fake/herdr"
  chmod +x "$HOME/fake/herdr"
  export HERDR_BIN_PATH="$HOME/fake/herdr"
  fx="$REPO_ROOT/test/fixtures/plugin-overlay"
  pane=$(jq -r '.result.pane.pane_id' "$fx/pane.json")
  reply pane_get 0 "$(cat "$fx/pane.json")"
}
teardown() { unisolate; }

# reply <command words joined by _> <exit code> <text>: what the fake herdr answers.
reply() { printf '%s\n' "$3" > "$HOME/fake/$1.out"; echo "$2" > "$HOME/fake/$1.rc"; }
staged() { echo "$HERDR_PLUGIN_STATE_DIR/staging/$pane"; }

# stack_plugin <seq> <plugin id> [placement]: the plugin-overlay fixture's entry on the closed
# stack, as <plugin id>, with <placement> (default overlay).
stack_plugin() {
  local e
  e="$HERDR_PLUGIN_STATE_DIR/closed/$(printf '%010d' "$1")-$pane"
  mkdir -p "$e"
  bash "$REPO_ROOT/build_entry.sh" "$fx" \
    | jq --arg id "$2" --arg pl "${3:-overlay}" '.plugin.id = $id | .plugin.placement = $pl' > "$e/entry.json"
  : > "$e/scrollback.ansi"
}
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
  stack_plugin 1 other.tool
  stack_plugin 2 acme.tool
  reply plugin_pane_open 1 '{"error":{"code":"plugin_not_found","message":"plugin not found"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not reopen the acme.tool pane (plugin_not_found: plugin not found); it is dropped from the stack."* ]]
  [ "$(stack)" = "0000000001-$pane" ]
  [ -z "$(ls "$HERDR_PLUGIN_STATE_DIR/reopening")" ]

  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w8:p9"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [[ "$(grep '^plugin pane open' "$HOME/fake/calls" | tail -n 1)" == *"--plugin other.tool "* ]]
  [ -z "$(stack)" ]
}

@test "an entrypoint that is gone drops its entry with herdr's reason" {
  stack_plugin 1 acme.tool
  reply plugin_pane_open 1 "{\"error\":{\"code\":\"plugin_pane_not_found\",\"message\":\"plugin pane entrypoint 'view' not found\"},\"id\":\"cli:plugin\"}"
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(plugin_pane_not_found: plugin pane entrypoint 'view' not found); it is dropped from the stack."* ]]
  [ -z "$(stack)" ]
}

@test "any other open failure keeps the entry and names herdr's reason on every press" {
  stack_plugin 1 acme.tool
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
  stack_plugin 1 acme.tool
  reply plugin_pane_open 2 'invalid pane placement: overlay'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not reopen the acme.tool pane (herdr gave no error code); it is back on the stack."* ]]
  [ "$(stack)" = "0000000001-$pane" ]
}

# A tiled entry whose sibling, tab, and workspace are all gone: reopen makes a workspace to host it.
gone_workspace() {
  reply pane_get 1 '{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane"}'
  reply workspace_create 0 '{"result":{"workspace":{"workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1"}}}'
  reply workspace_close 0 '{"result":{}}'
}

@test "an open failure that keeps the entry closes the workspace reopen made for it, on every press" {
  stack_plugin 1 acme.tool tiled
  gone_workspace
  reply plugin_pane_open 1 '{"error":{"code":"plugin_pane_open_failed","message":"busy"},"id":"cli:plugin"}'
  for n in 1 2; do
    run bash "$REPO_ROOT/reopen.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"it is back on the stack."* ]]
    [ "$(grep -c '^workspace create' "$HOME/fake/calls")" -eq "$n" ]
    [ "$(grep -c '^workspace close w9$' "$HOME/fake/calls")" -eq "$n" ]
  done

  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w9:p2"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^workspace close' "$HOME/fake/calls")" -eq 2 ]
}

@test "an open failure that drops the entry closes the workspace reopen made for it" {
  stack_plugin 1 acme.tool tiled
  gone_workspace
  reply plugin_pane_open 1 '{"error":{"code":"plugin_not_found","message":"plugin not found"},"id":"cli:plugin"}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is dropped from the stack."* ]]
  [ "$(grep -c '^workspace close w9$' "$HOME/fake/calls")" -eq 1 ]
  [ -z "$(stack)" ]
}

@test "a workspace reopen made and could not close hosts the next press, which makes none" {
  stack_plugin 1 acme.tool tiled
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
  [ "$(grep -c '^workspace create' "$HOME/fake/calls")" -eq 1 ]
  [ "$(grep -c '^plugin pane open .*--placement tab --workspace w9' "$HOME/fake/calls")" -eq 2 ]

  reply plugin_pane_open 0 '{"result":{"plugin_pane":{"pane":{"pane_id":"w9:p2"}}}}'
  run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^workspace create' "$HOME/fake/calls")" -eq 1 ]
  [ -z "$(stack)" ]
}
