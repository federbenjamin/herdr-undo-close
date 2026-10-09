#!/usr/bin/env bash
# Runs at `herdr plugin install` (manifest [[build]]), after the install preview is confirmed:
# checks for jq, then does the two setup steps, so the plugin works from the first new pane
# with no second command. Each step writes one marked block (keys in the herdr config, the
# replay hook in the pane shell's startup file), keeps a backup, and has a remove- twin.
# A step that cannot finish (say, every default key is already bound) is reported, not fatal:
# the plugin still installs and the setup-keys / setup-shell actions stay available.
# herdr shows a build command's output only when it fails, and a toast reaches only an attached
# client, so the report of the steps is also written to
# <XDG_STATE_HOME or ~/.local/state>/herdr-undo-close/install.log (README: Install).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
install_log="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-undo-close/install.log"
log_tmp=""
trap 'if [ -n "$log_tmp" ]; then rm -f "$log_tmp"; fi' EXIT

/bin/sh "$here/scripts/check-deps.sh" || exit 1

# configure runs both steps and reports on stdout (the steps' own stderr merged in).
configure() {
  rc=0
  bash "$here/setup.sh" keys || rc=1
  bash "$here/setup.sh" shell || rc=1
  if [ "$rc" -ne 0 ]; then
    echo "herdr-undo-close: a setup step did not finish (see above). After fixing it, run" \
      "\`herdr plugin action invoke setup-keys --plugin herdr-undo-close\` or \`setup-shell\`."
  fi
}

# The report goes to a new 0600 file that is then renamed over $install_log, so a symlink, hard
# link, or FIFO there is replaced, never written through; a folder there is left alone.
log_dir=$(dirname "$install_log")
if (umask 077 && mkdir -p "$log_dir") 2>/dev/null && log_tmp=$(mktemp "$log_dir/.install.log.XXXXXX" 2>/dev/null); then
  configure 2>&1 | tee "$log_tmp"
  if [ ! -d "$install_log" ]; then
    mv -f "$log_tmp" "$install_log" 2>/dev/null
  fi
else
  configure
fi
exit 0
