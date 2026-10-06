#!/usr/bin/env bash
# Re-takes docs/media/hero.gif: a split whose left pane runs `tail -f app.log` and whose right pane
# holds a Claude Code session with one exchange. The left pane is closed with ctrl+d and brought
# back with prefix+u: its old output, then the command typed back at a fresh prompt. Then the
# right pane: ctrl+d until it closes, prefix+u, and it comes back as `claude --resume` into the
# same conversation. The keys are the ones setup-keys binds, pressed in a client that vhs records.
# Needs herdr, jq, claude, and vhs (with ttyd). Makes one live model call (haiku).
# Runs under the tests' isolation (test/helpers/common.bash `isolate`): a temporary HOME, every
# herdr call through test/helpers/herdr-guard, and its own headless server, stopped at the end.
# Claude Code runs on your own login: a `claude` wrapper first on the panes' PATH runs the real
# claude with your HOME but only the demo's settings (--setting-sources local --settings), so your
# hooks, status line and plugins stay out of the picture. The demo session's transcript folder is
# deleted at the end.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../test/helpers/common.bash
. "$here/../../test/helpers/common.bash"
# shellcheck source-path=SCRIPTDIR source=../../test/helpers/live.bash
. "$REPO_ROOT/test/helpers/live.bash"
out="$here/hero.gif"
claude_bin=$(command -v claude) || { echo "hero.sh: claude is not on PATH" >&2; exit 1; }
real_home=$HOME
session=""

# HOME resolved (on macOS /tmp is a link), so herdr and Claude Code agree on the demo folder's path.
UNDO_CLOSE_TEST_TMP=$(cd -P /tmp && pwd)
export UNDO_CLOSE_TEST_TMP
isolate
# The demo session's folder in your ~/.claude/projects, removed only when named for the demo folder.
forget_session() {
  local f
  [ -n "$session" ] || return 0
  for f in "$real_home/.claude/projects/"*/"$session.jsonl"; do
    case "$(basename "$(dirname "$f")")" in *-uc-??????-demo) rm -rf -- "$(dirname "$f")" ;; esac
  done
}
trap 'stop_server || true; forget_session; unisolate || true' EXIT
# A Claude Code session that started this script marks its children as its own; a claude that
# inherits the marks saves no transcript, so there would be nothing to resume.
for v in $(compgen -e); do
  case "$v" in CLAUDECODE|CLAUDE_*) unset "$v" ;; esac
done
export BASH_SILENCE_DEPRECATION_WARNING=1
mkdir -p "$HOME/.config/herdr" "$HOME/demo/src" "$HOME/demo/test" "$HOME/bin" "$HOME/.claude"
touch "$HOME/demo/README.md"
printf '%s\n' '12:04:31 server starting' '12:04:31 config loaded (3 routes)' '12:04:32 listening on :8080' \
  '12:04:40 GET /health 200 2ms' '12:04:52 GET /api/items 200 14ms' > "$HOME/demo/app.log"
printf '[terminal]\ndefault_shell = "%s"\nshell_mode = "login"\n' "$(command -v bash)" > "$HOME/.config/herdr/config.toml"
# The reopened pane looks for the session file under CLAUDE_CONFIG_DIR, so it names your folder.
printf "PS1='\$ '\nexport PATH=\"\$HOME/bin:\$PATH\"\nexport CLAUDE_CONFIG_DIR=%q\n" "$real_home/.claude" > "$HOME/.bash_profile"
# The demo's Claude settings: the cheapest model, and herdr's session hook (installed below by
# `integration install claude`) so herdr knows which session to resume.
jq -n --arg hook "$HOME/.claude/hooks/herdr-agent-state.sh" '{model: "haiku",
  hooks: {SessionStart: [{matcher: "^(startup|resume|clear|compact|fork)$",
    hooks: [{type: "command", command: ("bash " + ($hook | @sh) + " session"), timeout: 10}]}]}}' \
  > "$HOME/claude-settings.json"
