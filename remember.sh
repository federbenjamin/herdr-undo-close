#!/usr/bin/env bash
# The memory half. close.sh calls `snapshot` before every close key and `promote` after it.
#
#   remember.sh snapshot <pane>   staging/<pane>/: the raw herdr replies (pane, layout, procs,
#                                 tab, workspace), agent.json while the pane holds an agent
#                                 (kept $agent_minutes after it leaves: Claude Code exits on
#                                 two ctrl+d, the shell on the next), and the scrollback.
#                                 Also forgets anything older than $max_age_days.
#   remember.sh promote <pane>    waits up to ~2s for the pane to be gone, then turns the
#                                 staging dir into closed/<seq>-<pane>/ holding entry.json
#                                 (entry.jq: the flat contract reopen.sh reads) and
#                                 scrollback.ansi. The stack keeps the newest $keep.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
[ -n "$state" ] || exit 0

cmd=${1:?usage: remember.sh snapshot|promote <pane>}
pane=${2:?usage: remember.sh snapshot|promote <pane>}
valid_id "$pane" || exit 0
dir="$state/staging/$pane"

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
    save "$dir/procs.json" pane process-info --pane "$pane" || echo '{}' > "$dir/procs.json"
    save "$dir/tab.json" tab get "$(jq -r '.result.pane.tab_id' "$dir/pane.json")" || echo '{}' > "$dir/tab.json"
    save "$dir/workspace.json" workspace get "$(jq -r '.result.pane.workspace_id' "$dir/pane.json")" || echo '{}' > "$dir/workspace.json"
    save "$dir/scrollback.ansi" pane read "$pane" --source recent --lines 100000 --format ansi || : > "$dir/scrollback.ansi"
    # Forget old snapshots whether or not anything else ever happens.
    for d in staging closed reopening; do
      find "$state/$d" -mindepth 1 -maxdepth 1 -type d -mtime +"$max_age_days" -exec rm -rf {} + 2>/dev/null || true
    done
    ;;
  promote)
    [ -d "$dir" ] || exit 0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.2
      # Gone means herdr says so (its error JSON goes to stderr); any other error is not a close.
      [ "$("$herdr" pane get "$pane" 2>&1 >/dev/null | jq -r '.error.code // empty' 2>/dev/null)" = pane_not_found ] || continue
      [ -s "$dir/pane.json" ] && [ -s "$dir/layout.json" ] || { rm -rf "$dir"; exit 0; }
      [ -e "$dir/agent.json" ] || : > "$dir/agent.json"
      if ! jq -n -f "$here/entry.jq" --slurpfile pane "$dir/pane.json" --slurpfile layout "$dir/layout.json" \
           --slurpfile procs "$dir/procs.json" --slurpfile tab "$dir/tab.json" --slurpfile ws "$dir/workspace.json" \
           --slurpfile agent "$dir/agent.json" > "$dir/entry.json" 2>/dev/null; then
        rm -rf "$dir"; exit 0
      fi
      # Entries sort by a counter, so two closes in one second keep their order.
      mkdir -p "$state/closed"
      seq=$(( $(cat "$state/seq" 2>/dev/null || echo 0) + 1 )); printf '%s' "$seq" > "$state/seq"
      entry="$state/closed/$(printf '%010d' "$seq")-$pane"
      mkdir "$entry" && mv "$dir/entry.json" "$dir/scrollback.ansi" "$entry/" && rm -rf "$dir"
      # The stack keeps the newest $keep.
      { ls -d "$state"/closed/*/ 2>/dev/null || true; } | sort -r | tail -n +"$((keep + 1))" | while read -r old; do rm -rf "$old"; done
      exit 0
    done
    ;;
  *) echo "usage: remember.sh snapshot|promote <pane>" >&2; exit 2 ;;
esac
