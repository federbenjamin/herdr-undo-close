# herdr-undo-close

Undo close for [Herdr](https://herdr.dev) panes. Close a pane with `ctrl+d`, get it back with
`prefix+u`: same spot, same scrollback, and a Claude Code pane picks up its conversation where
it left off.

## Install

You need Herdr 0.9+ and `jq`, on macOS or Linux.

```sh
herdr plugin install federbenjamin/herdr-undo-close
herdr plugin action invoke setup-keys --plugin herdr-undo-close
herdr plugin action invoke setup-shell --plugin herdr-undo-close
```

`setup-keys` binds `ctrl+d` to close and `prefix+u` to reopen (`prefix` is Herdr's command key,
`ctrl+b` unless you changed it). `setup-shell` adds a few lines to the end of the file your
pane shell reads at start (`~/.bash_profile` or `~/.zprofile` on macOS, `~/.bashrc` or
`~/.zshrc` on Linux); a reopened pane needs them to replay its scrollback before the first
prompt. Both write one marked block, keep a backup of the original file, and have a
`remove-keys` / `remove-shell` twin. A key you already use is left alone.

An action reports through a Herdr notification and `herdr plugin log list --plugin
herdr-undo-close`; `invoke` itself prints only that it started.

For Claude Code resume, Herdr must know the session: `herdr integration install claude` once.

## What you get

**`ctrl+d` closes anything.** A shell, a REPL, Claude Code, vim or less get the key and exit
(or scroll) on their own terms. A file viewer or lazygit, which would ignore it, are closed by
Herdr instead. Either way the pane is remembered first. A popup is just dismissed.

**`prefix+u` brings the last one back.**

```
close a shell pane        →  same split, same side, old output above a fresh prompt
close a Claude Code pane  →  same split, old output, then `claude --resume` into that session
close a pane running      →  same split, old output, and `tail -f app.log` typed at the
  `tail -f app.log`          prompt for you to press Enter
close the last pane of    →  the tab, or the workspace, comes back with it
  a tab or workspace
```

Press it again for the pane closed before that. The last 20 are kept, for 7 days.

What it cannot do: bring back a process. The old `tail -f` is gone; you get its output and its
command line. A pane closed some other way (`exit`, a crash, Herdr's close-tab key) is not
remembered.

## Good to know

- A remembered pane's scrollback is written to disk, readable by you only, under
  `~/.local/state/herdr/plugins/herdr-undo-close/`, until it is reopened, pushed out by 20
  newer closes, or 7 days old. Delete the directory any time.
- The typed-back command is never run for you, and is not typed at all if it contains a
  control character.
- Closing a popup needs `python3`; without it the key goes to the pane under the popup.
- A [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) pane reopens beside the
  pane it was opened from, at the file it was launched with when it had one.
- Updating is reinstalling. Uninstalling: run `remove-keys` and `remove-shell` first, then
  `herdr plugin uninstall herdr-undo-close`.

## Configuration

Optional. Copy a line from `config.example` into the file `herdr plugin config-dir
herdr-undo-close` points at, named `config`, and change it. It is sourced as shell.

| setting | default | |
| --- | --- | --- |
| `claude_resume_args` | none | flags for `claude --resume`, e.g. `"--permission-mode auto"` |
| `passthrough_regex` | shells, REPLs, agents, pagers, editors | programs that get `ctrl+d` instead of being closed |
| `keep` | 20 | panes remembered |
| `max_age_days` | 7 | days before a remembered pane is forgotten |
| `agent_minutes` | 10 | how long after Claude exits a close of that pane still reopens as Claude |

Prefer your own keys? Skip `setup-keys` and bind `herdr-undo-close.close` and
`herdr-undo-close.reopen` yourself.

## License

MIT.
