load ../helpers/common
load ../helpers/entry

setup() { isolate; }
teardown() { unisolate; }

@test "pane split right: the sibling is the left pane, side after" {
  run build_entry "$(fx right-after)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -nc --arg p "$(pane_of right-before)" '{pane_id:$p,direction:"right",side:"after"}')" ]
}

@test "pane split right: the left pane's sibling is the right pane, side before" {
  run build_entry "$(fx right-before)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -nc --arg p "$(pane_of right-after)" '{pane_id:$p,direction:"right",side:"before"}')" ]
}

@test "pane split down: the sibling is the upper pane, side after" {
  run build_entry "$(fx down-after)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -nc --arg p "$(pane_of down-before)" '{pane_id:$p,direction:"down",side:"after"}')" ]
}

@test "pane split down: the upper pane's sibling is the lower pane, side before" {
  run build_entry "$(fx down-before)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -nc --arg p "$(pane_of down-after)" '{pane_id:$p,direction:"down",side:"before"}')" ]
}

@test "nested split: the smallest split that held the pane decides the sibling" {
  run build_entry "$(fx nested-last)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -nc --arg p "$(pane_of nested-middle)" '{pane_id:$p,direction:"down",side:"after"}')" ]
  run build_entry "$(fx nested-middle)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = "$(jq -nc --arg p "$(pane_of nested-last)" '{pane_id:$p,direction:"down",side:"before"}')" ]
}

@test "nested split: a pane alone on one side of the root split gets a neighbour from the other side" {
  run build_entry "$(fx nested-first)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.sibling.direction' <<<"$output")" = right ]
  [ "$(jq -r '.sibling.side' <<<"$output")" = before ]
  [ "$(jq -r '.sibling.pane_id' <<<"$output")" = "$(pane_of nested-middle)" ]
}

@test "no split: sibling is null" {
  run build_entry "$(fx lone)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.sibling' <<<"$output")" = null ]
}

@test "a shell at its prompt: kind shell, argv null" {
  run build_entry "$(fx lone)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.kind' <<<"$output")" = shell ]
  [ "$(jq -c '.argv' <<<"$output")" = null ]
}

@test "a command in the foreground: kind shell, argv is the leader's argv" {
  run build_entry "$(fx command)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.kind' <<<"$output")" = shell ]
  [ "$(jq -c '.argv' <<<"$output")" = '["tail","-F","/home/user/proj/a"]' ]
}

@test "a leader that is a shell (login dash, any path) gives argv null" {
  d=$(copy_fx command)
  edit_fx "$d/procs.json" '.result.process_info.foreground_processes[0] |= (.argv = ["-bash"] | .argv0 = "-bash")'
  run build_entry "$d"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.argv' <<<"$output")" = null ]
}

@test "an agent session in agent.json: kind agent, agent and session carried over" {
  d=$(copy_fx lone)
  printf '{"agent":"claude","session":"abc-123"}' > "$d/agent.json"
  run build_entry "$d"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.kind' <<<"$output")" = agent ]
  [ "$(jq -r '.agent' <<<"$output")" = claude ]
  [ "$(jq -r '.session' <<<"$output")" = abc-123 ]
}

@test "a file viewer plugin pane: kind plugin, the plugin herdr names, viewer_open is the --open path" {
  run build_entry "$(fx plugin-split)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.kind' <<<"$output")" = plugin ]
  [ "$(jq -c '.plugin' <<<"$output")" = '{"id":"herdr-file-viewer","entrypoint":"file-viewer","placement":"tiled"}' ]
  [ "$(jq -r '.viewer_open' <<<"$output")" = /home/user/proj/sub/notes.md ]
}

@test "viewer_open is null for a pane that is not a viewer" {
  run build_entry "$(fx lone)"
  [ "$(jq -c '.viewer_open' <<<"$output")" = null ]
}

@test "the contract version is 2 and the ids and cwd come from the pane reply" {
  run build_entry "$(fx lone)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.v' <<<"$output")" = 2 ]
  [ "$(jq -r '.pane_id' <<<"$output")" = "$(pane_of lone)" ]
  [ "$(jq -r '.cwd' <<<"$output")" = /home/user/proj ]
}

@test "tab_label is null for herdr's auto label 'N · name'" {
  d=$(copy_fx lone)
  edit_fx "$d/tab.json" '.result.tab.label = "2 · proj"'
  run build_entry "$d"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.tab_label' <<<"$output")" = null ]
}

@test "tab_label is null for the label herdr 0.9.1 really gives a never-renamed tab" {
  run build_entry "$(fx lone)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.tab_label' <<<"$output")" = null ]
}

@test "tab_label keeps a label the user set" {
  run build_entry "$(fx labeled)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tab_label' <<<"$output")" = "My tab" ]
}

@test "workspace_label is null when it equals the cwd basename" {
  run build_entry "$(fx lone)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.workspace_label' <<<"$output")" = null ]
}

@test "workspace_label keeps a label the user set" {
  run build_entry "$(fx labeled)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.workspace_label' <<<"$output")" = "My workspace" ]
}

@test "missing tab and workspace replies ({}) give null labels, not an error" {
  d=$(copy_fx labeled)
  echo '{}' > "$d/tab.json"
  echo '{}' > "$d/workspace.json"
  run build_entry "$d"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.tab_label, .workspace_label]' <<<"$output")" = '[null,null]' ]
}

@test "empty tab and workspace files give null labels, not an error" {
  d=$(copy_fx labeled)
  : > "$d/tab.json"
  : > "$d/workspace.json"
  run build_entry "$d"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.tab_label, .workspace_label]' <<<"$output")" = '[null,null]' ]
}
