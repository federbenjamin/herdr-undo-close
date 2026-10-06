#!/usr/bin/env bats
# A closed plugin pane comes back as the same plugin pane: an overlay zoomed over the active
# pane, a split beside its sibling.
load live_helpers

setup_file() {
  live_setup_file bash || return 1
  link_plugin "$HOME/overlay-plugin" test.overlay view overlay '["sleep", "1000"]' >/dev/null
}
teardown_file() { live_teardown_file; }
setup() { live_setup; }
teardown() { live_teardown; }

@test "a closed overlay plugin pane reopens as the same overlay, zoomed over the root pane" {
  new_workspace --focus
  ov=$(h plugin pane open --plugin test.overlay --entrypoint view --placement overlay --focus \
    | jq -r '.result.plugin_pane.pane.pane_id')
  [ -n "$ov" ]
  close_pane "$ov"
  jq -e '.kind == "plugin" and .plugin.placement == "overlay"' "$HERDR_PLUGIN_STATE_DIR"/closed/*/entry.json

  new=$(reopen_pane)

  h plugin pane focus "$new" | jq -e '.result.plugin_pane | .plugin_id == "test.overlay" and .entrypoint == "view"'
  h pane layout --pane "$new" | jq -e --arg n "$new" --arg r "$ROOT_PANE" \
    '.result.layout | .zoomed == true and .focused_pane_id == $n and any(.panes[]; .pane_id == $r)'
}

@test "a closed split plugin pane reopens as a plugin pane right of its sibling, not zoomed" {
  new_workspace
  sp=$(h plugin pane open --plugin test.overlay --entrypoint view --placement split \
    --target-pane "$ROOT_PANE" --direction right --no-focus | jq -r '.result.plugin_pane.pane.pane_id')
  [ -n "$sp" ]
  h pane rename "$sp" uc-plug >/dev/null
  close_pane "$sp"

  new=$(reopen_pane)

  h plugin pane focus "$new" >/dev/null
  [ "$(pane_field "$new" label)" = uc-plug ]
  [ "$(pane_field "$new" tab_id)" = "$(pane_field "$ROOT_PANE" tab_id)" ]
  [ "$(rect "$new" x)" -gt "$(rect "$ROOT_PANE" x)" ]
  h pane layout --pane "$new" | jq -e '.result.layout.zoomed == false'
}
