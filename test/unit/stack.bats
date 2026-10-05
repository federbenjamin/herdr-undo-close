#!/usr/bin/env bats
# stack.sh, the closed-pane stack: the seq lock and the stack order. No herdr.
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

@test "a held seq lock holds the push back until it is released" {
  mkdir "$state/seq.lock"
  staged w1:p1
  stack_push w1:p1 &
  sleep 0.3
  [ ! -e "$state/seq" ]
  [ -z "$(ls "$state/closed" 2>/dev/null)" ]
  rmdir "$state/seq.lock"
  wait
  [ "$(cat "$state/seq")" = 1 ]
  [ -f "$state/closed/0000000001-w1:p1/entry.json" ]
  [ ! -e "$(stack_staging w1:p1)" ]
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
