#!/usr/bin/env bash
# Merge upstream (storytold/vectorcraft) into this fork, then run the bridge gate. Merge, never rebase.
#
# Usage: apple/scripts/sync-upstream.sh
# Fails loudly on a merge conflict or a failing gate. See FORK.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$PATH"

git remote get-url upstream >/dev/null 2>&1 || {
  echo "error: no 'upstream' remote. Add it: git remote add upstream https://github.com/storytold/vectorcraft.git" >&2
  exit 1
}
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: uncommitted changes in tracked files: commit or stash them before syncing." >&2
  exit 1
fi

echo "==> git fetch upstream"
git fetch upstream
echo "==> git merge upstream/main"
if ! git merge upstream/main; then
  echo "" >&2
  echo "MERGE CONFLICT. Keep upstream's version of every upstream file (git checkout --theirs <file>)," >&2
  echo "finish the merge, then fix apple/ until this script passes. See FORK.md." >&2
  exit 1
fi

echo "==> bridge gate"
cd "$ROOT/apple/bridge"
cargo test
cargo clippy --all-targets -- -D warnings
echo "sync-upstream: OK (upstream merged, bridge gate green)"
