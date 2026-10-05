# Changelog

## Unreleased

- A closed plugin pane reopens as the same plugin pane, with its plugin and entrypoint read from
  Herdr's `plugin pane focus`: an overlay (such as clauth) comes back as an overlay over the pane
  you are in, a split or tab plugin pane in its old spot. This replaces the file viewer's own
  path, which recognised it by process name. When a plugin pane cannot reopen, the message gives
  Herdr's reason; a pane whose plugin or entrypoint is gone (uninstalled, unlinked) is dropped from
  the stack, so the next `prefix+u` reaches the pane below it. A failed plugin lookup at close is
  written to `herdr plugin log`.
- A Claude Code pane whose session never got a message reopens as a fresh `claude` (with
  `claude_resume_args`) in its folder, with a one-line note, instead of a failing
  `claude --resume`. The check looks for `projects/*/<session id>.jsonl` under Claude Code's
  config dir (`CLAUDE_CONFIG_DIR`, else `~/.claude`), the files `--resume` itself searches; if a
  future Claude Code stops writing them, every pane starts fresh.
- The saved-pane format is now version 2. Panes remembered before this update are dropped on the
  first `prefix+u` after it.
- A file viewer reopens at the file it showed when it closed, read from the viewer's
  `file_viewer_open` pane token (the viewer's `report_open_file = true`). A viewer that does not
  report it reopens at the file it was launched with, as before.

## 0.2.1 — 2026-10-04

- A test suite on bats-core: unit tests for `entry.jq`, `reopen_entry.sh` and `setup.sh` against
  saved Herdr replies, and live tests that close and reopen panes on a real headless Herdr. Every
  Herdr call goes through a guard, so the tests never reach your own Herdr.
- CI on GitHub Actions: shellcheck and both test layers on Ubuntu and macOS.
- Fix: a reopened tab no longer keeps Herdr's own default label (the tab's number, "1") as a
  custom label; only a label you set is restored.
- `build_entry.sh` holds the one `entry.jq` command; `remember.sh` and the tests both run it.

## 0.2.0 — 2026-10-03

First shareable version.

- `close` remembers the pane (snapshot before the key; promoted to the stack once the pane is gone).
- `reopen` recreates the newest closed pane in its old spot, or its tab, or its workspace; replays
  the scrollback; resumes a Claude Code session; types back a single command; reopens the file viewer.
- `setup-keys`, `setup-shell`, `remove-keys`, `remove-shell` write and remove marked blocks.
- Snapshots are owner-only and forgotten after `max_age_days`.
