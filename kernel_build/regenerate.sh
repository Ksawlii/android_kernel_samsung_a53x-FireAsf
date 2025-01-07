#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Please exec from root directory"
    exit 1
fi
cd "$1"

if [ "$(uname -m)" != "x86_64" ]; then
  echo "This script requires an x86_64 (64-bit) machine."
  exit 1
fi

export PATH="$(pwd)/kernel_build/bin:$PATH"

# Config
OUTDIR="$(pwd)/out"

# Kernel-side
BUILD_ARGS="KBUILD_BUILD_USER=Ksawlii KBUILD_BUILD_HOST=FireAsFuck"

export CROSS_COMPILE="$PARENT_DIR/clang-r536225/bin/aarch64-linux-gnu-"
export CC="$PARENT_DIR/clang-r536225/bin/clang"

export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s
export PATH="$PARENT_DIR/build-tools/path/linux-x86:$PARENT_DIR/clang-r536225/bin:$PATH"
export TARGET_SOC=s5e8825
export LLVM=1 LLVM_IAS=1
export ARCH=arm64

if [ ! -d "$PARENT_DIR/clang-r536225" ]; then
  git clone -j$(nproc --all) https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r536225.git -b 15.0 "$PARENT_DIR/clang-r536225" --depth=1
fi

if [ ! -d "$PARENT_DIR/build-tools" ]; then
    git clone https://android.googlesource.com/platform/prebuilts/build-tools "$PARENT_DIR/build-tools" --depth=1
fi

# Dirs
DIR="$(readlink -f .)"
PARENT_DIR="$(readlink -f ${DIR}/..)"

# Non ksu
make -j$(nproc --all) -C $(pwd) O=out $BUILD_ARGS a53x_defconfig >/dev/null
mv $OUTDIR/.config $(pwd)/arch/arm64/config/a53x_defconfig

# KSU
make -j$(nproc --all) -C $(pwd) O=out $BUILD_ARGS a53x-ksu_defconfig >/dev/null
mv $OUTDIR/.config $(pwd)/arch/arm64/config/a53x-ksu_defconfig

# Commit
git add $(pwd)/arch/arm64/config/a53x_defconfig $(pwd)/arch/arm64/config/a53x-ksu_defconfig
git commit -m "defconfigs: Regenerate with regenerate.sh" -m "regenerate.sh: Best work frfr"
