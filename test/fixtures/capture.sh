#!/usr/bin/env bash
# Regenerates test/fixtures/ from a real herdr, started headless under a throwaway HOME made by
# `isolate` (every herdr call goes through test/helpers/herdr-guard). Run it when herdr changes
# a reply shape:  bash test/fixtures/capture.sh
# Each fixture dir holds the five replies entry.jq reads, saved by the plugin's own
# `remember.sh snapshot`, with the throwaway HOME replaced by /home/user.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=../helpers/common.bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../helpers/common.bash"
# shellcheck source-path=SCRIPTDIR source=../helpers/live.bash
. "$REPO_ROOT/test/helpers/live.bash"
out="$REPO_ROOT/test/fixtures"

isolate
trap 'stop_server || true; unisolate || true' EXIT
start_server
herdr() { "$HERDR_BIN_PATH" "$@"; }
mkdir -p "$HOME/proj/sub"

# new_ws <label|""> prints "<pane> <tab> <workspace>" ids of the new workspace's first pane.
new_ws() {
  local args=(--cwd "$HOME/proj" --no-focus)
  [ -z "$1" ] || args+=(--label "$1")
  herdr workspace create "${args[@]}" | jq -r '.result | "\(.root_pane.pane_id) \(.tab.tab_id) \(.workspace.workspace_id)"'
}
split() { herdr pane split "$1" --direction "$2" | jq -r '.result.pane.pane_id'; }

# run_in <pane> <marker> <command...> runs the command and waits until herdr shows marker in a
# foreground process argv.
run_in() {
  local pane=$1 marker=$2; shift 2
  herdr pane run "$pane" "$@" >/dev/null
  for _ in $(seq 1 40); do
    herdr pane process-info --pane "$pane" | jq -e --arg m "$marker" \
      '[.result.process_info.foreground_processes[]?.argv | join(" ")] | any(contains($m))' >/dev/null && return 0
    sleep 0.25
  done
  echo "capture: $marker never showed in $pane's foreground" >&2
  return 1
}

# snap <name> <pane> saves the pane's replies as test/fixtures/<name>/.
snap() {
  local name=$1 pane=$2 d="$out/$1" f
  export HERDR_PLUGIN_STATE_DIR="$HOME/state/$name"
  bash "$REPO_ROOT/remember.sh" snapshot "$pane"
  mkdir -p "$d"
  for f in pane layout procs tab workspace; do
    sed -e "s|$(cd -P "$HOME" && pwd)|/home/user|g" -e "s|$HOME|/home/user|g" \
      "$HERDR_PLUGIN_STATE_DIR/staging/$pane/$f.json" > "$d/$f.json"
  done
}

read -r p1 _ _ <<<"$(new_ws "")"
snap lone "$p1"

read -r p1 _ _ <<<"$(new_ws "")"
p2=$(split "$p1" right)
snap right-before "$p1"
snap right-after "$p2"

read -r p1 _ _ <<<"$(new_ws "")"
p2=$(split "$p1" down)
snap down-before "$p1"
snap down-after "$p2"

read -r p1 _ _ <<<"$(new_ws "")"
p2=$(split "$p1" right)
p3=$(split "$p2" down)
snap nested-first "$p1"
snap nested-middle "$p2"
snap nested-last "$p3"

read -r p1 _ _ <<<"$(new_ws "")"
p2=$(split "$p1" right)
run_in "$p2" "tail -F" tail -F "$HOME/proj/a"
snap command "$p2"

read -r p1 tab _ <<<"$(new_ws "My workspace")"
herdr tab rename "$tab" "My tab" >/dev/null
snap labeled "$p1"

# A pane whose foreground is a process named herdr-file-viewer, as the file-viewer plugin runs it.
read -r p1 _ _ <<<"$(new_ws "")"
run_in "$p1" "--open" exec -a herdr-file-viewer bash -c "'sleep 1000; :'" --open "$HOME/proj/sub/notes.md"
snap viewer "$p1"

echo "captured: $(find "$out" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ')"
