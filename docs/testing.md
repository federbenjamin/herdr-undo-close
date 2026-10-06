# Testing

Two test layers, on [bats-core](https://github.com/bats-core/bats-core). You need Herdr 0.9+,
`jq` and bats-core; the zsh case is skipped when `zsh` is not installed.

```sh
bats test/unit   # entry.jq, close.sh, remember.sh, reopen.sh, reopen_entry.sh, setup.sh and the live harness's own checks, against saved Herdr replies and a fake herdr; no server
bats test/live   # close.sh and reopen.sh against a real headless Herdr, one server per file
```

The tests never touch your own Herdr, even when run from inside a Herdr pane. Each unit test,
and each live file (its tests share one server), gets a temporary HOME under `/tmp`, with every
`HERDR_*` and `XDG_*` variable removed, and every Herdr call, the plugin's included, goes
through `test/helpers/herdr-guard`, which refuses any call that could reach a server outside
that HOME. A refused call fails the unit test that made it, or, in a live file, the file's
teardown. The one call that skips Herdr, `close.sh`'s popup check, needs `HERDR_SOCKET_PATH`,
which the tests remove, so it makes no connection.

`test/fixtures/capture.sh` re-captures the saved replies from an isolated server, for a new
Herdr version. `media/hero.sh` re-takes the README picture the same way (it needs `vhs`). CI
(`../.github/workflows/test.yml`) runs shellcheck and both layers on Ubuntu and macOS.
