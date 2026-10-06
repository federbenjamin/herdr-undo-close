#!/usr/bin/env bats
# scripts/install.sh is the manifest's build step: one `herdr plugin install` leaves the keys and
# the shell hook in place. It runs against a temp HOME; `herdr config check` goes through the
# guard to the real herdr, which needs no server for that.
load ../helpers/common

setup() {
  isolate
  config=$HOME/.config/herdr/config.toml
  mkdir -p "$HOME/.config/herdr"
  printf '[terminal]\ndefault_shell = "/bin/bash"\nshell_mode = "login"\n' > "$config"
  printf '# my profile\n' > "$HOME/.bash_profile"
}
teardown() { unisolate; }

count() { grep -c -- "$1" "$2" || true; }

@test "install writes the keys block and the shell hook, exit 0" {
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [ "$(count '^# >>> herdr-undo-close keys' "$config")" -eq 1 ]
  [ "$(count 'command = "herdr-undo-close.close"' "$config")" -eq 1 ]
  [ "$(count '^# >>> herdr-undo-close shell hook' "$HOME/.bash_profile")" -eq 1 ]
  [ "$(head -n 1 "$HOME/.bash_profile")" = "# my profile" ]
}

@test "every default key already bound: install still exits 0, names the actions to run, config unchanged, hook written" {
  printf '[[keys.command]]\nkey = "ctrl+d"\ncommand = "mine"\n[[keys.command]]\nkey = "prefix+u"\ncommand = "mine"\n' >> "$config"
  before=$(cat "$config")
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup-keys"* ]]
  [ "$(cat "$config")" = "$before" ]
  [ "$(count '^# >>> herdr-undo-close shell hook' "$HOME/.bash_profile")" -eq 1 ]
}
