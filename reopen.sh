#!/usr/bin/env bash
# The reopen half (action `reopen`, prefix+u): bring back the most recently closed pane.
#   where: split off the pane it shared a split with, on the same side; else beside any pane of
#          its tab; else as a new tab of its workspace; else as a new workspace (with its name
#          when it had one)
#   what:  its scrollback replayed, then by kind — agent: `claude --resume` into the session;
#          shell: the one command it ran typed back at the prompt, not run; plugin: the same
#          plugin pane opened again (`plugin pane open`), an overlay over the active pane or a
#          split/tab in the spot above; a file viewer at the file it showed
# The shell cannot be told what to do at creation, so a reopened pane carries two environment
# variables and the login-profile hook (setup-shell) runs reopen_entry.sh from them, which
# replays, resumes, and deletes the entry. The entry is consumed once: it moves to reopening/
# first, goes back to the stack if nothing was created (dropped instead when its plugin or
# entrypoint is gone), and is forgotten by age if the hook never ran. An entry that cannot be
# read is dropped and the next one is tried.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
[ -n "$state" ] || fail "Reopen" "HERDR_PLUGIN_STATE_DIR is not set; run this as a herdr plugin action."

f() { jq -r "$1 // empty" "$entry/entry.json" 2>/dev/null || true; }
entry="" new=""
restore() { if [ -z "$new" ] && [ -n "$entry" ] && [ -d "$entry" ]; then mv "$entry" "$state/closed/" 2>/dev/null || true; fi; }
trap restore EXIT

