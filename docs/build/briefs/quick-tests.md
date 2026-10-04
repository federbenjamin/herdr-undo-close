class: R1 — agent (unconfirmed), 2026-10-03
model: opus — the ## Design block names P3's files (the live harness and CI)

# quick/tests — a test suite and CI for herdr-undo-close

## Spec

herdr-undo-close is a herdr plugin written in bash + jq (`close.sh`, `remember.sh`, `entry.jq`,
`reopen.sh`, `reopen_entry.sh`, `setup.sh`, `lib.sh`, `shell-hook.sh`). It has no tests. Add two
layers on bats-core, plus GitHub Actions CI.

**Layer 1 — unit (no herdr server).**
- `entry.jq` against real herdr 0.9.1 replies saved as fixtures: the sibling (`pane_id`,
  `direction` right/down, `side` before/after), no split → `sibling: null`, `kind`
  shell/agent/viewer, `argv` = the process-group leader's argv and `null` when the leader is a
  shell, `tab_label` null for herdr's auto label (`^[0-9]+ · `), `workspace_label` null when it
  equals the cwd basename, `viewer_open` from the viewer's `--open <path>`, `v: 1`, missing
  tab/workspace replies → null fields, never an error.
- `reopen_entry.sh` with a fake `claude` on disk: the scrollback is printed then the
  `── reopened by undo-close ──` marker; no marker when the scrollback is empty; the entry dir is
  deleted; the fake claude receives `<claude_resume_args words> --resume=<session>`; a session id
  outside `^[A-Za-z0-9-]+$` is refused with its message and claude is not run; an empty
  `claude_bin` prints the "not on PATH" message; an agent other than `claude` prints the
  "no resume for" message.
- `setup.sh` in a temp HOME with the real `herdr config check`: `keys` appends one fenced block
  binding `ctrl+d` → `herdr-undo-close.close` and `prefix+u` → `herdr-undo-close.reopen`; a
  second `keys` replaces the block (one block, not two); a key already bound outside the block is
  skipped and named; every key bound → refused, file unchanged; a begin marker with no end marker
  → refused, file unchanged; a config that fails `herdr config check` before the write → refused,
  unchanged; the first backup is kept on a second run; `remove-keys` deletes only the block;
  `shell` writes the hook block to the profile `profile_path` picks — bash login →
  first existing of `.bash_profile`/`.bash_login`/`.profile` (else `.bash_profile`), bash
  non-login → `.bashrc`, zsh login → `.zprofile`, zsh non-login → `.zshrc`, by
  `default_shell` and `shell_mode` (`login` / `non_login` / `auto` = login on Darwin only);
  `remove-shell` deletes only that block.

**Layer 2 — live (a real headless herdr).** Each live file starts its own `herdr server` under
the test HOME `isolate` made and stops it in teardown. Before any other herdr call, the file
asserts `herdr status server` reports a socket under that HOME. The plugin scripts run directly
(`bash "$REPO_ROOT/close.sh" <pane>`, `bash "$REPO_ROOT/reopen.sh"`), with
`HERDR_PLUGIN_STATE_DIR` per test under the test HOME; no plugin is installed in the test server. The pane
shell reads the test HOME's profile, so the hook is installed there with `setup.sh shell`.
Cases:
- a shell pane split right of another, with output in it, closed with `close.sh` (it gets
  ctrl+d and exits) → `reopen.sh` brings a pane back in the same tab, beside the same sibling,
  on the same side (right of it); the new pane's screen holds the old output and the marker.
- the same with the closed pane on the left/top (side `before`) → after reopen it is on the left
  /top again (the swap).
- a pane running `tail -F '<dir>/a;b'` closed with `close.sh` (herdr closes it: `tail` is not in
  `passthrough_regex`) → after reopen the prompt holds `tail -F '<dir>/a;b'` typed, not run (no
  `tail` process in the new pane).
- a pane whose leader's argv holds a control character (e.g. `tail -F $'<dir>/x\001y'`) → after
  reopen nothing is typed at the prompt.
- the last pane of a tab with a custom label → the tab comes back with that label.
- the last pane of a workspace with a custom label → the workspace comes back with that label.
- the first case again with `default_shell` set to zsh in the test config (zsh hook in
  `.zprofile` or `.zshrc` per `setup.sh shell`), skipped with a message when zsh is absent.

