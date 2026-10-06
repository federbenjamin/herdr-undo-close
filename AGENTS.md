# herdr-undo-close

## Project state

- 2026-10-04: launched — v0.2.1 is released and public, so other people may have it installed. Retires if the repo is archived.
- 2026-10-04: the project holds no user data; each user's closed panes live only on their own machine, under the plugin's state dir. A change to the saved-pane format drops panes saved before it (the version field), so it costs a user at most their stack. Retires if the plugin ever stores or sends data off the user's machine.

<!-- >>> git-workflow (generated block; do not edit by hand) -->
## Git workflow

- `main` changes only through a PR, squash-merged.
- Branch names: `<type>/<slug>`, the type being the commit type (`feat`, `fix`, `docs`, `chore`, `refactor`).
<!-- <<< git-workflow -->
