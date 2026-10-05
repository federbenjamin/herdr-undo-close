load ../helpers/common

setup() {
  isolate
  entry=$HOME/entry
  mkdir -p "$entry" "$HOME/bin"
  # A claude that records its argv, one word per line, and says it ran.
  cat > "$HOME/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/claude-args"
echo "fake claude ran"
FAKE
  chmod +x "$HOME/bin/claude"
}
teardown() { unisolate; }

# launch <agent> <session> <claude_bin> <claude_resume_args>: writes <entry>/launch.
launch() {
  printf 'agent=%q\nsession=%q\nclaude_bin=%q\nclaude_resume_args=%q\n' "$1" "$2" "$3" "$4" > "$entry/launch"
}

@test "prints the scrollback, then the reopened marker" {
  printf 'old output\n' > "$entry/scrollback.ansi"
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"old output"* ]]
  [[ "$output" == *"── reopened by undo-close ──"* ]]
  before=${output%%old output*}
  after=${output#*old output}
  [ -z "$before" ]
  [[ "$after" == *"── reopened by undo-close ──"* ]]
}

@test "an empty scrollback prints no marker" {
  : > "$entry/scrollback.ansi"
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reopened by undo-close"* ]]
}

@test "the entry dir is deleted" {
  printf 'x\n' > "$entry/scrollback.ansi"
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ ! -e "$entry" ]
}

@test "a missing entry dir is not an error" {
  run bash "$REPO_ROOT/reopen_entry.sh" "$HOME/nope"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "claude gets the resume args words, then --resume=<session>" {
  mkdir -p "$HOME/.claude/projects/-home-user-proj"
  : > "$HOME/.claude/projects/-home-user-proj/abc-123.jsonl"
  launch claude abc-123 "$HOME/bin/claude" "--foo --bar=baz"
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fake claude ran"* ]]
  [ "$(cat "$HOME/claude-args")" = $'--foo\n--bar=baz\n--resume=abc-123' ]
}

@test "claude with no resume args gets only --resume=<session>" {
  mkdir -p "$HOME/.claude/projects/-home-user-proj"
  : > "$HOME/.claude/projects/-home-user-proj/abc-123.jsonl"
  launch claude abc-123 "$HOME/bin/claude" ""
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--resume=abc-123" ]
}

@test "a session id outside [A-Za-z0-9-] is refused and claude is not run" {
  for bad in 'a;b' 'a b' 'a$(touch x)' 'a_b' 'a/b'; do
    mkdir -p "$entry"
    launch claude "$bad" "$HOME/bin/claude" ""
    run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
    [ "$status" -eq 0 ]
    [[ "$output" == *"refusing to resume an odd-looking session id."* ]]
    [ ! -e "$HOME/claude-args" ]
  done
}

@test "an empty claude_bin says claude is not on PATH" {
  launch claude abc-123 "" ""
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude is not on PATH; the session abc-123 was not resumed."* ]]
  [ ! -e "$HOME/claude-args" ]
}

@test "an agent other than claude says there is no resume for it" {
  launch codex abc-123 "$HOME/bin/claude" ""
  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no resume for codex; its scrollback is above."* ]]
  [ ! -e "$HOME/claude-args" ]
}
