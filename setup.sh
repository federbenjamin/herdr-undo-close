#!/usr/bin/env bash
# Install or remove what a herdr plugin cannot ship in its manifest: keys and a shell hook.
#
#   setup.sh keys          the default keybindings (ctrl+d → close, prefix+u → reopen) as one
#                          marker-fenced block at the end of the config herdr loads
#   setup.sh shell         the shell hook (shell-hook.sh, minus its comments) as one block at
#                          the end of the file the pane shell reads at start
#   setup.sh remove-keys   delete the keys block
#   setup.sh remove-shell  delete the shell block
#
# Rules: never touch anything outside the block; leave a key that is already bound elsewhere
# alone and say so; keep the first backup of a file for good; pass a new config through
# `herdr config check` before it replaces the old one; write through a symlinked file.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# key | action id | description
bindings=(
  "ctrl+d|close|undo-close: close the focused pane the right way, and remember it"
  "prefix+u|reopen|undo-close: reopen the last closed pane"
)

config_path() {
  if [ "${HERDR_CONFIG_PATH+set}" = set ]; then printf '%s' "$HERDR_CONFIG_PATH"
  elif [ -n "${XDG_CONFIG_HOME:-}" ]; then printf '%s/herdr/config.toml' "$XDG_CONFIG_HOME"
  else printf '%s/.config/herdr/config.toml' "$HOME"; fi
}

# One `key = "..."` value from the [terminal] section of the config herdr loads, or nothing.
config_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$(config_path)" 2>/dev/null | head -n 1
}

# The file the pane shell reads at start. Herdr's shell_mode decides whether a pane shell is a
# login shell: "login" everywhere, "non_login" nowhere, "auto" (the default) on macOS only.
# A login bash reads the first of .bash_profile/.bash_login/.profile; a login zsh reads
# .zprofile; otherwise bash reads .bashrc and zsh .zshrc.
profile_path() {
  local shell mode login=0
  shell=$(basename "$(config_value default_shell)")
  shell=${shell:-$(basename "${SHELL:-bash}")}
  mode=$(config_value shell_mode); mode=${mode:-auto}
  case "$mode" in login) login=1 ;; non_login) login=0 ;; *) [ "$(uname)" = Darwin ] && login=1 ;; esac
  case "$shell" in
    zsh)  if [ "$login" = 1 ]; then printf '%s/.zprofile' "${ZDOTDIR:-$HOME}"; else printf '%s/.zshrc' "${ZDOTDIR:-$HOME}"; fi ;;
    bash) if [ "$login" = 1 ]; then
            for f in .bash_profile .bash_login .profile; do [ -f "$HOME/$f" ] && { printf '%s/%s' "$HOME" "$f"; return; }; done
            printf '%s/.bash_profile' "$HOME"
          else printf '%s/.bashrc' "$HOME"; fi ;;
    sh|dash) printf '%s/.profile' "$HOME" ;;
    *) return 1 ;;
  esac
}

# The hook as it is written: shell-hook.sh without its comment lines.
hook_lines() { grep -v '^#' "$here/shell-hook.sh"; }

# The file without the block fenced by $1 and $2. A begin marker with no end marker is refused
# (deleting to EOF would eat the user's file). Runs in $(…), so call it as
# rest=$(strip_block …) || exit 1.
strip_block() {
  if grep -qxF "$1" "$3" && ! grep -qxF "$2" "$3"; then
    fail "undo-close" "$3 has the begin marker of a $plugin block but no end marker; fix it by hand first, nothing was changed."
  fi
  awk -v b="$1" -v e="$2" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$3"
}

# The first backup of a file is the original; later runs do not overwrite it.
backup() { [ -e "$1.undo-close-backup" ] || cp -p "$1" "$1.undo-close-backup"; }

# write_block <path> <rest> <begin> <end> <lines...>: <path>.undo-close-new, holding <rest> (the
# file without the block) and the block at its end. <path> itself is not touched.
write_block() {
  local path=$1 rest=$2 begin=$3 end=$4; shift 4
  { [ -n "$rest" ] && printf '%s\n\n' "$rest"
    printf '%s\n' "$begin"; printf '%s\n' "$@"; printf '%s\n' "$end"
  } > "$path.undo-close-new"
}

