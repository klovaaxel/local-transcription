#!/usr/bin/env bash
# Check what a Linux tester actually gets from the installed package.
#
#   wsl -d Ubuntu -u root -- bash tool/package/verify_deb.sh dist/forelasning_*.deb
#
# The interesting check is the last one. The local brief is an FFI dlopen of
# libllama.so; if that fails the app records and transcribes and then never
# produces a brief, which is the whole point of the product.
set -uo pipefail
DEB="${1:?usage: verify_deb.sh <path to .deb>}"
PREFIX=/opt/forelasning

echo "==> install"
# unattended-upgrades grabs the dpkg lock on a fresh Ubuntu and a failed install
# here would silently verify the previously installed package instead.
for _ in $(seq 1 60); do
  fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break
  echo "  waiting for the dpkg lock..."
  sleep 5
done
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --reinstall "$DEB" 2>&1 | tail -4; then
  echo "install FAILED - the checks below would describe the old package" >&2
  exit 1
fi

echo "==> desktop entry"
if command -v desktop-file-validate >/dev/null 2>&1; then
  if desktop-file-validate /usr/share/applications/se.axelkarlsson.lecture_local.desktop; then
    echo "clean"
  fi
else
  echo "desktop-file-validate not installed, skipped"
fi

echo "==> icons"
find /usr/share/icons/hicolor /usr/share/pixmaps -name "se.axelkarlsson.lecture_local.png" 2>/dev/null | while read -r f; do
  printf "  %-10s %s
" "$(file -b "$f" | cut -d, -f2 | tr -d " ")" "$f"
done

echo "==> launcher"
head -n 1 /usr/bin/forelasning >/dev/null 2>&1 && echo "  /usr/bin/forelasning present"
grep -q LD_LIBRARY_PATH /usr/bin/forelasning 2>/dev/null && echo "  sets LD_LIBRARY_PATH: yes"

echo "==> unresolved libraries for the main binary"
ldd "$PREFIX/lecture_local" | grep "not found" || echo "  none"

echo "==> recording dependency"
command -v parecord >/dev/null && echo "  parecord: $(command -v parecord)" || echo "  parecord MISSING - recording will fail"

echo "==> local brief: dlopen libllama.so the way the app does"
PROBE=/tmp/dlopen_probe
SRC="$(dirname "$0")/dlopen_probe.c"
if cc -o "$PROBE" "$SRC" -ldl 2>/dev/null || clang -o "$PROBE" "$SRC" 2>/dev/null; then
  if LD_LIBRARY_PATH="$PREFIX/lib" "$PROBE" "$PREFIX/lib/libllama.so"; then
    echo "  the brief can load its backend"
  else
    echo "  BROKEN: the app will transcribe but never write a brief"
    exit 1
  fi
else
  echo "  no C compiler, skipped"
fi
