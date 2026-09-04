#!/usr/bin/env bash
# Build llama.cpp for the Linux package.
#
# Why not the prebuilt llm_llamacpp downloads: that one is linked against CUDA,
# and libggml-cuda.so needs libcuda.so.1 - the NVIDIA *driver* library. It
# cannot be bundled, and pulling it from apt drags in NVIDIA driver packages. So
# on a tester machine without an NVIDIA card the app records and transcribes and
# then cannot load libllama.so at all. Building here gives libraries with no GPU
# dependency that run on any x86-64 Linux.
#
# The commit is the submodule pin of the llm_llamacpp release in pubspec.lock,
# so the C API matches the generated FFI bindings.
# tool/package/find_llamacpp_pin.sh re-derives it after a package upgrade.
#
#   wsl -d Ubuntu -- bash tool/package/build_llamacpp_linux.sh
#
set -euo pipefail

LLAMA_COMMIT="${LLAMA_COMMIT:-25ae3a9b331fffea50ff8d07a5cad34c33f1276f}"
SRC="$HOME/build/llama.cpp"
BUILD="$HOME/build/llama.cpp-build"
OUT="${1:-$HOME/build/llamacpp-linux-x64}"

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
if ! git -C "$SRC" cat-file -e "${LLAMA_COMMIT}^{commit}" 2>/dev/null; then
  echo "==> fetching llama.cpp $LLAMA_COMMIT"
  git -C "$SRC" fetch -q --depth 1 origin "$LLAMA_COMMIT"
fi
git -C "$SRC" checkout -q --detach "$LLAMA_COMMIT"
echo "==> llama.cpp at $(git -C "$SRC" rev-parse --short HEAD)"

rm -rf "$BUILD"
# GGML_NATIVE=OFF is the flag that matters for a package: left on, ggml compiles
# for this machine CPU and a tester with an older one gets an illegal
# instruction. The rest is off because the app only needs the library.
cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DGGML_NATIVE=OFF -DGGML_CUDA=OFF -DGGML_VULKAN=OFF -DGGML_OPENMP=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF -DLLAMA_CURL=OFF

cmake --build "$BUILD" --config Release -j "$(nproc)"

rm -rf "$OUT"; mkdir -p "$OUT"
# Copy the real files, not the version symlinks; the packaging step recreates
# the SONAME links itself.
find "$BUILD" -name "lib*.so*" -type f -exec cp {} "$OUT/" \;

echo "==> built into $OUT"
ls -la "$OUT"
echo "==> CUDA references (expect none)"
if objdump -p "$OUT"/*.so* 2>/dev/null | grep -i cuda; then
  echo "UNEXPECTED: a CUDA dependency survived" >&2
  exit 1
fi
echo "none"
