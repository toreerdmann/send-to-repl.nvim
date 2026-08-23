#!/bin/bash
set -euo pipefail

# Directory of the repository root
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

# Temporary isolated XDG directory to avoid touching user's local nvim configs/plugins
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'nvim_testdrive')"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Starting isolated Neovim session for send-to-repl.nvim..."

XDG_CONFIG_HOME="$TMP_DIR/config" \
XDG_DATA_HOME="$TMP_DIR/data" \
XDG_STATE_HOME="$TMP_DIR/state" \
nvim --clean -u "$REPO_DIR/tests/demo_init.lua" "$@"
