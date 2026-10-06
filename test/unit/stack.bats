#!/usr/bin/env bats
# stack.sh, the closed-pane stack: the seq lock, publishing an entry, and the stack order. No herdr.
load ../helpers/common

setup() {
  isolate
  # shellcheck disable=SC2034  # read by stack.sh
  state=$HERDR_PLUGIN_STATE_DIR keep=20 max_age_days=7
  . "$REPO_ROOT/stack.sh"
}
teardown() { unisolate; }

# staged <pane>: a staged entry for <pane>, as promote leaves it before the push.
staged() {
  mkdir -p "$(stack_staging "$1")"
  echo '{}' > "$(stack_staging "$1")/entry.json"
  : > "$(stack_staging "$1")/scrollback.ansi"
}

# hold_lock <pid> [<seconds ago>]: seq.lock as a push by <pid> takes it.
hold_lock() { ln -s "$1.$(( $(date +%s) - ${2:-0} )).1" "$state/seq.lock"; }
# A pid no process has.
dead_pid() { sh -c 'echo $$'; }
# The seq read takes 0.3 s after reading, so two counts that overlap read the same value.
slow_seq_read() {
  cat() { command cat "$@"; [ "$1" != "$state/seq" ] || sleep 0.3; }
}
seqs() { ls "$state/closed" | cut -c1-10 | sort -u | tr '\n' ' '; }

@test "a held seq lock holds the push back until it is released" {
  hold_lock $$
  staged w1:p1
  stack_push w1:p1 &
  sleep 0.3
  [ ! -e "$state/seq" ]
  [ -z "$(ls "$state/closed" 2>/dev/null)" ]
  rm "$state/seq.lock"
  wait
  [ "$(cat "$state/seq")" = 1 ]
  [ -f "$state/closed/0000000001-w1:p1/entry.json" ]
  [ ! -e "$(stack_staging w1:p1)" ]
}

@test "a push that cannot get a live lock fails and leaves the pane staged" {
  hold_lock $$
  staged w1:p1
  run stack_push w1:p1
  [ "$status" -ne 0 ]
  [ ! -e "$state/seq" ]
  [ -z "$(ls "$state/closed")" ]
  [ -f "$(stack_staging w1:p1)/entry.json" ]
  [ -L "$state/seq.lock" ]
}

@test "two pushes behind a lock a dead promote left take it over one at a time" {
  hold_lock "$(dead_pid)"
  staged w1:p1
  staged w1:p2
  slow_seq_read
  stack_push w1:p1 & a=$!
  stack_push w1:p2 & b=$!
  wait "$a"
  wait "$b"
  [ "$(seqs)" = "0000000001 0000000002 " ]
  [ "$(cat "$state/seq")" = 2 ]
  [ ! -e "$state/seq.lock" ]
  [ ! -e "$state/seq.break" ]
}

@test "of two waiters on a dead promote's lock, only one removes it" {
  hold_lock "$(dead_pid)"
  stale=$(readlink "$state/seq.lock")
  sync=$BATS_TEST_TMPDIR
  # A removal of the dead lock waits for a second one; a second one waits until the lock is
  # taken again, so without one-at-a-time it would remove a live lock.
  rm() {
    if [ "$*" = "-f $state/seq.lock" ] && [ "$(readlink "$state/seq.lock")" = "$stale" ]; then
      if mkdir "$sync/first" 2>/dev/null; then
        for _ in {1..15}; do [ ! -e "$sync/second" ] || break; sleep 0.02; done
      else
        touch "$sync/second"
        for _ in {1..25}; do
          case "$(readlink "$state/seq.lock")" in ''|"$stale") sleep 0.02 ;; *) break ;; esac
        done
      fi
    fi
    command rm "$@"
  }
  staged w1:p1
  staged w1:p2
  slow_seq_read
  stack_push w1:p1 & a=$!
  stack_push w1:p2 & b=$!
  wait "$a"
  wait "$b"
  [ "$(seqs)" = "0000000001 0000000002 " ]
}

@test "a lock a minute old is taken over even when its pid is alive" {
  hold_lock $$ 120
  staged w1:p1
  run stack_push w1:p1
  [ "$status" -eq 0 ]
  [ -f "$state/closed/0000000001-w1:p1/entry.json" ]
  [ ! -e "$state/seq.lock" ]
}

