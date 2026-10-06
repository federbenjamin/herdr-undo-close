load ../helpers/common
load ../helpers/fake-herdr

# setup.sh runs against a temp HOME; its `herdr config check` calls go through the guard to the
# real herdr, which needs no server for that.

setup() {
  isolate
  config=$HOME/.config/herdr/config.toml
  mkdir -p "$HOME/.config/herdr"
  keys_begin='# >>> herdr-undo-close keys'
  keys_begin_line='# >>> herdr-undo-close keys (managed: `setup-keys` writes this block, `remove-keys` deletes it)'
  shell_begin='# >>> herdr-undo-close shell hook'
}
teardown() { unisolate; }

setup_sh() { bash "$REPO_ROOT/setup.sh" "$@"; }
count() { grep -c -- "$1" "$2" || true; }

# terminal_config <default_shell> <shell_mode> writes the [terminal] settings profile_path reads.
terminal_config() {
  printf '[terminal]\ndefault_shell = "%s"\nshell_mode = "%s"\n' "$1" "$2" > "$config"
}

@test "keys appends one fenced block binding ctrl+d to close and prefix+u to reopen" {
  printf '# mine\n' > "$config"
  run setup_sh keys
  [ "$status" -eq 0 ]
  [ "$(count "^$keys_begin" "$config")" -eq 1 ]
  [ "$(count '^# <<< herdr-undo-close keys' "$config")" -eq 1 ]
  [ "$(head -n 1 "$config")" = "# mine" ]
  block=$(sed -n "/^$keys_begin/,/^# <<< herdr-undo-close keys/p" "$config")
  [[ "$block" == *'key = "ctrl+d"'* ]]
  [[ "$block" == *'command = "herdr-undo-close.close"'* ]]
  [[ "$block" == *'key = "prefix+u"'* ]]
  [[ "$block" == *'command = "herdr-undo-close.reopen"'* ]]
  [[ "$block" == *'type = "plugin_action"'* ]]
}

@test "keys creates the config when there is none" {
  [ ! -e "$config" ]
  run setup_sh keys
  [ "$status" -eq 0 ]
  [ "$(count "^$keys_begin" "$config")" -eq 1 ]
}

@test "a second keys replaces the block: still one block" {
  printf '# mine\n' > "$config"
  setup_sh keys
  run setup_sh keys
  [ "$status" -eq 0 ]
  [ "$(count "^$keys_begin" "$config")" -eq 1 ]
  [ "$(count 'key = "ctrl+d"' "$config")" -eq 1 ]
  [ "$(count 'key = "prefix+u"' "$config")" -eq 1 ]
}

@test "a key already bound outside the block is skipped and named" {
  cat > "$config" <<'TOML'
[[keys.command]]
key = "ctrl+d"
type = "shell"
command = "true"
TOML
  run setup_sh keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"Left ctrl+d alone"* ]]
  [ "$(count 'key = "ctrl+d"' "$config")" -eq 1 ]
  [ "$(count 'key = "prefix+u"' "$config")" -eq 1 ]
  [ "$(count 'herdr-undo-close.reopen' "$config")" -ge 1 ]
}

@test "a mention of a key in a comment does not count as bound" {
  printf '# ctrl+d is nice\n' > "$config"
  run setup_sh keys
  [ "$status" -eq 0 ]
  [ "$(count 'key = "ctrl+d"' "$config")" -eq 1 ]
}

@test "every key already bound: refused, file unchanged" {
  cat > "$config" <<'TOML'
[[keys.command]]
key = "ctrl+d"
type = "shell"
command = "true"

[[keys.command]]
key = "prefix+u"
type = "shell"
command = "true"
TOML
  cp "$config" "$BATS_TEST_TMPDIR/before"
  run setup_sh keys
  [ "$status" -ne 0 ]
  [[ "$output" == *"Every default key is already bound"* ]]
  cmp "$config" "$BATS_TEST_TMPDIR/before"
}