# Pop the newest readable entry.
while :; do
  newest=$( { ls -d "$state"/closed/*/ 2>/dev/null || true; } | sort | tail -n 1)
  [ -n "$newest" ] || { notify "Reopen" "Nothing to reopen."; exit 0; }
  newest=${newest%/}
  mkdir -p "$state/reopening"
  entry="$state/reopening/$(basename "$newest")"
  mv "$newest" "$entry"
  [ "$(f .v)" = 2 ] && [ -n "$(f .pane_id)" ] && [ -n "$(f .workspace_id)" ] && [ -n "$(f .tab_id)" ] && break
  echo "reopen: dropping unreadable entry $(basename "$entry")" >&2
  rm -rf "$entry"; entry=""
done

old=$(f .pane_id) ws=$(f .workspace_id) tab=$(f .tab_id) kind=$(f .kind) label=$(f .label)
cwd=$(f .cwd); [ -d "$cwd" ] || cwd=$HOME
tab_label=$(f .tab_label) ws_label=$(f .workspace_label)

# Where it goes, by what still exists.
place=split target="" direction=right side=after
sibling=$(f .sibling.pane_id)
alive() { [ -n "$("$herdr" "$1" get "$2" 2>/dev/null | jq -r ".result.$1.${1}_id // empty" 2>/dev/null)" ]; }
if [ "$(f .plugin.placement)" = overlay ]; then
  # herdr opens an overlay over the active pane and takes no target.
  place=overlay
elif [ -n "$sibling" ] && alive pane "$sibling"; then
  target=$sibling direction=$(f .sibling.direction) side=$(f .sibling.side)
else
  target=$("$herdr" pane list --workspace "$ws" 2>/dev/null \
    | jq -r --arg t "$tab" '[.result.panes[]? | select(.tab_id == $t)][0].pane_id // empty' 2>/dev/null || true)
  if [ -n "$target" ]; then
    # Down when the pane looks taller than wide (cells are ~2x taller than wide), else right.
    direction=$("$herdr" pane layout --pane "$target" 2>/dev/null | jq -r --arg p "$target" '
      .result.layout.panes[] | select(.pane_id == $p) | .rect
      | if .height * 2 > .width then "down" else "right" end' 2>/dev/null || echo right)
  elif alive workspace "$ws"; then
    place=tab
  else
    place=workspace
  fi
fi

# The one command a shell pane ran, to type back. Refused when any byte is a control character:
# a ^C or newline inside the typed text would make the shell run it (never trust a file name).
preload=""
if [ "$kind" = shell ] && [ "$(f '.argv | length')" != "" ] && [ "$(f '.argv | length')" != 0 ]; then
  if jq -e '.argv | all(test("[[:cntrl:]]") | not)' "$entry/entry.json" >/dev/null 2>&1; then
    preload=$(jq -r '.argv | map(if test("^[A-Za-z0-9_@%+=:,./-]+$") then . else @sh end) | join(" ")' "$entry/entry.json")
  fi
fi

# What the hook will run, resolved here where PATH is known; reopen_entry.sh needs nothing else.
if [ "$kind" = agent ]; then
  {
    printf 'agent=%q\nsession=%q\n' "$(f .agent)" "$(f .session)"
    printf 'claude_bin=%q\nclaude_resume_args=%q\n' "$(command -v claude || true)" "$claude_resume_args"
  } > "$entry/launch"
fi

case "$kind" in
  plugin)
    id=$(f .plugin.id) made_ws=""
    args=(plugin pane open --plugin "$id" --entrypoint "$(f .plugin.entrypoint)" --focus)
    case "$place" in
      overlay) args+=(--placement overlay) ;;
      split) args+=(--placement split --direction "$direction" --target-pane "$target") ;;
      tab)   args+=(--placement tab --workspace "$ws") ;;
      workspace)
        # A workspace needs a first pane; the plugin pane then opens as its own tab beside that shell.
        ws_args=(--cwd "$cwd" --no-focus); [ -n "$ws_label" ] && ws_args+=(--label "$ws_label")
        ws=$("$herdr" workspace create "${ws_args[@]}" 2>/dev/null | jq -r '.result.workspace.workspace_id // empty' || true)
        [ -n "$ws" ] || fail "Reopen" "Could not recreate the workspace for the $id pane; it is back on the stack."
        made_ws=$ws
        args+=(--placement tab --workspace "$ws") ;;
    esac
    open=$(f .viewer_open)
    [ -n "$open" ] && args+=(--env "HERDR_FILE_VIEWER_OPEN=$open")
    new=$("$herdr" "${args[@]}" 2>"$entry/open-error" | jq -r '.result.plugin_pane.pane.pane_id // empty' || true)
    if [ -z "$new" ]; then
      if [ -n "$made_ws" ] && ! "$herdr" workspace close "$made_ws" >/dev/null 2>&1; then
        # The workspace stays, so the entry now names it: the next press opens there, making none.
        if jq --arg w "$made_ws" '.workspace_id = $w' "$entry/entry.json" > "$entry/entry.json.new"; then
          mv "$entry/entry.json.new" "$entry/entry.json" || true
        fi
      fi
      # herdr's own reason. A plugin or entrypoint that is gone never comes back, so its entry
      # is dropped and the next prefix+u reaches the one below; anything else may pass on retry.
      code=$(jq -r '.error.code // empty' "$entry/open-error" 2>/dev/null || true)
      why=$(jq -r '.error | "\(.code)\(if .message then ": " + .message else "" end)" | gsub("[[:cntrl:]]"; " ")' "$entry/open-error" 2>/dev/null || true)
      rm -f "$entry/open-error"
      [ -n "$code" ] || why="herdr gave no error code"
      case "$code" in
        plugin_not_found|plugin_pane_not_found)
          rm -rf "$entry"
          fail "Reopen" "Could not reopen the $id pane ($why); it is dropped from the stack." ;;
      esac
      fail "Reopen" "Could not reopen the $id pane ($why); it is back on the stack."
    fi
    rm -rf "$entry"
    ;;
  agent|shell)
    env=(--env "UNDO_CLOSE_REOPEN=$entry" --env "UNDO_CLOSE_SCRIPT=$here/reopen_entry.sh" --env BASH_SILENCE_DEPRECATION_WARNING=1)
    case "$place" in
      split)
        new=$("$herdr" pane split --pane "$target" --direction "$direction" --cwd "$cwd" --focus "${env[@]}" 2>/dev/null \
          | jq -r '.result.pane.pane_id // empty' || true) ;;
      tab)
        tab_args=(--workspace "$ws" --cwd "$cwd" --focus); [ -n "$tab_label" ] && tab_args+=(--label "$tab_label")
        new=$("$herdr" tab create "${tab_args[@]}" "${env[@]}" 2>/dev/null | jq -r '.result.root_pane.pane_id // empty' || true) ;;
      workspace)
        ws_args=(--cwd "$cwd" --focus); [ -n "$ws_label" ] && ws_args+=(--label "$ws_label")
        new=$("$herdr" workspace create "${ws_args[@]}" "${env[@]}" 2>/dev/null | jq -r '.result.root_pane.pane_id // empty' || true)
        if [ -n "$new" ] && [ -n "$tab_label" ]; then
          new_tab=$("$herdr" pane get "$new" 2>/dev/null | jq -r '.result.pane.tab_id // empty' || true)
          [ -z "$new_tab" ] || "$herdr" tab rename "$new_tab" "$tab_label" >/dev/null 2>&1 || true
        fi ;;
    esac
    [ -n "$new" ] || fail "Reopen" "Could not reopen pane $old; it is back on the stack."
    [ -z "$label" ] || "$herdr" pane rename "$new" "$label" >/dev/null 2>&1 || true
    if [ -n "$preload" ]; then
      # The hook deletes the entry once the scrollback is replayed and the prompt is next; type then.
      for _ in $(seq 1 50); do [ -e "$entry" ] || break; sleep 0.1; done
      [ -e "$entry" ] || "$herdr" pane send-text "$new" "$preload" >/dev/null 2>&1 || true
    fi
    ;;
  *) rm -rf "$entry"; fail "Reopen" "Entry of unknown kind '$kind' dropped." ;;
esac

# The old pane sat before its sibling: the new one is after, so swap them.
if [ "$side" = before ] && [ "$place" = split ]; then
  "$herdr" pane swap --source-pane "$new" --target-pane "$target" >/dev/null 2>&1 || true
fi
