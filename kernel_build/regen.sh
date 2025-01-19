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

# Configs
OUTDIR="$(pwd)/out"
MODULES_OUTDIR="$(pwd)/modules_out"
TMPDIR="$(pwd)/kernel_build/tmp"

IN_PLATFORM="$(pwd)/kernel_build/vboot_platform"
IN_DLKM="$(pwd)/kernel_build/vboot_dlkm"
IN_DTB="$OUTDIR/arch/arm64/boot/dts/exynos/s5e8825.dtb"

PLATFORM_RAMDISK_DIR="$TMPDIR/ramdisk_platform"
DLKM_RAMDISK_DIR="$TMPDIR/ramdisk_dlkm"
PREBUILT_RAMDISK="$(pwd)/kernel_build/boot/ramdisk"
MODULES_DIR="$DLKM_RAMDISK_DIR/lib/modules"

kfinish() {
    rm -rf "$TMPDIR"
    rm -rf "$MODULES_OUTDIR"
}

kfinish

DIR="$(readlink -f .)"
PARENT_DIR="$(readlink -f ${DIR}/..)"

export CROSS_COMPILE="$PARENT_DIR/clang-r536225/bin/aarch64-linux-gnu-"
export CC="$PARENT_DIR/clang-r536225/bin/clang"

export PLATFORM_VERSION=15.0
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

# Non KSU
make -j$(nproc --all) -C $(pwd) O=out $BUILD_ARGS a53x_defconfig >/dev/null
cp -rfv out/.config arch/arm64/configs/a53x_defconfig
sed -i 's/^# CONFIG_KSU is not set$/CONFIG_KSU=n/' arch/arm64/configs/a53x_defconfig

# KSU
make -j$(nproc --all) -C $(pwd) O=out $BUILD_ARGS a53x-ksu_defconfig >/dev/null
cp -rfv out/.config arch/arm64/configs/a53x-ksu_defconfig

# Git my beloved
git add arch/arm64/configs/a53x_defconfig arch/arm64/configs/a53x-ksu_defconfig
git commit -m "defconfigs: Regenerate with regen.sh"