@test "a begin marker with no end marker: refused, file unchanged" {
  printf '[terminal]\nshell_mode = "login"\n%s\n# something\n' "$keys_begin_line" > "$config"
  cp "$config" "$BATS_TEST_TMPDIR/before"
  run setup_sh keys
  [ "$status" -ne 0 ]
  [[ "$output" == *"no end marker"* ]]
  cmp "$config" "$BATS_TEST_TMPDIR/before"
}

@test "a config that fails herdr config check: refused, file unchanged" {
  printf 'this is = = not toml [[[\n' > "$config"
  cp "$config" "$BATS_TEST_TMPDIR/before"
  run setup_sh keys
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not pass"* ]]
  cmp "$config" "$BATS_TEST_TMPDIR/before"
}

@test "a new config that fails the check leaves the file byte-identical, previous block included" {
  printf '# mine\n' > "$config"
  setup_sh keys
  cp "$config" "$BATS_TEST_TMPDIR/before"
  fake_herdr
  # The fake does not see which file a check reads (HERDR_CONFIG_PATH); this wrapper logs it.
  printf '#!/usr/bin/env bash\necho "${HERDR_CONFIG_PATH-} $*" >> "$HOME/fake/checked"\nexec "$HOME/fake/herdr" "$@"\n' > "$HOME/fake/logged"
  chmod +x "$HOME/fake/logged"
  export HERDR_BIN_PATH="$HOME/fake/logged" HERDR_CONFIG_PATH="$config"
  reply 2 0 ''
  reply 3 1 'config parse error'
  run setup_sh keys
  [ "$status" -ne 0 ]
  [[ "$output" == *"was not changed"* ]]
  cmp "$config" "$BATS_TEST_TMPDIR/before"
  [ ! -e "$config.undo-close-new" ]
  [ "$(grep ' config check$' "$HOME/fake/checked")" = "$config config check"$'\n'"$config.undo-close-new config check" ]
}

@test "keys writes through a symlinked config and leaves it a symlink" {
  mkdir "$HOME/dotfiles"
  printf '# mine\n' > "$HOME/dotfiles/config.toml"
  ln -s "$HOME/dotfiles/config.toml" "$config"
  run setup_sh keys
  [ "$status" -eq 0 ]
  [ -L "$config" ]
  [ "$(head -n 1 "$HOME/dotfiles/config.toml")" = "# mine" ]
  [ "$(count "^$keys_begin" "$HOME/dotfiles/config.toml")" -eq 1 ]
  [ ! -e "$config.undo-close-new" ]
}

@test "the first backup is kept on a second run" {
  printf '# original\n' > "$config"
  setup_sh keys
  [ "$(cat "$config.undo-close-backup")" = "# original" ]
  printf '# edited later\n' >> "$config"
  setup_sh keys
  [ "$(cat "$config.undo-close-backup")" = "# original" ]
}

@test "remove-keys deletes only the block" {
  printf '# before\n[terminal]\nshell_mode = "login"\n' > "$config"
  setup_sh keys
  run setup_sh remove-keys
  [ "$status" -eq 0 ]
  [ "$(count 'undo-close' "$config")" -eq 0 ]
  [ "$(count 'plugin_action' "$config")" -eq 0 ]
  [ "$(head -n 1 "$config")" = "# before" ]
  [ "$(count '^shell_mode = "login"' "$config")" -eq 1 ]
  run "$HERDR_BIN_PATH" config check
  [ "$status" -eq 0 ]
}

@test "remove-keys with no block changes nothing" {
  printf '# mine\n' > "$config"
  cp "$config" "$BATS_TEST_TMPDIR/before"
  run setup_sh remove-keys
  [ "$status" -eq 0 ]
  cmp "$config" "$BATS_TEST_TMPDIR/before"
}

# shell: which profile gets the hook

@test "shell: writes the hook block, nothing else changes" {
  terminal_config /bin/bash login
  printf '# my profile\n' > "$HOME/.bash_profile"
  run setup_sh shell
  [ "$status" -eq 0 ]
  [ "$(count "^$shell_begin" "$HOME/.bash_profile")" -eq 1 ]
  [ "$(count 'UNDO_CLOSE_REOPEN' "$HOME/.bash_profile")" -ge 1 ]
  [ "$(head -n 1 "$HOME/.bash_profile")" = "# my profile" ]
  bash -n "$HOME/.bash_profile"
}

