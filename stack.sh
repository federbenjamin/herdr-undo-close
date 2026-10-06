# The closed-pane stack under $state. Source it after lib.sh; never run it. Reads state, keep,
# max_age_days.
#   staging/<pane>/        a snapshot remember.sh is still taking or promoting
#   closed/<seq>-<pane>/   entry.json and scrollback.ansi; the highest seq is the top
#   reopening/<name>/      an entry reopen.sh popped, until the shell hook deletes it
#   seq, seq.lock          the last seq given out, and the lock a push counts under
# shellcheck disable=SC2154  # state, keep and max_age_days are set by lib.sh

stack_staging() { printf '%s/staging/%s' "$state" "$1"; }

# Newest first.
_stack_entries() { { ls -d "$state"/closed/*/ 2>/dev/null || true; } | sort -r; }

# _stack_lock: takes seq.lock and prints its token, or fails after about 1 s. The lock is a
# symlink to <pid>.<epoch>.<random>, which `ln -s` makes or refuses in one step. A lock whose pid
# is gone, or that is a minute old, was left by a killed promote: one waiter at a time (holding
# seq.break) removes it if it is still that lock, then every waiter tries again.
_stack_lock() {
  local me held
  me="$$.$(date +%s).$RANDOM"
  for _ in {1..50}; do
    if ln -s "$me" "$state/seq.lock" 2>/dev/null; then printf '%s' "$me"; return 0; fi
    held=$(readlink "$state/seq.lock" 2>/dev/null) || continue
    if _stack_stale "$held" && mkdir "$state/seq.break" 2>/dev/null; then
      if [ "$(readlink "$state/seq.lock" 2>/dev/null)" = "$held" ]; then rm -f "$state/seq.lock"; fi
      rmdir "$state/seq.break"
      continue
    fi
    sleep 0.02
  done
  return 1
}

_stack_stale() {
  local pid=${1%%.*} at=${1#*.}
  at=${at%%.*}
  ! kill -0 "$pid" 2>/dev/null || [ $(( $(date +%s) - at )) -gt 60 ]
}

_stack_unlock() { if [ "$(readlink "$state/seq.lock" 2>/dev/null)" = "$1" ]; then rm -f "$state/seq.lock"; fi; }

# stack_push <pane>: the pane's staged entry becomes the top of the stack; the stack keeps the
# newest $keep. Fails, with the entry left staged, when it did not reach closed/.
stack_push() {
  local dir n entry lock part
  dir=$(stack_staging "$1")
  mkdir -p "$state/closed"
  lock=$(_stack_lock) || return 1
  n=$(( $(cat "$state/seq" 2>/dev/null || echo 0) + 1 ))
  if ! printf '%s' "$n" > "$state/seq"; then _stack_unlock "$lock"; return 1; fi
  _stack_unlock "$lock"
  entry="$state/closed/$(printf '%010d' "$n")-$1"
  # Put together inside the staging dir, then renamed into closed/ whole: the stack never lists
  # an entry without its files.
  part="$dir/.entry-$n"
  if ! { mkdir "$part" && mv "$dir/entry.json" "$dir/scrollback.ansi" "$part/" && mv "$part" "$entry"; }; then
    return 1
  fi
  rm -rf "$dir"
  _stack_entries | tail -n +"$((keep + 1))" | while read -r old; do rm -rf "$old"; done
}

# stack_pop: moves the top entry to reopening/ and prints its path. Returns 1 when the stack is
# empty, and 2 when the top entry could not be moved (it stays on the stack). A top entry another
# pop took first is passed over for the next one.
stack_pop() {
  local top
  while top=$(_stack_entries | sed -n 1p); [ -n "$top" ]; do
    top=${top%/}
    if mkdir -p "$state/reopening" && mv "$top" "$state/reopening/"; then
      printf '%s\n' "$state/reopening/${top##*/}"
      return 0
    fi
    [ ! -e "$top" ] || return 2
  done
  return 1
}

# stack_restore <entry>: a popped entry goes back on the stack, in its old place.
stack_restore() { mv "$1" "$state/closed/"; }

stack_forget_old() {
  local d
  for d in staging closed reopening; do
    find "$state/$d" -mindepth 1 -maxdepth 1 -type d -mtime +"$max_age_days" -exec rm -rf {} + 2>/dev/null || true
  done
}
