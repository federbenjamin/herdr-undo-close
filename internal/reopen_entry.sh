#!/usr/bin/env bash
# Runs inside a reopened pane's shell, before its first prompt (the setup-shell hook sees
# UNDO_CLOSE_REOPEN=<entry dir>): replay the closed pane's scrollback, delete the entry, then
# resume its agent, or start a fresh claude when its session has no conversation file. Needs no
# PATH and no herdr: reopen.sh wrote every path into <entry>/launch.
set -u
entry=${1:?usage: reopen_entry.sh <entry dir>}
[ -d "$entry" ] || exit 0

dim() { printf '\033[2m%s\033[0m\n' "$1"; }
note() { dim "undo-close: $1"; }

if [ -s "$entry/scrollback.ansi" ]; then
  cat "$entry/scrollback.ansi"
  printf '\n'; dim '── reopened by undo-close ──'
fi
agent="" session="" claude_bin="" claude_resume_args=""
# shellcheck disable=SC1091
[ -f "$entry/launch" ] && . "$entry/launch"
rm -rf "$entry"

case "$agent" in
  "") ;;
  claude)
    if [ -z "$claude_bin" ]; then
      note "claude is not on PATH; the session $session was not resumed."
    elif ! printf '%s' "$session" | grep -Eq '^[A-Za-z0-9-]+$'; then
      note "refusing to resume an odd-looking session id."
    # Claude Code's --resume finds a session under any project folder, so any one is a hit.
    elif compgen -G "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/$session.jsonl" >/dev/null; then
      # shellcheck disable=SC2086
      "$claude_bin" $claude_resume_args --resume="$session"
    else
      note "claude session $session was never saved (no conversation file); starting a fresh claude here."
      # shellcheck disable=SC2086
      "$claude_bin" $claude_resume_args
    fi ;;
  *) note "no resume for $agent; its scrollback is above." ;;
esac
