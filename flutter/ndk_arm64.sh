#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == Darwin ]]; then
    # Apple's archive tools can silently produce an empty archive from ELF
    # objects when libsodium's configure script falls back to host tools.
    ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    if [[ -z "$ndk_root" ]]; then
        echo "Set ANDROID_NDK_HOME or ANDROID_NDK_ROOT for Android builds on macOS" >&2
        exit 1
    fi
    ndk_bin="$ndk_root/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    export AR="$ndk_bin/llvm-ar"
    export RANLIB="$ndk_bin/llvm-ranlib"
    export NM="$ndk_bin/llvm-nm"
fi

cargo ndk --platform 21 --target aarch64-linux-android build --locked --release --features flutter,hwcodec
