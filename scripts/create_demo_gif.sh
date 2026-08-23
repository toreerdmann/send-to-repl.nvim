#!/bin/bash
set -euo pipefail

# Directory of the repository root
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "--- 1. Checking Environment ---"
if ! command -v vhs &>/dev/null; then
    echo "Error: 'vhs' is required to generate the demo GIF."
    echo "Install it via Homebrew: brew install vhs"
    exit 1
fi

echo "--- 2. Generating demo.gif with VHS ---"
vhs scripts/demo.tape

echo "--- 3. Done ---"
if [ -f "demo.gif" ]; then
    ls -lh demo.gif
    echo "Successfully generated demo.gif in $REPO_DIR"
else
    echo "Error: demo.gif was not created."
    exit 1
fi
