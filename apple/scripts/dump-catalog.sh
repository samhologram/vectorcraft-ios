#!/usr/bin/env bash
# Print the bridge's catalogs: dump-catalog.sh engine|ui|menus|tools|panels|full  (tab separated, `full` is the
# human-readable apple/docs/catalog-dump.txt).
#   engine: id label menu params; ui: id label menu; tools: id label shortcut icon; panels: id label menu.
# Needs cargo (host build of apple/bridge).
set -euo pipefail
BRIDGE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bridge" && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
cd "$BRIDGE" && cargo run -q --example dump -- "${1:?engine|ui|menus|tools|panels|full}"
