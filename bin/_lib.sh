#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$BIN_DIR/.." && pwd)"
export BIN_DIR ROOT_DIR
cd "$ROOT_DIR"
run() {
  if command -v mise >/dev/null 2>&1; then
    mise exec -- "$@"
  else
    "$@"
  fi
}
bundle_exec() { run bundle exec "$@"; }
