#!/usr/bin/env bash
# One-time WSL (Ubuntu) setup for building the Linux desktop bundle and .deb.
# Run as root: wsl -d Ubuntu -u root -- bash /mnt/d/.../tool/package/wsl_setup.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
# Desktop toolchain + what the plugins shell out to at build/run time, plus
# dpkg-deb/fakeroot for packaging and git/curl/xz for the Flutter checkout.
apt-get install -y -qq \
  clang cmake ninja-build pkg-config libgtk-3-dev \
  unzip pulseaudio-utils \
  dpkg-dev fakeroot patchelf binutils desktop-file-utils \
  git curl xz-utils file

echo "--- installed ---"
for p in clang cmake ninja pkg-config unzip parecord dpkg-deb fakeroot patchelf objdump git; do
  if command -v "$p" >/dev/null 2>&1; then echo "ok      $p"; else echo "MISSING $p"; fi
done
pkg-config --modversion gtk+-3.0 | sed 's/^/gtk+-3.0 /'
