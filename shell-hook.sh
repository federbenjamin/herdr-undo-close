# herdr-undo-close shell hook. `setup-shell` writes the lines below the comments into the
# file your pane shell reads at start; or source this file from there yourself.
# A reopened pane carries UNDO_CLOSE_REOPEN=<entry> and UNDO_CLOSE_SCRIPT=<reopen_entry.sh>:
# the hook replays the closed pane's scrollback and resumes its agent before the first prompt,
# so nothing is typed into the pane. Both are unset first so shells the agent spawns don't
# re-trigger it.
if [ -n "${UNDO_CLOSE_REOPEN:-}" ]; then
  _undo_close_entry=$UNDO_CLOSE_REOPEN; _undo_close_script=$UNDO_CLOSE_SCRIPT
  unset UNDO_CLOSE_REOPEN UNDO_CLOSE_SCRIPT
  bash "$_undo_close_script" "$_undo_close_entry"
  unset _undo_close_entry _undo_close_script
fi
