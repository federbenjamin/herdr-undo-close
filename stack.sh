# The closed-pane stack under $state. Source it after lib.sh; never run it. Reads state, keep,
# max_age_days.
#   staging/<pane>/        a snapshot remember.sh is still taking or promoting
#   closed/<seq>-<pane>/   entry.json and scrollback.ansi; the highest seq is the top
#   reopening/<name>/      an entry reopen.sh popped, until the shell hook deletes it
# shellcheck disable=SC2154  # state, keep and max_age_days are set by lib.sh

stack_staging() { printf '%s/staging/%s' "$state" "$1"; }

# Newest first.
_stack_entries() { { ls -d "$state"/closed/*/ 2>/dev/null || true; } | sort -r; }

# stack_push <pane>: the pane's staged entry becomes the top of the stack; the stack keeps the
# newest $keep.
stack_push() {
  local dir n entry
  dir=$(stack_staging "$1")
  mkdir -p "$state/closed"
  # Two promotes at once must not take the same number. A lock a killed promote left behind is
  # waited out for 1 s, then ignored, so it never blocks the stack for good.
  for _ in {1..50}; do mkdir "$state/seq.lock" 2>/dev/null && break; sleep 0.02; done
  n=$(( $(cat "$state/seq" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$state/seq"
  rmdir "$state/seq.lock" 2>/dev/null || true
  entry="$state/closed/$(printf '%010d' "$n")-$1"
  mkdir "$entry" && mv "$dir/entry.json" "$dir/scrollback.ansi" "$entry/" && rm -rf "$dir"
  _stack_entries | tail -n +"$((keep + 1))" | while read -r old; do rm -rf "$old"; done
}

# stack_pop: moves the top entry to reopening/ and prints its path; fails when the stack is empty.
stack_pop() {
  local top
  top=$(_stack_entries | sed -n 1p)
  [ -n "$top" ] || return 1
  top=${top%/}
  mkdir -p "$state/reopening"
  mv "$top" "$state/reopening/" || return 1
  printf '%s\n' "$state/reopening/${top##*/}"
}

# stack_restore <entry>: a popped entry goes back on the stack, in its old place.
stack_restore() { mv "$1" "$state/closed/"; }

stack_forget_old() {
  local d
  for d in staging closed reopening; do
    find "$state/$d" -mindepth 1 -maxdepth 1 -type d -mtime +"$max_age_days" -exec rm -rf {} + 2>/dev/null || true
  done
}
