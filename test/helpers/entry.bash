# Entries from the saved herdr replies in test/fixtures/. Load it after common.bash.

# build_entry <dir> prints entry.jq's result for the replies in <dir>, through the same
# build_entry.sh remember.sh's promote runs.
build_entry() { bash "$REPO_ROOT/internal/build_entry.sh" "$1"; }

fx() { echo "$REPO_ROOT/test/fixtures/$1"; }
pane_of() { jq -r '.result.pane.pane_id' "$(fx "$1")/pane.json"; }

# A writable copy of a fixture, for a test that changes one reply.
copy_fx() { cp -R "$(fx "$1")" "$BATS_TEST_TMPDIR/$1"; echo "$BATS_TEST_TMPDIR/$1"; }

# edit_fx <file> <jq filter> [jq options...]: rewrites <file> through the filter.
edit_fx() {
  local f=$1 filter=$2; shift 2
  jq "$@" "$filter" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# stack_entry <replies dir> [<jq filter> [jq options...]]: the entry built from <dir>, through the
# filter, pushed onto the stack at HERDR_PLUGIN_STATE_DIR the way promote pushes it.
stack_entry() {
  local dir=$1 filter=${2:-.} pane staged
  shift; [ $# -eq 0 ] || shift
  # shellcheck disable=SC2034  # read by stack.sh
  state=$HERDR_PLUGIN_STATE_DIR keep=${keep:-20}
  # shellcheck source-path=SCRIPTDIR source=../../internal/stack.sh
  declare -F stack_push >/dev/null || . "$REPO_ROOT/internal/stack.sh"
  pane=$(jq -r '.result.pane.pane_id' "$dir/pane.json")
  staged=$(stack_staging "$pane")
  mkdir -p "$staged"
  build_entry "$dir" | jq "$@" "$filter" > "$staged/entry.json"
  : > "$staged/scrollback.ansi"
  stack_push "$pane"
}
