#!/usr/bin/env bash
# Runs at `herdr plugin install` (manifest [[build]]), after the install preview is confirmed:
# checks for jq, then does the two setup steps, so the plugin works from the first new pane
# with no second command. Each step writes one marked block (keys in the herdr config, the
# replay hook in the pane shell's startup file), keeps a backup, and has a remove- twin.
# A step that cannot finish (say, every default key is already bound) is reported, not fatal:
# the plugin still installs and the setup-keys / setup-shell actions stay available.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
/bin/sh "$here/scripts/check-deps.sh" || exit 1
rc=0
bash "$here/setup.sh" keys || rc=1
bash "$here/setup.sh" shell || rc=1
if [ "$rc" -ne 0 ]; then
  echo "herdr-undo-close: a setup step did not finish (see above). After fixing it, run" \
    "\`herdr plugin action invoke setup-keys --plugin herdr-undo-close\` or \`setup-shell\`."
fi
exit 0