@test "shell: bash login uses the first existing of .bash_profile, .bash_login, .profile" {
  terminal_config /bin/bash login
  : > "$HOME/.bash_login"
  : > "$HOME/.profile"
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.bash_login")" -eq 1 ]
  [ ! -s "$HOME/.profile" ]
  [ ! -e "$HOME/.bash_profile" ]
}

@test "shell: bash login prefers .bash_profile over .profile" {
  terminal_config /bin/bash login
  : > "$HOME/.bash_profile"
  : > "$HOME/.profile"
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.bash_profile")" -eq 1 ]
  [ ! -s "$HOME/.profile" ]
}

@test "shell: bash login with only .profile uses .profile" {
  terminal_config /bin/bash login
  : > "$HOME/.profile"
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.profile")" -eq 1 ]
  [ ! -e "$HOME/.bash_profile" ]
}

@test "shell: bash login with none of them creates .bash_profile" {
  terminal_config /bin/bash login
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.bash_profile")" -eq 1 ]
}

@test "shell: bash non-login uses .bashrc" {
  terminal_config /bin/bash non_login
  : > "$HOME/.bash_profile"
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.bashrc")" -eq 1 ]
  [ ! -s "$HOME/.bash_profile" ]
}

@test "shell: zsh login uses .zprofile" {
  terminal_config /bin/zsh login
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.zprofile")" -eq 1 ]
  [ ! -e "$HOME/.zshrc" ]
}

@test "shell: zsh non-login uses .zshrc" {
  terminal_config /bin/zsh non_login
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.zshrc")" -eq 1 ]
  [ ! -e "$HOME/.zprofile" ]
}

@test "shell: shell_mode auto is login on Darwin only" {
  terminal_config /bin/bash auto
  setup_sh shell
  if [ "$(uname)" = Darwin ]; then expected=.bash_profile; else expected=.bashrc; fi
  [ "$(count "^$shell_begin" "$HOME/$expected")" -eq 1 ]
}

@test "shell: zsh with shell_mode auto follows the same rule" {
  terminal_config /bin/zsh auto
  setup_sh shell
  if [ "$(uname)" = Darwin ]; then expected=.zprofile; else expected=.zshrc; fi
  [ "$(count "^$shell_begin" "$HOME/$expected")" -eq 1 ]
}

@test "shell: writes through a symlinked profile and leaves it a symlink" {
  terminal_config /bin/bash login
  mkdir "$HOME/dotfiles"
  printf '# my profile\n' > "$HOME/dotfiles/bash_profile"
  ln -s "$HOME/dotfiles/bash_profile" "$HOME/.bash_profile"
  run setup_sh shell
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bash_profile" ]
  [ "$(head -n 1 "$HOME/dotfiles/bash_profile")" = "# my profile" ]
  [ "$(count "^$shell_begin" "$HOME/dotfiles/bash_profile")" -eq 1 ]
}

@test "shell: a second run replaces the block, still one" {
  terminal_config /bin/bash login
  setup_sh shell
  setup_sh shell
  [ "$(count "^$shell_begin" "$HOME/.bash_profile")" -eq 1 ]
}

@test "remove-shell deletes only the hook block" {
  terminal_config /bin/bash login
  printf '# my profile\nexport A=1\n' > "$HOME/.bash_profile"
  setup_sh shell
  run setup_sh remove-shell
  [ "$status" -eq 0 ]
  [ "$(count 'undo-close' "$HOME/.bash_profile")" -eq 0 ]
  [ "$(count 'UNDO_CLOSE' "$HOME/.bash_profile")" -eq 0 ]
  [ "$(head -n 1 "$HOME/.bash_profile")" = "# my profile" ]
  [ "$(count '^export A=1' "$HOME/.bash_profile")" -eq 1 ]
}