# install_block <path>: the candidate write_block made replaces <path>'s content. Written through,
# not moved, so a symlinked dotfile stays a symlink.
install_block() {
  backup "$1"
  cat "$1.undo-close-new" > "$1"
  rm -f "$1.undo-close-new"
}

remove_block() {
  local path=$1 begin=$2 end=$3 rest
  [ -f "$path" ] || { notify "undo-close" "No $path, nothing to remove."; return 0; }
  grep -qxF "$begin" "$path" || { notify "undo-close" "No $plugin block in $path, nothing to remove."; return 0; }
  rest=$(strip_block "$begin" "$end" "$path") || exit 1
  backup "$path"
  if [ -n "$rest" ]; then printf '%s\n' "$rest" > "$path"; else : > "$path"; fi
  notify "undo-close" "Removed the $plugin block from $path."
}

reload() { "$herdr" server reload-config >/dev/null 2>&1 || echo "No running herdr to reload; the keys are live from the next start."; }

keys_begin="# >>> $plugin keys (managed: \`setup-keys\` writes this block, \`remove-keys\` deletes it)"
keys_end="# <<< $plugin keys"
shell_begin="# >>> $plugin shell hook (managed: \`setup-shell\` writes this block, \`remove-shell\` deletes it)"
shell_end="# <<< $plugin shell hook"

case "${1:-}" in
  keys)
    path=$(config_path)
    [ -n "$path" ] || fail "undo-close: not installed" "HERDR_CONFIG_PATH is set but empty, so herdr loads no config and there is nowhere to put a key."
    mkdir -p "$(dirname "$path")"; [ -f "$path" ] || : > "$path"
    "$herdr" config check >/dev/null 2>&1 || fail "undo-close: not installed" "$path does not pass \`herdr config check\`; fix it first, nothing was changed."
    rest=$(strip_block "$keys_begin" "$keys_end" "$path") || exit 1
    installed="" skipped="" lines=()
    for entry in "${bindings[@]}"; do
      key=${entry%%|*}; rem=${entry#*|}; action=${rem%%|*}; desc=${rem#*|}
      # Bound elsewhere means a real `key = "..."` line, not a mention in a comment.
      if printf '%s\n' "$rest" | grep -Eq "^[[:space:]]*key[[:space:]]*=[[:space:]]*\"$(printf '%s' "$key" | sed 's/[+]/\\&/g')\""; then
        skipped="$skipped $key"; continue
      fi
      installed="$installed $key"
      lines+=("[[keys.command]]" "key = \"$key\"" "type = \"plugin_action\"" "command = \"$plugin.$action\"" "description = \"$desc\"" "")
    done
    installed=${installed# }; skipped=${skipped# }
    [ -n "$installed" ] || fail "undo-close: not installed" "Every default key is already bound in $path ($skipped), so nothing was changed. Bind $plugin.close and $plugin.reopen to keys of your own."
    write_block "$path" "$rest" "$keys_begin" "$keys_end" "${lines[@]}"
    HERDR_CONFIG_PATH="$path.undo-close-new" "$herdr" config check >/dev/null 2>&1 || {
      rm -f "$path.undo-close-new"
      fail "undo-close: not installed" "The new config did not pass \`herdr config check\`; $path was not changed."
    }
    install_block "$path"
    reload
    msg="Bound $installed in $path."
    [ -z "$skipped" ] || msg="$msg Left $skipped alone, already bound there; bind $plugin.close / $plugin.reopen yourself."
    notify "undo-close" "$msg"
    ;;
  shell)
    path=$(profile_path) || fail "undo-close: not installed" "The pane shell is neither bash nor zsh; source shell-hook.sh from the file it reads at start."
    [ -f "$path" ] || : > "$path"
    lines=(); while IFS= read -r l; do lines+=("$l"); done < <(hook_lines)
    rest=$(strip_block "$shell_begin" "$shell_end" "$path") || exit 1
    write_block "$path" "$rest" "$shell_begin" "$shell_end" "${lines[@]}"
    install_block "$path"
    notify "undo-close" "Wrote the shell hook to $path. New panes pick it up; existing ones do not."
    ;;
  remove-keys)  remove_block "$(config_path)" "$keys_begin" "$keys_end"; reload ;;
  remove-shell) path=$(profile_path) || exit 0; remove_block "$path" "$shell_begin" "$shell_end" ;;
  *) echo "usage: setup.sh keys|shell|remove-keys|remove-shell" >&2; exit 2 ;;
esac
