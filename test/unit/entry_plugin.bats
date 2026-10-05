load ../helpers/common
load ../helpers/entry

setup() { isolate; }
teardown() { unisolate; }

write_plugin() {
  local d=$1 plugin_id=$2 entrypoint=$3
  jq -nc --arg id "$plugin_id" --arg entrypoint "$entrypoint" \
    '{id:"cli:plugin",result:{plugin_pane:{entrypoint:$entrypoint,pane:{},plugin_id:$id},type:"plugin_pane_focused"}}' \
    > "$d/plugin.json"
}

set_viewer_process() {
  edit_fx "$1/procs.json" '.result.process_info.foreground_processes = [{argv:["herdr-file-viewer","--open","/x/y.md"],argv0:"herdr-file-viewer",cmdline:"herdr-file-viewer --open /x/y.md",cwd:"/home/user/proj",name:"herdr-file-viewer",pid:.result.process_info.shell_pid}] | .result.process_info.foreground_process_group_id = .result.process_info.shell_pid'
}

@test "a plugin in a right split keeps its sibling and records a tiled plugin entry" {
  baseline=$(build_entry "$(fx right-after)")
  d=$(copy_fx right-after)
  write_plugin "$d" acme.tool main

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.kind' <<<"$output")" = plugin ]
  [ "$(jq -c '.plugin' <<<"$output")" = '{"id":"acme.tool","entrypoint":"main","placement":"tiled"}' ]
  [ "$(jq -c '.viewer_open' <<<"$output")" = null ]
  [ "$(jq -c '.argv' <<<"$output")" = null ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -c '.sibling' <<<"$baseline")" ]
}

@test "a plugin pane zoomed on itself records overlay placement" {
  d=$(copy_fx right-after)
  write_plugin "$d" acme.tool main
  edit_fx "$d/layout.json" '.result.layout.zoomed = true | .result.layout.focused_pane_id = $pane' --arg pane "$(pane_of right-after)"

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.plugin.placement' <<<"$output")" = overlay ]
}

@test "a zoomed layout focused on another pane keeps the plugin tiled" {
  d=$(copy_fx right-after)
  write_plugin "$d" acme.tool main
  edit_fx "$d/layout.json" '.result.layout.zoomed = true | .result.layout.focused_pane_id = "w2:p1"'

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.plugin.placement' <<<"$output")" = tiled ]
}

@test "an empty or missing plugin reply remains a shell entry" {
  d=$(copy_fx lone)
  printf '{}\n' > "$d/plugin.json"

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -c '[.plugin, .kind]' <<<"$output")" = '[null,"shell"]' ]

  d=$(copy_fx right-after)
  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -c '[.plugin, .kind]' <<<"$output")" = '[null,"shell"]' ]
}

@test "a file viewer plugin records the file passed to its shell process" {
  d=$(copy_fx right-after)
  write_plugin "$d" herdr-file-viewer file-viewer
  set_viewer_process "$d"

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.viewer_open' <<<"$output")" = /x/y.md ]
}

@test "a file viewer plugin prefers its reported open-file token" {
  d=$(copy_fx right-after)
  write_plugin "$d" herdr-file-viewer file-viewer
  set_viewer_process "$d"
  edit_fx "$d/pane.json" '.result.pane.tokens.file_viewer_open = "docs/now.md"'

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.viewer_open' <<<"$output")" = docs/now.md ]
}

@test "a file viewer token does not make another plugin a viewer" {
  d=$(copy_fx right-after)
  write_plugin "$d" acme.tool main
  edit_fx "$d/pane.json" '.result.pane.tokens.file_viewer_open = "docs/now.md"'

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -c '.viewer_open' <<<"$output")" = null ]
}

@test "a plugin wins over an agent" {
  d=$(copy_fx lone)
  write_plugin "$d" acme.tool main
  printf '{"agent":"claude","session":"abc-123"}\n' > "$d/agent.json"

  run build_entry "$d"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.kind' <<<"$output")" = plugin ]
}
