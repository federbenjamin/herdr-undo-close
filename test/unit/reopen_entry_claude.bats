load ../helpers/common

setup() {
  isolate
  entry=$HOME/entry
  mkdir -p "$entry" "$HOME/bin"
  # The record distinguishes a fresh launch from one that received --resume.
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

saved_session() {
  local config_dir=$1
  mkdir -p "$config_dir/projects/-home-user-proj"
  printf 'conversation\n' > "$config_dir/projects/-home-user-proj/abc-123.jsonl"
}

@test "a missing conversation file starts fresh and names the unsaved Claude session" {
  launch claude abc-123 "$HOME/bin/claude" "--foo"

  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--foo" ]
  [[ "$output" == *$'\033[2mundo-close: claude session abc-123 was never saved (no conversation file); starting a fresh claude here.\033[0m'* ]]
}

@test "a conversation file under the default Claude config resumes that session" {
  saved_session "$HOME/.claude"
  launch claude abc-123 "$HOME/bin/claude" "--foo"

  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = $'--foo\n--resume=abc-123' ]
  [[ "$output" != *"never saved"* ]]
}

@test "a conversation file in CLAUDE_CONFIG_DIR resumes that session" {
  saved_session "$HOME/cfg"
  launch claude abc-123 "$HOME/bin/claude" "--foo"

  run env CLAUDE_CONFIG_DIR="$HOME/cfg" bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = $'--foo\n--resume=abc-123' ]
}

@test "CLAUDE_CONFIG_DIR ignores a conversation stored only in the default config" {
  saved_session "$HOME/.claude"
  mkdir -p "$HOME/cfg/projects"
  launch claude abc-123 "$HOME/bin/claude" "--foo"

  run env CLAUDE_CONFIG_DIR="$HOME/cfg" bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--foo" ]
  [[ "$output" == *"never saved"* ]]
}

@test "an unsaved session with empty resume args launches Claude with no arguments" {
  launch claude abc-123 "$HOME/bin/claude" ""

  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [ -f "$HOME/claude-args" ]
  [ -z "$(cat "$HOME/claude-args")" ]
}

@test "an empty claude_bin refuses even when the conversation file exists" {
  saved_session "$HOME/.claude"
  launch claude abc-123 "" ""

  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [[ "$output" == *"claude is not on PATH; the session abc-123 was not resumed."* ]]
  [ ! -e "$HOME/claude-args" ]
}

@test "an odd session id refuses even when a matching conversation file exists" {
  mkdir -p "$HOME/.claude/projects/-home-user-proj"
  printf 'conversation\n' > "$HOME/.claude/projects/-home-user-proj/a_b.jsonl"
  launch claude a_b "$HOME/bin/claude" ""

  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [[ "$output" == *"refusing to resume an odd-looking session id."* ]]
  [ ! -e "$HOME/claude-args" ]
}

@test "a non-Claude agent refuses without running the fake despite a conversation file" {
  saved_session "$HOME/.claude"
  launch codex abc-123 "$HOME/bin/claude" ""

  run bash "$REPO_ROOT/reopen_entry.sh" "$entry"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no resume for codex; its scrollback is above."* ]]
  [ ! -e "$HOME/claude-args" ]
}
