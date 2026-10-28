#!/usr/bin/env bash
# Builds libveltrio_llm.dylib (llama.cpp + our C wrapper) for:
#   ios-arm64     iPhone, Metal, deployment target IOS_MIN (default 15.0)
#   macos-<arch>  this Mac, CPU only (for local tests)
#
# Usage: scripts/build_native.sh [ios|macos|all]   (default: all)
# Outputs: native/<target>/libveltrio_llm.dylib (git-ignored)
#
# Build flags mirror llama.cpp's build-xcframework.sh, with networking (OpenSSL),
# tools, examples, tests and the multimodal library turned off.
# iOS: BLAS is off because Accelerate's cblas_sgemm needs iOS 16.4 (our target
# is 15.0); Metal does the matrix work on the GPU.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$PKG_DIR/../.." && pwd)"
LLAMA_DIR="$REPO_DIR/third_party/llama.cpp"
BUILD_ROOT="$PKG_DIR/build"
OUT_ROOT="$PKG_DIR/native"
IOS_MIN="${IOS_MIN:-15.0}"
MACOS_MIN="${MACOS_MIN:-13.3}"
JOBS="$(sysctl -n hw.logicalcpu)"

if [[ ! -f "$LLAMA_DIR/include/llama.h" ]]; then
  echo "llama.cpp missing. Run: git submodule update --init --depth 1" >&2
  exit 1
fi

COMMON_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DLLAMA_BUILD_COMMON=OFF
  -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_BUILD_TOOLS=OFF
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_SERVER=OFF
  -DLLAMA_BUILD_APP=OFF
  -DLLAMA_BUILD_MTMD=OFF
  -DLLAMA_OPENSSL=OFF
  -DGGML_NATIVE=OFF
  -DGGML_OPENMP=OFF
  -DGGML_BLAS_DEFAULT=ON
  -DCMAKE_C_FLAGS=-Wno-shorten-64-to-32
  -DCMAKE_CXX_FLAGS=-Wno-shorten-64-to-32
)

# $1 target name, $2 sdk, $3 arch, $4 min-version flag, $5.. extra cmake args
build_target() {
  local target="$1" sdk="$2" arch="$3" min_flag="$4"
  shift 4
  local build_dir="$BUILD_ROOT/$target"
  local out_dir="$OUT_ROOT/$target"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  echo "==> [$target] configuring llama.cpp"
  cmake -S "$LLAMA_DIR" -B "$build_dir" -G "Unix Makefiles" \
    "${COMMON_ARGS[@]}" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    "$@" >/dev/null

  echo "==> [$target] building llama.cpp ($JOBS jobs)"
  cmake --build "$build_dir" --config Release -j "$JOBS" >/dev/null

  echo "==> [$target] linking libveltrio_llm.dylib"
  local libs=()
  while IFS= read -r lib; do libs+=("$lib"); done < <(find "$build_dir" -name '*.a' ! -name combined.a | sort)
  xcrun libtool -static -o "$build_dir/combined.a" "${libs[@]}" 2>/dev/null

  local frameworks=(-framework Foundation -framework Accelerate)
  if [[ "$sdk" == "iphoneos" ]]; then
    frameworks+=(-framework Metal)
  fi

  mkdir -p "$out_dir"
  xcrun --sdk "$sdk" clang++ -dynamiclib -O3 \
    -isysroot "$sysroot" -arch "$arch" "$min_flag" \
    -I "$LLAMA_DIR/include" -I "$LLAMA_DIR/ggml/include" \
    -x c "$PKG_DIR/src/veltrio_llm.c" \
    -Wl,-force_load,"$build_dir/combined.a" \
    "${frameworks[@]}" \
    -install_name "@rpath/libveltrio_llm.dylib" \
    -o "$out_dir/libveltrio_llm.dylib"
  xcrun strip -x "$out_dir/libveltrio_llm.dylib"

  echo "==> [$target] $(du -h "$out_dir/libveltrio_llm.dylib" | cut -f1) -> $out_dir/libveltrio_llm.dylib"
}

build_ios() {
  build_target ios-arm64 iphoneos arm64 "-mios-version-min=$IOS_MIN" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_METAL_TARGET_OS=ios \
    -DGGML_BLAS=OFF
}

build_macos() {
  local arch
  arch="$(uname -m)"
  build_target "macos-$arch" macosx "$arch" "-mmacosx-version-min=$MACOS_MIN" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
    -DGGML_METAL=OFF
}

case "${1:-all}" in
  ios) build_ios ;;
  macos) build_macos ;;
  all) build_macos; build_ios ;;
  *) echo "usage: $0 [ios|macos|all]" >&2; exit 2 ;;
esac
