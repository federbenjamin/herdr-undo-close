# Changelog

## Unreleased

- A test suite on bats-core: unit tests for `entry.jq`, `reopen_entry.sh` and `setup.sh` against
  saved Herdr replies, and live tests that close and reopen panes on a real headless Herdr. Every
  Herdr call goes through a guard, so the tests never reach your own Herdr.
- CI on GitHub Actions: shellcheck and both test layers on Ubuntu and macOS.

## 0.2.0 — 2026-10-03

First shareable version.

- `close` remembers the pane (snapshot before the key; promoted to the stack once the pane is gone).
- `reopen` recreates the newest closed pane in its old spot, or its tab, or its workspace; replays
  the scrollback; resumes a Claude Code session; types back a single command; reopens the file viewer.
- `setup-keys`, `setup-shell`, `remove-keys`, `remove-shell` write and remove marked blocks.
- Snapshots are owner-only and forgotten after `max_age_days`.
