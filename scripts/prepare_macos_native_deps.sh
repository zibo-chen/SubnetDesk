#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
native_root=${SUBNETDESK_NATIVE_ROOT:-"$repo_root/target/local-native-deps"}
brew_root=$(brew --prefix)
case $(uname -m) in
  arm64) native_triplet=arm64-osx ;;
  x86_64) native_triplet=x64-osx ;;
  *) echo "Unsupported macOS architecture" >&2; exit 1 ;;
esac
for package in aom libvpx opus; do
  if [[ ! -d "$brew_root/opt/$package/include" ]]; then
    echo "Install macOS build dependencies: brew install aom libvpx opus cmake" >&2
    exit 1
  fi
done

mkdir -p "$native_root/$native_triplet/lib" "$native_root/$native_triplet/include" "$native_root/installed"
ln -sfn "../$native_triplet" "$native_root/installed/$native_triplet"
for package in aom libvpx opus; do
  for library in "$brew_root/opt/$package/lib/"*.a; do
    ln -sfn "$library" "$native_root/$native_triplet/lib/$(basename "$library")"
  done
  for header in "$brew_root/opt/$package/include/"*; do
    ln -sfn "$header" "$native_root/$native_triplet/include/$(basename "$header")"
  done
done

# Use the same libyuv revision as the repository's vcpkg overlay.
yuv_revision=0faf8dd0e004520a61a603a4d2996d5ecc80dc3f
if [[ ! -f "$native_root/libyuv-build/libyuv.a" ]]; then
  mkdir -p "$native_root/libyuv-source"
  git -C "$native_root/libyuv-source" init -q
  git -C "$native_root/libyuv-source" fetch --depth 1 https://chromium.googlesource.com/libyuv/libyuv "$yuv_revision"
  git -C "$native_root/libyuv-source" checkout --detach FETCH_HEAD
  cmake -S "$native_root/libyuv-source" -B "$native_root/libyuv-build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_DISABLE_FIND_PACKAGE_JPEG=TRUE
  cmake --build "$native_root/libyuv-build" --target yuv --parallel 8
fi
ln -sfn "$native_root/libyuv-build/libyuv.a" "$native_root/$native_triplet/lib/libyuv.a"
for header in "$native_root/libyuv-source/include/"*; do
  ln -sfn "$header" "$native_root/$native_triplet/include/$(basename "$header")"
done

# Homebrew's AOM enables VMAF; keep its static dependency in the local archive
# so the application does not acquire a Homebrew dylib dependency.
if [[ -f "$brew_root/opt/libvmaf/lib/libvmaf.a" ]]; then
  /usr/bin/libtool -static -o "$native_root/$native_triplet/lib/libaom-bundled.a" \
    "$brew_root/opt/aom/lib/libaom.a" "$brew_root/opt/libvmaf/lib/libvmaf.a"
  ln -sfn libaom-bundled.a "$native_root/$native_triplet/lib/libaom.a"
fi
echo "macOS native libraries: $native_root"
