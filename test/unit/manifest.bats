#!/usr/bin/env bats
# herdr-plugin.toml against what setup.sh writes and takes: an action a written key names, or a
# subcommand setup.sh takes, that the manifest does not declare would fail only at runtime.
load ../helpers/common

setup() {
  isolate
  config=$HOME/.config/herdr/config.toml
  mkdir -p "$HOME/.config/herdr"
  manifest=$REPO_ROOT/herdr-plugin.toml
}
teardown() { unisolate; }

@test "every action a key written by setup-keys runs is declared in the manifest" {
  printf '# mine\n' > "$config"
  bash "$REPO_ROOT/setup.sh" keys
  ids=$(sed -n 's/^command = "herdr-undo-close\.\(.*\)"$/\1/p' "$config")
  [ -n "$ids" ]
  for id in $ids; do
    grep -qxF "id = \"$id\"" "$manifest"
  done
}

@test "every setup.sh subcommand is an action command in the manifest" {
  run bash "$REPO_ROOT/setup.sh"
  [ "$status" -eq 2 ]
  subs=${output#usage: setup.sh }
  [ "$subs" != "$output" ]
  for sub in ${subs//|/ }; do
    grep -qxF "command = [\"bash\", \"setup.sh\", \"$sub\"]" "$manifest"
  done
}
