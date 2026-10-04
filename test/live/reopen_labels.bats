#!/usr/bin/env bats
# Closing the last pane of a tab or a workspace closes it too; reopen brings it back with its
# custom label.
load live_helpers

setup_file() { live_setup_file bash; }
teardown_file() { live_teardown_file; }
setup() { live_setup; }
teardown() {
  live_teardown
  [ -z "${NEW_WS:-}" ] || h workspace close "$NEW_WS" >/dev/null 2>&1 || true
}

@test "the last pane of a labeled tab brings the tab back with its label" {
  new_workspace
  c=$(h tab create --workspace "$TEST_WS" --cwd "$HOME" --label uc-tab --no-focus | jq -r '.result.root_pane.pane_id')
  wait_for "$c" "$PROMPT_MARK"
  old_tab=$(pane_field "$c" tab_id)
  close_pane "$c"
  run ! h tab get "$old_tab" >/dev/null 2>&1

  new=$(reopen_pane)

  [ "$(pane_field "$new" workspace_id)" = "$TEST_WS" ]
  [ "$(h tab get "$(pane_field "$new" tab_id)" | jq -r .result.tab.label)" = uc-tab ]
}

@test "the last pane of a labeled workspace brings the workspace back with its label" {
  new_workspace uc-space
  close_pane "$ROOT_PANE"
  run ! h workspace get "$TEST_WS" >/dev/null 2>&1
  TEST_WS=""

  new=$(reopen_pane)

  NEW_WS=$(pane_field "$new" workspace_id)
  [ "$(h workspace get "$NEW_WS" | jq -r .result.workspace.label)" = uc-space ]
}
