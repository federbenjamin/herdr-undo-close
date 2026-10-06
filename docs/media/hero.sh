#!/usr/bin/env bash
# Re-takes docs/media/hero.png: a split whose right pane ran `tail -f app.log`, closed with close.sh
# and brought back with reopen.sh: its old output, then the command typed back at a fresh prompt.
# Needs herdr, jq, and vhs (with ttyd).
# Runs under the tests' isolation (test/helpers/common.bash `isolate`): a temporary HOME, every
# herdr call through test/helpers/herdr-guard, and its own headless server, stopped at the end.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../test/helpers/common.bash
. "$here/../../test/helpers/common.bash"
# shellcheck source-path=SCRIPTDIR source=../../test/helpers/live.bash
. "$REPO_ROOT/test/helpers/live.bash"
out="$here/hero.png"

isolate
trap 'stop_server || true; unisolate || true' EXIT
export BASH_SILENCE_DEPRECATION_WARNING=1
mkdir -p "$HOME/.config/herdr" "$HOME/demo/src" "$HOME/demo/test"
touch "$HOME/demo/README.md"
printf '%s\n' '12:04:31 server starting' '12:04:31 config loaded (3 routes)' '12:04:32 listening on :8080' \
  '12:04:40 GET /health 200 2ms' '12:04:52 GET /api/items 200 14ms' > "$HOME/demo/app.log"
printf '[terminal]\ndefault_shell = "%s"\nshell_mode = "login"\n' "$(command -v bash)" > "$HOME/.config/herdr/config.toml"
printf "PS1='\$ '\n" > "$HOME/.bash_profile"
start_server
bash "$REPO_ROOT/setup.sh" shell >/dev/null

h() { "$HERDR_BIN_PATH" "$@"; }
wait_for() { h pane wait-output "$1" --match "$2" --source recent --timeout 10000 >/dev/null; }

r=$(h workspace create --cwd "$HOME/demo" --label demo)
left=$(printf '%s' "$r" | jq -r '.result.root_pane.pane_id')
wait_for "$left" '$'
right=$(h pane split "$left" --direction right --no-focus | jq -r '.result.pane.pane_id')
wait_for "$right" '$'

h pane run "$left" "ls -1" >/dev/null
h pane run "$right" "tail -f app.log" >/dev/null
wait_for "$right" 'listening on :8080'

bash "$REPO_ROOT/close.sh" "$right"
for _ in $(seq 1 60); do compgen -G "$HERDR_PLUGIN_STATE_DIR/closed/*/entry.json" >/dev/null && break; sleep 0.1; done
compgen -G "$HERDR_PLUGIN_STATE_DIR/closed/*/entry.json" >/dev/null || { echo "hero.sh: close.sh remembered nothing" >&2; exit 1; }
bash "$REPO_ROOT/reopen.sh" >/dev/null
new=$(h pane list --workspace "$(printf '%s' "$r" | jq -r .result.workspace.workspace_id)" | jq -r --arg l "$left" '.result.panes[] | select(.pane_id != $l) | .pane_id')
wait_for "$new" 'reopened by undo-close'

# vhs runs under the same isolation, so its shell's client attaches to this server. The first
# attach shows herdr's welcome, then its settings: Enter, then Escape, dismisses both. vhs fails a
# recording with no frame after Show, hence the last Sleep.
cat > "$HOME/hero.tape" <<TAPE
Output "$HOME/hero.gif"
Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 440
Set Padding 0
Env PS1 "\$ "
Hide
Type 'clear; exec "\$HERDR_BIN_PATH"'
Enter
Wait+Screen@15s /continue/
Enter
Wait+Screen@5s /integrations/
Escape
Wait+Screen@5s /reopened by undo-close/
Show
Screenshot "$out"
Sleep 500ms
TAPE
vhs "$HOME/hero.tape"
echo "wrote $out"
