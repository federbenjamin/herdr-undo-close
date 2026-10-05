#!/usr/bin/env bash
# The memory half. close.sh calls `snapshot` before every close key and `promote` after it.
#
#   remember.sh snapshot <pane>   staging/<pane>/: the raw herdr replies build_entry.sh reads,
#                                 agent.json while the pane holds an agent (kept $agent_minutes
#                                 after it leaves: Claude Code exits on two ctrl+d, the shell on
#                                 the next), and the scrollback.
#   remember.sh promote <pane>    forgets anything older than $max_age_days, waits up to ~2s for
#                                 the pane to be gone, then pushes entry.json (entry.jq: the flat
#                                 contract reopen.sh reads) and scrollback.ansi onto the stack.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
# shellcheck source=stack.sh
. "$here/stack.sh"
[ -n "$state" ] || exit 0

cmd=${1:?usage: remember.sh snapshot|promote <pane>}
pane=${2:?usage: remember.sh snapshot|promote <pane>}
valid_id "$pane" || exit 0
dir=$(stack_staging "$pane")

# A reply is written whole or not at all (a redirect would truncate the file first).
# shellcheck disable=SC2015  # the rm runs when either step fails, which is the intent
save() { "$herdr" "${@:2}" > "$1.tmp" 2>/dev/null && mv "$1.tmp" "$1" || { rm -f "$1.tmp"; return 1; }; }

case "$cmd" in
  snapshot)
    mkdir -p "$dir"
    save "$dir/pane.json" pane get "$pane" || exit 1
    if [ -n "$(jq -r '.result.pane.agent_session.value // empty' "$dir/pane.json")" ]; then
      jq '.result.pane | {agent, session: .agent_session.value}' "$dir/pane.json" > "$dir/agent.json"
    elif [ -n "$(find "$dir" -name agent.json -mmin +"$agent_minutes" 2>/dev/null)" ]; then
      rm -f "$dir/agent.json"   # the agent left long ago; this is a plain shell close now
    fi
    save "$dir/layout.json" pane layout --pane "$pane" || true
    # The one API that names a pane's plugin; it also focuses the pane, so the layout is saved first.
    # {} only on herdr's own "no plugin owns it"; any other failure leaves no plugin.json (the entry
    # falls back to a shell) and says so on stdout, which close.sh leaves to `herdr plugin log`.
    if err=$("$herdr" plugin pane focus "$pane" 2>&1 > "$dir/plugin.json.tmp"); then
      mv "$dir/plugin.json.tmp" "$dir/plugin.json"
    else
      rm -f "$dir/plugin.json.tmp" "$dir/plugin.json"
      herdr_error "$err"
      if [ "$code" = plugin_pane_not_found ]; then
        echo '{}' > "$dir/plugin.json"
      else
        echo "remember: plugin pane focus $pane failed (${code:-no error code}); not recorded as a plugin pane"
      fi
    fi
    save "$dir/procs.json" pane process-info --pane "$pane" || echo '{}' > "$dir/procs.json"
    save "$dir/tab.json" tab get "$(jq -r '.result.pane.tab_id' "$dir/pane.json")" || echo '{}' > "$dir/tab.json"
    save "$dir/workspace.json" workspace get "$(jq -r '.result.pane.workspace_id' "$dir/pane.json")" || echo '{}' > "$dir/workspace.json"
    save "$dir/scrollback.ansi" pane read "$pane" --source recent --lines 100000 --format ansi || : > "$dir/scrollback.ansi"
    ;;
  promote)
    stack_forget_old
    [ -d "$dir" ] || exit 0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.2
      gone pane "$pane" || continue
      if ! bash "$here/build_entry.sh" "$dir" > "$dir/entry.json" 2>/dev/null; then
        rm -rf "$dir"; exit 0
      fi
      stack_push "$pane"
      exit 0
    done
    ;;
  *) echo "usage: remember.sh snapshot|promote <pane>" >&2; exit 2 ;;
esac