@test "a push whose lock was taken over leaves the new holder's lock in place" {
  other="$$.$(date +%s).2"
  # While the push counts, its lock is removed and another push takes it.
  cat() {
    command cat "$@"
    if [ "$1" = "$state/seq" ]; then command rm -f "$state/seq.lock"; ln -s "$other" "$state/seq.lock"; fi
  }
  staged w1:p1
  stack_push w1:p1
  [ "$(readlink "$state/seq.lock")" = "$other" ]
}

@test "a push that cannot write the seq fails, releases the lock, and leaves the pane staged" {
  mkdir "$state/seq"
  staged w1:p1
  run stack_push w1:p1
  [ "$status" -ne 0 ]
  [ ! -e "$state/seq.lock" ]
  [ -z "$(ls "$state/closed")" ]
  [ -f "$(stack_staging w1:p1)/entry.json" ]
}

@test "an entry shows on the stack only once it is whole" {
  staged w1:p1
  # At every move stack_push makes, each entry the stack lists has both files.
  mv() {
    local e
    for e in $(_stack_entries); do
      [ -f "$e/entry.json" ] && [ -f "$e/scrollback.ansi" ] || echo "$e" >> "$BATS_TEST_TMPDIR/partial"
    done
    command mv "$@"
  }
  stack_push w1:p1
  [ ! -e "$BATS_TEST_TMPDIR/partial" ]
  [ -f "$state/closed/0000000001-w1:p1/scrollback.ansi" ]
}

@test "a push whose files cannot all be moved fails and puts nothing on the stack" {
  staged w1:p1
  rm "$(stack_staging w1:p1)/scrollback.ansi"
  run stack_push w1:p1
  [ "$status" -ne 0 ]
  [ -z "$(ls "$state/closed")" ]
}

@test "a push into a closed/ it cannot write fails and leaves the pane staged" {
  staged w1:p1
  mkdir -p "$state/closed"
  chmod 500 "$state/closed"
  run stack_push w1:p1
  chmod 700 "$state/closed"
  [ "$status" -ne 0 ]
  [ -z "$(ls "$state/closed")" ]
  [ -d "$(stack_staging w1:p1)" ]
}

@test "pushes number in order and pop takes the newest first" {
  staged w1:p1
  stack_push w1:p1
  staged w1:p2
  stack_push w1:p2
  [ "$(ls "$state/closed")" = $'0000000001-w1:p1\n0000000002-w1:p2' ]

  run stack_pop
  [ "$status" -eq 0 ]
  [ "$output" = "$state/reopening/0000000002-w1:p2" ]
  [ "$(ls "$state/closed")" = 0000000001-w1:p1 ]

  run stack_pop
  [ "$output" = "$state/reopening/0000000001-w1:p1" ]

  run stack_pop
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a top entry that cannot be moved fails the pop with 2 and stays on the stack" {
  staged w1:p1
  stack_push w1:p1
  mkdir -p "$state/reopening/0000000001-w1:p1/left-over"
  run stack_pop
  [ "$status" -eq 2 ]
  [ "$(ls "$state/closed")" = 0000000001-w1:p1 ]
}

@test "a top entry another pop takes first is passed over for the next one" {
  staged w1:p1
  stack_push w1:p1
  staged w1:p2
  stack_push w1:p2
  # The other pop moves the top entry away just before this one's move.
  mv() {
    if [ "$1" = "$state/closed/0000000002-w1:p2" ]; then command mv "$1" "$BATS_TEST_TMPDIR/"; fi
    command mv "$@"
  }
  run stack_pop
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "$state/reopening/0000000001-w1:p1" ]
  [ -z "$(ls "$state/closed")" ]
}

@test "a pop into a reopening/ it cannot write fails with 2" {
  staged w1:p1
  stack_push w1:p1
  mkdir -p "$state/reopening"
  chmod 500 "$state/reopening"
  run stack_pop
  chmod 700 "$state/reopening"
  [ "$status" -eq 2 ]
  [ "$(ls "$state/closed")" = 0000000001-w1:p1 ]
}
