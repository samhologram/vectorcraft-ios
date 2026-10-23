# Fork notes: VectorCraft for iPad and iPhone

This repository is a fork of [storytold/vectorcraft](https://github.com/storytold/vectorcraft) that adds a native
iOS / iPadOS app (SwiftUI over the unchanged Rust engine, through a UniFFI bridge). Design and contracts:
`apple/README.md`, `apple/docs/CONTRACT.md`. Recipe: `CraftApps/COOKBOOK.md`.

## Remotes and branches

| Remote | Repository | Role |
|---|---|---|
| `origin` | `samhologram/vectorcraft-ios` | our fork; we push here |
| `upstream` | `storytold/vectorcraft` | the desktop app; we only pull from it |

`main` is our main branch (upstream's `main` plus `apple/`). Add the upstream remote once:
`git remote add upstream https://github.com/storytold/vectorcraft.git`.

## What is ours

Only these paths belong to the fork:

- `apple/` (the bridge crate, scripts, XcodeGen project, Swift package, the app and its tests, docs),
- `FORK.md` (this file),
- `.github/workflows/apple-ios.yml` (manual `workflow_dispatch` only; nothing runs on push or pull request).

**Never edit any other file.** If the engine lacks something, work around it in `apple/` and note it for upstream
(for example the iOS font folders: `configure_fonts` in `apple/bridge/src/lib.rs`).

## Staying in step with upstream

```bash
apple/scripts/sync-upstream.sh
```

It runs `git fetch upstream && git merge upstream/main` (merge, never rebase: our history stays intact and upstream
stays mergeable), then the bridge gate (`cargo test` and `cargo clippy --all-targets -- -D warnings` in
`apple/bridge`). It stops loudly on a merge conflict or a failing gate.

Upstream changes that reach the app through the bridge: command ids and params docs (`command_catalog`), the tool and
panel tables, and `crates/ui-egui/src/menus.rs` (parsed at build time by `apple/bridge/src/menus_src.rs`). After a
sync, run `apple/scripts/check-command-ids.sh`, `tool-coverage.sh` and `feature-coverage.sh` too: a new upstream
tool or panel needs a line in `apple/docs/tool-map.toml`.

### Resolving the rare conflict

Conflicts can only be in files we never edit, so: keep upstream's version of every upstream file
(`git checkout --theirs <file>` during the merge, or `git checkout upstream/main -- <file>`), finish the merge, then
fix `apple/` until the bridge gate passes again.

## Commits

Commit messages carry `[skip ci]`: the hosted CI runs only when started by hand (Actions, "Apple iOS", Run workflow).
