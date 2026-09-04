#!/usr/bin/env bash
# Install a Linux Flutter SDK inside WSL, pinned to the same version the Windows
# side uses. A separate checkout on purpose: bin/cache holds an OS-specific
# dart-sdk, so sharing D:\sdk\flutter between Windows and Linux clobbers it.
set -euo pipefail

FLUTTER_VERSION="${1:-3.47.2}"
FLUTTER_DIR="$HOME/sdk/flutter"

if [ -d "$FLUTTER_DIR/.git" ]; then
  echo "Flutter already at $FLUTTER_DIR"
else
  mkdir -p "$HOME/sdk"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_DIR" || true
flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter config --enable-linux-desktop
