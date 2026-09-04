#!/usr/bin/env bash
# Which llama.cpp commit does llm_llamacpp build against? The pub package ships
# the FFI bindings but not the submodule, so the pin lives in the upstream repo.
set -euo pipefail
VER="${1:-0.4.0}"
WORK="$HOME/build/dart-llm-pin"
rm -rf "$WORK"
git clone --quiet --depth 1 --branch "$VER" https://github.com/brynjen/dart-llm.git "$WORK" 2>/dev/null \
  || git clone --quiet --depth 1 https://github.com/brynjen/dart-llm.git "$WORK"
cd "$WORK"
echo "== tag/branch: $(git describe --tags --always 2>/dev/null || echo unknown)"
echo "== .gitmodules"
cat .gitmodules 2>/dev/null || echo "(none)"
echo "== submodule pins"
git submodule status 2>/dev/null || true
git ls-tree HEAD --full-tree -r 2>/dev/null | awk '$2=="commit"{print $3, $4}'