cat > "$HOME/bin/claude" <<SHIM
#!/bin/sh
exec env -u CLAUDE_CONFIG_DIR HOME="$real_home" DISABLE_AUTOUPDATER=1 "$claude_bin" --setting-sources local --settings "$HOME/claude-settings.json" "\$@"
SHIM
chmod +x "$HOME/bin/claude"
# reopen.sh finds claude on the server's PATH, so the server starts with the wrapper first on it.
export PATH="$HOME/bin:$PATH"
start_server
h() { "$HERDR_BIN_PATH" "$@"; }
h plugin link "$REPO_ROOT" >/dev/null
bash "$REPO_ROOT/setup.sh" keys >/dev/null
bash "$REPO_ROOT/setup.sh" shell >/dev/null
h integration install claude >/dev/null

wait_for() { h pane wait-output "$1" --match "$2" --source recent --timeout "${3:-10000}" >/dev/null; }

r=$(h workspace create --cwd "$HOME/demo" --label demo)
left=$(printf '%s' "$r" | jq -r '.result.root_pane.pane_id')
wait_for "$left" '$'
right=$(h pane split "$left" --direction right --no-focus | jq -r '.result.pane.pane_id')
wait_for "$right" '$'

# The root pane is the one a fresh client focuses, so it is the one the recording closes first.
h pane run "$left" "tail -f app.log" >/dev/null
wait_for "$left" 'listening on :8080'

# One exchange, so the session has a conversation file to resume.
screen() { echo "hero.sh: $1; the Claude pane shows:" >&2; h pane read "$right" --source recent --lines 30 >&2; exit 1; }
h pane run "$right" claude >/dev/null
# A new folder gets Claude's trust question first, defaulting to "No, exit": pick yes, once.
trusted=0
ready() {
  local out
  out=$(h pane read "$right" --source recent --lines 40 2>/dev/null) || return 1
  case "$out" in *"for shortcuts"*) return 0 ;; esac
  case "$trusted:$out" in 0:*"Yes, I trust this folder"*)
    trusted=1; h pane send-keys "$right" down >/dev/null; h pane send-keys "$right" enter >/dev/null ;;
  esac
  return 1
}
poll 120 0.25 ready || screen "claude did not reach its prompt"
# Claude's SessionStart hook reports the session to herdr a moment after the prompt draws.
session_id() { session=$(h pane get "$right" | jq -r '.result.pane.agent_session.value // empty'); [ -n "$session" ]; }
poll 40 0.25 session_id || screen "herdr reports no Claude session for $right"
h pane send-text "$right" "Reply with the single word: ready" >/dev/null
h pane send-keys "$right" enter >/dev/null
# A rejected login also writes an assistant line (the API error), so wait for the word itself.
answered() { grep '"type":"assistant"' "$real_home/.claude/projects/"*/"$session.jsonl" | grep -qi '"text":"ready'; }
poll 120 0.5 answered || screen "claude did not answer 'ready' within 60s"
idle() { h pane get "$right" | jq -e '.result.pane.agent_status | IN("idle", "done")'; }
poll 40 0.25 idle || screen "claude did not go idle after answering"

# vhs runs under the same isolation, so its shell's client attaches to this server. The first
# attach shows herdr's welcome, then its settings: Enter, then Escape, dismisses both. The pauses
# are for the viewer: a beat on each state before the next key. Claude Code exits on two ctrl+d
# within about a second, and the shell under it on the third. prefix+l moves the focus right.
# vhs fails a recording with no frame after the last key, hence the final Sleep.
cat > "$HOME/hero.tape" <<TAPE
Output "$out"
Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 520
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
Sleep 2.5s
Ctrl+B
Type "l"
Sleep 1.5s
Ctrl+D
Sleep 0.4s
Ctrl+D
Wait+Screen@10s /Resume this session with/
Sleep 1s
Ctrl+D
Sleep 1.5s
Ctrl+B
Type "u"
Wait+Screen@20s /reopened by undo-close[\s\S]*reopened by undo-close[\s\S]*❯/
Sleep 4s
TAPE
vhs "$HOME/hero.tape"
echo "wrote $out"
