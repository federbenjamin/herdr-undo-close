#!/usr/bin/env bash
# Runs inside a reopened pane's shell, before its first prompt (the setup-shell hook sees
# UNDO_CLOSE_REOPEN=<entry dir>): replay the closed pane's scrollback, delete the entry, then
# resume its agent. Needs no PATH and no herdr: reopen.sh wrote every path into <entry>/launch.
set -u
entry=${1:?usage: reopen_entry.sh <entry dir>}
[ -d "$entry" ] || exit 0

if [ -s "$entry/scrollback.ansi" ]; then
  cat "$entry/scrollback.ansi"
  printf '\n\033[2m── reopened by undo-close ──\033[0m\n'
fi
agent="" session="" claude_bin="" claude_resume_args=""
# shellcheck disable=SC1091
[ -f "$entry/launch" ] && . "$entry/launch"
rm -rf "$entry"

case "$agent" in
  "") ;;
  claude)
    if [ -z "$claude_bin" ]; then
      printf '\033[2mundo-close: claude is not on PATH; the session %s was not resumed.\033[0m\n' "$session"
    elif ! printf '%s' "$session" | grep -Eq '^[A-Za-z0-9-]+$'; then
      printf '\033[2mundo-close: refusing to resume an odd-looking session id.\033[0m\n'
    else
      # shellcheck disable=SC2086
      "$claude_bin" $claude_resume_args --resume="$session"
    fi ;;
  *) printf '\033[2mundo-close: no resume for %s; its scrollback is above.\033[0m\n' "$agent" ;;
esac
