# Changelog

## 0.2.0 — 2026-10-03

First shareable version.

- `close` remembers the pane (snapshot before the key; promoted to the stack once the pane is gone).
- `reopen` recreates the newest closed pane in its old spot, or its tab, or its workspace; replays
  the scrollback; resumes a Claude Code session; types back a single command; reopens the file viewer.
- `setup-keys`, `setup-shell`, `remove-keys`, `remove-shell` write and remove marked blocks.
- Snapshots are owner-only and forgotten after `max_age_days`.
