#!/usr/bin/env bats
# A closed shell pane comes back beside the same sibling, on the same side, with its output.
load live_helpers

setup_file() { live_setup_file bash; }
teardown_file() { live_teardown_file; }
setup() { live_setup; }
teardown() { live_teardown; }

@test "a pane right of its sibling reopens right of it, with its output and the marker" {
  new_workspace
  b=$(split_pane "$ROOT_PANE" right)
  put_output "$b"
  close_pane "$b"

  new=$(reopen_pane)

  [ "$(pane_field "$new" tab_id)" = "$(pane_field "$ROOT_PANE" tab_id)" ]
  [ "$(rect "$new" x)" -gt "$(rect "$ROOT_PANE" x)" ]
  wait_for "$new" "$REOPEN_MARK"
  h pane read "$new" --source recent | grep -q uc-out-42
}

@test "a pane left of its sibling reopens left of it" {
  new_workspace
  b=$(split_pane "$ROOT_PANE" right)
  put_output "$ROOT_PANE"
  close_pane "$ROOT_PANE"

  new=$(reopen_pane)

  [ "$(pane_field "$new" tab_id)" = "$(pane_field "$b" tab_id)" ]
  [ "$(rect "$new" x)" -lt "$(rect "$b" x)" ]
  [ "$(rect "$new" y)" -eq "$(rect "$b" y)" ]
  wait_for "$new" uc-out-42
}

@test "a pane above its sibling reopens above it" {
  new_workspace
  b=$(split_pane "$ROOT_PANE" down)
  put_output "$ROOT_PANE"
  close_pane "$ROOT_PANE"

  new=$(reopen_pane)

  [ "$(pane_field "$new" tab_id)" = "$(pane_field "$b" tab_id)" ]
  [ "$(rect "$new" y)" -lt "$(rect "$b" y)" ]
  [ "$(rect "$new" x)" -eq "$(rect "$b" x)" ]
  wait_for "$new" uc-out-42
}