**Safety (both layers).** No test may reach the developer's own herdr: a herdr pane exports
`HERDR_SOCKET_PATH`, which overrides `HERDR_SESSION` and `HOME` (seen on 2026-10-03: a probe with
only `HERDR_SESSION` set created a workspace in the developer's session). Every herdr call — the
plugin scripts' (via `HERDR_BIN_PATH`) and the tests' own — goes through
`test/helpers/herdr-guard`, which refuses unless HOME is the test HOME and every `HERDR_*`/`XDG_*`
path is under it. One call skips the guard: `close.sh`'s popup check opens the socket
`${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}` with python3 (`close.sh:26`); it is safe
only because `isolate` unsets `HERDR_SOCKET_PATH` and moves HOME, so no test sets it. The test HOME is short (`/tmp/uc.XXXXXX`): herdr's socket path must fit
`sun_path` (104 bytes on macOS); a `$TMPDIR` path fails with "local socket name length exceeds
capacity of sun_path".

**CI.** `.github/workflows/test.yml`, on push and pull_request, a matrix of `ubuntu-latest` and
`macos-latest`: install herdr (`curl -fsSL https://herdr.dev/install.sh | sh`, per herdr's docs;
`brew install herdr` is the macOS alternative), jq, bats-core, shellcheck, and zsh on ubuntu;
then `shellcheck -x` over every script and test helper, `bats test/unit`, `bats test/live`.

**Scope.** App code changes only when a test proves a defect; P2 changes no app file (it reports
a defect it proves, and the session routes the fix). A live Claude Code resume is out of scope
(whether a fake agent can carry a herdr agent session is unknown); `reopen_entry.sh`'s unit tests
cover the resume command. The file-viewer reopen is out of scope live (needs another plugin);
`entry.jq`'s `viewer_open` is covered by unit tests.

## Prior art

- test harness (`test/helpers/common.bash`, `test/helpers/herdr-guard`, `test/helpers/live.bash`)
  — **justified-new**: the repo has no test files (`git ls-files` at d99c45f: 14 files, all
  plugin code and docs). The throwaway stub harness from the development session (a fake
  `herdr` answering from canned JSON) is not reused: it hid the bug where herdr writes its error
  JSON to stderr (fixed in the plugin's history as "herdr prints its error JSON on stderr"), and
  a double that copies herdr's replies is what make-decision principle 10 rules out.
- fixtures — **justified-new**: none exist; captured fresh from an isolated herdr 0.9.1 by
  `test/fixtures/capture.sh` so they can be re-captured on a new herdr version.

## Design

- **Chosen:** bats-core; one shared `isolate` (common.bash) that makes a short temp HOME,
  removes every `HERDR_*`, `XDG_*`, `ZDOTDIR`, `BASH_ENV`, `ENV` variable, and points
  `HERDR_BIN_PATH` at `test/helpers/herdr-guard`; the guard refuses (exit 97, and appends the
  refusal to `$UNDO_CLOSE_TEST_HOME/guard-refusals`) any call whose HOME is not the test HOME or
  that carries a `HERDR_*`/`XDG_*` path outside it (the refusal file is the signal: the plugin
  throws herdr's exit code and stderr away, e.g. `reopen.sh:42`, `close.sh:40`); `unisolate` fails the test when that file exists,
  then removes the HOME. Live files run one `herdr server` per file (`setup_file`) and stop it in
  `teardown_file`; each test makes its own workspace and its own state dir.
  Fixtures come from the plugin's own `remember.sh snapshot <pane>` (`remember.sh:25-41` makes
  exactly the herdr calls and file names `entry.jq` reads), copied from `staging/<pane>/` with
  the test HOME path replaced by `/home/user`; `entry.bats` builds entries through one helper,
  `build_entry <dir>`, holding the `jq -n -f entry.jq --slurpfile …` command of
  `remember.sh:51-53`.
- **Rejected:** a stub `herdr` (hid the stderr bug; principle 10). A named session
  (`HERDR_SESSION`) under the developer's own config dir (writes into `~/.config/herdr/sessions/`,
  and a pane's `HERDR_SOCKET_PATH` overrides it — proven on 2026-10-03).
- **Assumptions (checked 2026-10-03 on herdr 0.9.1, macOS):** with `HOME=/tmp/claude/uc.XXXX`
  and the variables above unset, `herdr server` serves `$HOME/.config/herdr/herdr.sock`,
  `workspace create` and `pane process-info` work against it, and the developer's session is
  untouched; `herdr config check` passes on an empty config under that HOME. Not checked: herdr's
  `install.sh` on GitHub runners, and Linux's socket location when `XDG_RUNTIME_DIR` is unset
  (P3 confirms both in CI).

## Public surface

- `test/helpers/common.bash` — `REPO_ROOT` (the repo root, absolute, from the file's own path,
  so plain scripts can source it); `isolate` (no args; exports `HOME`, `UNDO_CLOSE_TEST_HOME`,
  `UNDO_CLOSE_TEST_TMP`, `UNDO_CLOSE_REAL_HERDR`, `HERDR_BIN_PATH`, `HERDR_PLUGIN_STATE_DIR`);
  `unisolate` (no args; fails when the guard refused anything, then removes the test HOME).
- `test/helpers/herdr-guard` — executable; same argv as `herdr`. Refuses (exit 97, and appends
  to `$UNDO_CLOSE_TEST_HOME/guard-refusals`) unless HOME is the test HOME, `HERDR_SESSION` is
  unset, and every `HERDR_*`/`XDG_*` value that is an absolute path sits under the test HOME.
- `test/helpers/live.bash` — plain bash (sourceable by `capture.sh`): `start_server` (starts
  `herdr server` under the test HOME, waits until `status: running`, returns 1 unless the
  socket, resolved with `cd -P`, is under the resolved test HOME), `stop_server` (stops it and
  waits until it is gone).
- `test/fixtures/capture.sh` — regenerates `test/fixtures/` from an isolated herdr.

P1 is the session's: these three helpers are committed right after this brief (smoke-tested on
2026-10-03 from a herdr pane with `HERDR_SOCKET_PATH` set: the guard refused a foreign socket,
HOME, and `XDG_CONFIG_HOME`; `start_server`/`stop_server` ran a server under the test HOME; the
developer's server logged 0 CLI requests). P2 and P3 use them and do not change them (a needed
change is a STOP back to the session). P3 may add live-only helpers in `test/live/`.

Rules for every test file: load `common`, call `isolate` in `setup` (unit) or `setup_file`
(live) and `unisolate` in the matching teardown; a live test sets
`HERDR_PLUGIN_STATE_DIR="$HOME/state/$BATS_TEST_NUMBER"` in its `setup` (one closed-pane stack
per test, so a failed test's entry never reopens in the next); never set `HERDR_SOCKET_PATH`; call herdr only as `"$HERDR_BIN_PATH"`, never
bare `herdr`; never `rm -rf` a path that did not come from `isolate`.

## Target files

- test/helpers/common.bash — P1, the session writes it
- test/helpers/herdr-guard — P1, the session writes it
- test/helpers/live.bash — P1, the session writes it
- test/fixtures/ — real herdr replies + capture.sh
- test/unit/ — layer 1
- test/live/ — layer 2
- .github/workflows/test.yml — CI
- README.md — a Development section: how to run the tests, the isolation guarantee
- CHANGELOG.md — an Unreleased entry

## Parts

- P1 · the isolation helpers
  - model: session — the brief holds their whole text
  - files: test/helpers/common.bash, test/helpers/herdr-guard, test/helpers/live.bash
  - test files: none
  - deliverables: 1
  - after: none
  - tests: none
- P2 · the unit layer and its fixtures
  - model: sonnet — the brief names every file and each case it must test
  - files: test/fixtures/, test/unit/
  - test files: none
  - deliverables: 2, 3, 4, 5
  - after: P1
  - tests: none
- P3 · the live layer, CI, and docs
  - model: opus — the ## Design block names its files; the live harness and the CI install are design choices
  - files: test/live/, .github/workflows/test.yml, README.md, CHANGELOG.md
  - test files: none
  - deliverables: 6, 7, 8, 9
  - after: P1
  - tests: none

## Hand test

- H1 · running both suites from a herdr pane (HERDR_SOCKET_PATH set to the developer's socket) sends nothing to the developer's own herdr server
  - run: `cd /Users/benjaminfeder/Programming/herdr-undo-close/.claude/worktrees/run-quick-tests && n=$(wc -l < ~/.config/herdr/herdr-server.log) && bats test/unit test/live; rc=$?; echo "bats exit=$rc"; tail -n +"$((n + 1))" ~/.config/herdr/herdr-server.log | grep -c 'request_id="cli:'`
  - pass: `bats exit=0`; the last line is `0` (no CLI request reached the developer's server during the run); the run started with `HERDR_SOCKET_PATH` set in the environment (`echo ${HERDR_SOCKET_PATH:+set}` prints `set`)
- H2 · the developer's own closed-pane stack, herdr config, and shell profile are unchanged by a full run
  - run: `cd /Users/benjaminfeder/Programming/herdr-undo-close/.claude/worktrees/run-quick-tests && b=$(ls ~/.local/state/herdr/plugins/herdr-undo-close/closed 2>/dev/null; md5 -q ~/.config/herdr/config.toml ~/.bash_profile) && bats test/unit test/live >/dev/null; a=$(ls ~/.local/state/herdr/plugins/herdr-undo-close/closed 2>/dev/null; md5 -q ~/.config/herdr/config.toml ~/.bash_profile); [ "$b" = "$a" ] && echo SAME || echo CHANGED`
  - pass: prints `SAME` (if the developer closed a pane during the run the stack listing differs; re-run once before calling it a fail)

## Deliverables

1. `test/helpers/common.bash`, `test/helpers/herdr-guard`, and `test/helpers/live.bash` exist as ## Public surface describes; before: no test helpers; after: `isolate`/`unisolate`, the guard (refuses a foreign HOME, `HERDR_SESSION`, or a `HERDR_*`/`XDG_*` path outside the test HOME), and `start_server`/`stop_server`. (§Public surface)
2. `test/fixtures/` holds herdr 0.9.1 replies (`pane get`, `pane layout`, `pane process-info`, `tab get`, `workspace get`) for: a two-pane right split, a two-pane down split, a three-pane nested split, a lone pane, a pane running a command, a labeled tab and workspace; captured by `test/fixtures/capture.sh` (which sources `common.bash` and `live.bash` and runs `remember.sh snapshot`) from an isolated server via the guard, with the temp HOME path replaced by a neutral `/home/user` before saving; before: none. (§Spec, Layer 1)
3. `test/unit/entry.bats` covers every `entry.jq` behavior in §Spec Layer 1's first bullet against those fixtures; before: untested. (§Spec)
4. `test/unit/reopen_entry.bats` covers every `reopen_entry.sh` behavior in §Spec Layer 1's second bullet with a fake `claude` script; before: untested. (§Spec)
5. `test/unit/setup.bats` covers every `setup.sh` behavior in §Spec Layer 1's third bullet with the real `herdr config check` through the guard; before: untested. (§Spec)
6. `test/live/*.bats` cover every live case in §Spec Layer 2, each file calling `start_server` (which asserts the socket is under the test HOME) before any other herdr call, each test on its own state dir; before: no live tests. (§Spec, Layer 2)
7. `.github/workflows/test.yml` runs shellcheck, `bats test/unit`, and `bats test/live` on ubuntu-latest and macos-latest after installing herdr, jq, bats-core, shellcheck (and zsh on ubuntu); before: no CI. (§Spec, CI)
8. README.md gains a Development section: the two layers, how to run them (`bats test/unit`, `bats test/live`, needing herdr 0.9+, jq, bats-core), and that the tests never touch the developer's own herdr (the guard); before: none. (§Spec)
9. CHANGELOG.md gains an `## Unreleased` entry naming the test suite and CI; before: none. (§Spec)

```yaml
description: bats unit + live test suites with an isolation guard, and GitHub Actions CI, for herdr-undo-close
files_exist:
  - test/helpers/common.bash
  - test/helpers/herdr-guard
  - test/helpers/live.bash
  - test/fixtures/capture.sh
  - test/unit/entry.bats
  - test/unit/reopen_entry.bats
  - test/unit/setup.bats
  - .github/workflows/test.yml
deliverables:
  - name: isolation helpers common.bash + herdr-guard + live.bash, as Public surface describes
    covered_by: [files_exist, judgment]
  - name: fixtures captured from an isolated herdr 0.9.1 by capture.sh, paths neutralized
    covered_by: [files_exist, judgment]
  - name: entry.bats covers every entry.jq behavior in the spec
    covered_by: [files_exist, judgment]
  - name: reopen_entry.bats covers every reopen_entry.sh behavior in the spec
    covered_by: [files_exist, judgment]
  - name: setup.bats covers every setup.sh behavior in the spec
    covered_by: [files_exist, judgment]
  - name: test/live covers every live case, start_server first, per-test state dir
    covered_by: [files_exist, judgment]
  - name: CI workflow on ubuntu + macos runs shellcheck, unit, live
    covered_by: [files_exist, judgment]
  - name: README Development section
    covered_by: [judgment]
  - name: CHANGELOG Unreleased entry
    covered_by: [judgment]
```

--- brief complete ---
