load ../helpers/common
load ../helpers/fake-herdr
load ../helpers/entry

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

# saved_session <config dir> [session]: the conversation file Claude Code writes after the first
# message.
saved_session() {
  local f="$1/projects/-home-user-proj/${2:-abc-123}.jsonl"
  mkdir -p "$(dirname "$f")"
  printf 'conversation\n' > "$f"
}

@test "prints the scrollback, then the reopened marker" {
  printf 'old output\n' > "$entry/scrollback.ansi"
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
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
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reopened by undo-close"* ]]
}

@test "the entry dir is deleted" {
  printf 'x\n' > "$entry/scrollback.ansi"
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ ! -e "$entry" ]
}

@test "a missing entry dir is not an error" {
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$HOME/nope"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing conversation file starts fresh and names the unsaved Claude session" {
  launch claude abc-123 "$HOME/bin/claude" "--foo"
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--foo" ]
  [[ "$output" == *$'\033[2mundo-close: claude session abc-123 was never saved (no conversation file); starting a fresh claude here.\033[0m'* ]]
}

@test "a conversation file under the default Claude config: the resume args words, then --resume=<session>" {
  saved_session "$HOME/.claude"
  launch claude abc-123 "$HOME/bin/claude" "--foo --bar=baz"
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fake claude ran"* ]]
  [[ "$output" != *"never saved"* ]]
  [ "$(cat "$HOME/claude-args")" = $'--foo\n--bar=baz\n--resume=abc-123' ]
}

@test "claude with no resume args gets only --resume=<session>" {
  saved_session "$HOME/.claude"
  launch claude abc-123 "$HOME/bin/claude" ""
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--resume=abc-123" ]
}

@test "a conversation file in CLAUDE_CONFIG_DIR resumes that session" {
  saved_session "$HOME/cfg"
  launch claude abc-123 "$HOME/bin/claude" "--foo"
  run env CLAUDE_CONFIG_DIR="$HOME/cfg" bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = $'--foo\n--resume=abc-123' ]
}

@test "CLAUDE_CONFIG_DIR ignores a conversation stored only in the default config" {
  saved_session "$HOME/.claude"
  mkdir -p "$HOME/cfg/projects"
  launch claude abc-123 "$HOME/bin/claude" "--foo"
  run env CLAUDE_CONFIG_DIR="$HOME/cfg" bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--foo" ]
  [[ "$output" == *"never saved"* ]]
}

@test "an unsaved session with empty resume args launches Claude with no arguments" {
  launch claude abc-123 "$HOME/bin/claude" ""
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [ -f "$HOME/claude-args" ]
  [ -z "$(cat "$HOME/claude-args")" ]
}

@test "a session id outside [A-Za-z0-9-] is refused and claude is not run, even with its conversation file" {
  for bad in 'a;b' 'a b' 'a$(touch x)' 'a_b' 'a/b'; do
    mkdir -p "$entry"
    saved_session "$HOME/.claude" "$bad"
    launch claude "$bad" "$HOME/bin/claude" ""
    run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
    [ "$status" -eq 0 ]
    [[ "$output" == *"refusing to resume an odd-looking session id."* ]]
    [ ! -e "$HOME/claude-args" ]
  done
}

@test "an empty claude_bin says claude is not on PATH, even with the conversation file" {
  saved_session "$HOME/.claude"
  launch claude abc-123 "" ""
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude is not on PATH; the session abc-123 was not resumed."* ]]
  [ ! -e "$HOME/claude-args" ]
}

@test "an agent other than claude says there is no resume for it, even with a conversation file" {
  saved_session "$HOME/.claude"
  launch codex abc-123 "$HOME/bin/claude" ""
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$entry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no resume for codex; its scrollback is above."* ]]
  [ ! -e "$HOME/claude-args" ]
}

@test "reopen.sh writes an agent entry's launch file, and reopen_entry.sh resumes from it" {
  fake_herdr
  saved_session "$HOME/.claude"
  d=$(copy_fx lone)
  printf '{"agent":"claude","session":"abc-123"}' > "$d/agent.json"
  stack_entry "$d"
  reply pane_list 0 '{"result":{"panes":[{"pane_id":"w1:p3","tab_id":"w1:t1"}]}}'
  reply pane_layout 0 '{"result":{"layout":{"panes":[{"pane_id":"w1:p3","rect":{"x":0,"y":0,"width":80,"height":20}}]}}}'
  reply pane_split 0 '{"result":{"pane":{"pane_id":"w1:p4"}}}'
  PATH="$HOME/bin:$PATH" run bash "$REPO_ROOT/reopen.sh"
  [ "$status" -eq 0 ]
  e=$(calls | sed -n 's/^pane split .*--env UNDO_CLOSE_REOPEN=\([^ ]*\).*/\1/p')
  [ -f "$e/launch" ]
  run bash "$REPO_ROOT/internal/reopen_entry.sh" "$e"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--resume=abc-123" ]
  [ ! -e "$e" ]
}
