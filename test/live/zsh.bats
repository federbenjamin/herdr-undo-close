#!/usr/bin/env bats
# The first split case with zsh as the pane shell: setup.sh puts the hook in .zprofile.
load live_helpers

setup_file() {
  command -v zsh >/dev/null || return 0
  live_setup_file zsh
}
teardown_file() {
  command -v zsh >/dev/null || return 0
  live_teardown_file
}
setup() {
  require_shell zsh
  live_setup
}
teardown() { live_teardown; }

@test "zsh: a pane right of its sibling reopens right of it, with its output and the marker" {
  grep -q 'herdr-undo-close shell hook' "$HOME/.zprofile"
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
