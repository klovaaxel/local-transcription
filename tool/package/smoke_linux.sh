#!/usr/bin/env bash
# Smoke test: does the installed Linux app actually start? Uses WSLg, so it only
# works from a WSL distro with a display. Kills the app after a few seconds -
# this proves it gets past dynamic linking and opens a window, nothing more.
set -u
export DISPLAY="${DISPLAY:-:0}"
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  echo "no display available, skipping"; exit 0
fi
/usr/bin/forelasning >/tmp/forelasning.log 2>&1 &
pid=$!
sleep 12
if kill -0 "$pid" 2>/dev/null; then
  echo "still running after 12s (pid $pid) - it started"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  rc=0
else
  wait "$pid"; rc=$?
  echo "exited early with status $rc"
fi
echo "--- output ---"
cat /tmp/forelasning.log
exit $rc
