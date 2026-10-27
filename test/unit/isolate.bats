#!/usr/bin/env bats
# isolate, from a bash started with the caller's shell state: a function, alias or variable the
# caller has must not reach the test, nor any process the test starts.
load ../helpers/common

setup() {
  isolate
  # seen.sh prints the caller's names this shell and a child of it can still see.
  cat > "$HOME/seen.sh" <<'SEEN'
declare -F caller_fn caller_rc_fn || true
alias caller_alias 2>/dev/null || true
echo "var=${CALLER_VAR-}"
bash -c 'declare -F caller_fn || true; echo "child var=${CALLER_VAR-}"'
SEEN
  # shellcheck disable=SC2016  # expanded by the bash that runs it
  probe='seen=$1; . "$REPO_ROOT/test/helpers/common.bash"; . "$seen"; echo ---; isolate; . "$seen"; unisolate'
}
teardown() { unisolate; }

@test "isolate drops a function and a variable the caller exported, for the test and its children" {
  run env 'BASH_FUNC_caller_fn%%=() { echo caller; }' CALLER_VAR=1 bash -c "$probe" probe "$HOME/seen.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' caller_fn var=1 caller_fn 'child var=1' --- var= 'child var=')" ]
}

@test "isolate drops a function and an alias the caller's BASH_ENV defined" {
  printf 'caller_rc_fn() { :; }\nalias caller_alias=true\n' > "$HOME/rc"
  run env BASH_ENV="$HOME/rc" bash -c "$probe" probe "$HOME/seen.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' caller_rc_fn "alias caller_alias='true'" var= 'child var=' --- var= 'child var=')" ]
}
