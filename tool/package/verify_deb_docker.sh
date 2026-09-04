#!/usr/bin/env bash
# Verify the .deb in a clean Ubuntu 24.04 container - the distro testers are
# expected to be on, and one that has not had build dependencies installed by
# hand. Run from the repo root:
#
#   tool/package/verify_deb_docker.sh dist/forelasning_1.0.0-1_amd64.deb
#
set -euo pipefail
DEB="${1:?usage: verify_deb_docker.sh <path to .deb>}"
IMAGE="${IMAGE:-ubuntu:24.04}"
DOCKER="${DOCKER:-docker}"

repo="$(cd "$(dirname "$0")/../.." && pwd)"
deb_rel="${DEB#"$repo"/}"

"$DOCKER" run --rm -v "$repo:/repo" -w /repo "$IMAGE" bash -c "
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  echo \"==> install the package the way a tester would\"
  apt-get install -y -qq ./$deb_rel
  echo \"==> glibc\"
  ldd --version | head -1
  echo \"==> recording dependency\"
  command -v parecord
  echo \"==> local brief: dlopen libllama.so as the app does\"
  apt-get install -y -qq gcc >/dev/null
  gcc -o /tmp/probe tool/package/dlopen_probe.c -ldl
  LD_LIBRARY_PATH=/opt/forelasning/lib /tmp/probe /opt/forelasning/lib/libllama.so
  echo \"==> speech: dlopen the sherpa-onnx library too\"
  LD_LIBRARY_PATH=/opt/forelasning/lib /tmp/probe /opt/forelasning/lib/libsherpa-onnx-c-api.so
"
