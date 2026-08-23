#!/bin/bash
# Exit immediately if a command exits with a non-zero status, and fail pipeline
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "--- 1. Checking Environment ---"

# Check for Neovim
if ! command -v nvim &>/dev/null; then
  echo "Error: Neovim (nvim) is required and not found in PATH."
  exit 1
fi

# Check for uv (Required for your Python REPL command)
if ! command -v uv &>/dev/null; then
  echo "Warning: 'uv' not found. Your REPL tests may fail if uv isn't installed."
fi

echo "--- 2. Setting up Dependencies ---"

# Clone Plenary if it doesn't exist (mirrors CI setup)
PLENARY_DIR="vendor/plenary.nvim"
if [ ! -d "$PLENARY_DIR" ]; then
  echo "Cloning Plenary to $PLENARY_DIR..."
  mkdir -p vendor
  git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$PLENARY_DIR"
else
  echo "Plenary already cloned."
fi

echo "--- 3. Running Tests ---"

# Execute the same command used in CI
XDG_CONFIG_HOME=/tmp XDG_DATA_HOME=/tmp nvim --headless --clean -u tests/minimal_init.lua -c "PlenaryBustedFile tests/tests.lua"
