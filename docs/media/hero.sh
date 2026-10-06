#!/usr/bin/env bash
# Re-takes docs/media/hero.gif: a split whose left pane runs `tail -f app.log`, closed with ctrl+d
# and brought back with prefix+u: its old output, then the command typed back at a fresh prompt.
# The keys are the ones setup-keys binds, pressed in a client that vhs records.
# Needs herdr, jq, and vhs (with ttyd).
# Runs under the tests' isolation (test/helpers/common.bash `isolate`): a temporary HOME, every
# herdr call through test/helpers/herdr-guard, and its own headless server, stopped at the end.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../test/helpers/common.bash
. "$here/../../test/helpers/common.bash"
# shellcheck source-path=SCRIPTDIR source=../../test/helpers/live.bash
. "$REPO_ROOT/test/helpers/live.bash"
out="$here/hero.gif"

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
h() { "$HERDR_BIN_PATH" "$@"; }
h plugin link "$REPO_ROOT" >/dev/null
bash "$REPO_ROOT/setup.sh" keys >/dev/null
bash "$REPO_ROOT/setup.sh" shell >/dev/null

wait_for() { h pane wait-output "$1" --match "$2" --source recent --timeout 10000 >/dev/null; }

r=$(h workspace create --cwd "$HOME/demo" --label demo)
left=$(printf '%s' "$r" | jq -r '.result.root_pane.pane_id')
wait_for "$left" '$'
right=$(h pane split "$left" --direction right --no-focus | jq -r '.result.pane.pane_id')
wait_for "$right" '$'

# The root pane is the one a fresh client focuses, so it is the one the recording closes.
h pane run "$left" "tail -f app.log" >/dev/null
h pane run "$right" "ls -1" >/dev/null
wait_for "$left" 'listening on :8080'

# vhs runs under the same isolation, so its shell's client attaches to this server. The first
# attach shows herdr's welcome, then its settings: Enter, then Escape, dismisses both. The pauses
# are for the viewer: a beat on each state before the next key. vhs fails a recording with no
# frame after the last key, hence the final Sleep.
cat > "$HOME/hero.tape" <<TAPE
Output "$out"
Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 440
Set Padding 0
Set Framerate 20
Set PlaybackSpeed 1.0
Env PS1 "\$ "
Hide
Type 'clear; exec "\$HERDR_BIN_PATH"'
Enter
Wait+Screen@15s /continue/
Enter
Wait+Screen@5s /integrations/
Escape
Wait+Screen@5s /listening on :8080/
Show
Sleep 1.5s
Ctrl+D
Sleep 1.5s
Ctrl+B
Type "u"
Wait+Screen@10s /reopened by undo-close/
Sleep 4s
TAPE
vhs "$HOME/hero.tape"
echo "wrote $out"
