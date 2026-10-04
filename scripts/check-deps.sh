#!/bin/sh
# Runs at install (manifest [[build]]): the plugin is shell + jq, nothing to compile. Fail the
# install with a clear message when jq is missing, since every script needs it.
if ! command -v jq >/dev/null 2>&1; then
  echo "herdr-undo-close needs jq (https://jqlang.github.io/jq/): brew install jq / apt install jq" >&2
  exit 1
fi
