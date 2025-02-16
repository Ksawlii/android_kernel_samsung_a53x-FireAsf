#!/bin/bash
# FireAsf Variables
FIRE_VERSION="6.0"
FIRE_VARIANT="UnstableAsf"
FIRE_MAINTAINER="Ksawlii"
FIRE_KBUILD="KBUILD_BUILD_USER=${FIRE_MAINTAINER} KBUILD_BUILD_HOST=FireAsFuck"
FIRE_DAY_MONTH=$(date +%e | tr -d ' ') # Removes leading space for single-digit days
FIRE_MONTH=$(date +%m)
FIRE_YEAR=$(date +%Y)
FIRE_HOUR=$(date +%H.%M) # Current hour in 24-hour format
FIRE_ANYKERNEL3="$(pwd)/kernel_build/fire_zip"
if [ "$FIREASF_VANILLA" = "true" ]; then
  FIRE_TYPE="Vanilla"
  FIRE_DEFCONFIG=a53x_defconfig
  FIRE_LOCALVERSION="LOCALVERSION=-FireAsf-${FIRE_VERSION}-${FIRE_TYPE}-${FIRE_VARIANT}"
  KERNELZIP="$(pwd)/kernel_build/FireAsf/$FIRE_DAY_MONTH.$FIRE_MONTH.$FIRE_YEAR/FireAsf-${FIRE_VERSION}-${FIRE_TYPE}-${FIRE_VARIANT}-${FIRE_HOUR}.zip"
  KERNELTAR="$(pwd)/kernel_build/FireAsf/$FIRE_DAY_MONTH.$FIRE_MONTH.$FIRE_YEAR/FireAsf-${FIRE_VERSION}-${FIRE_TYPE}-${FIRE_VARIANT}-${FIRE_HOUR}.tar"
else
  FIRE_TYPE="KN"
  FIRE_DEFCONFIG=a53x-ksu_defconfig
  FIRE_LOCALVERSION="LOCALVERSION=-FireAsf-${FIRE_VERSION}-${FIRE_TYPE}-${FIRE_VARIANT}"
  KERNELZIP="$(pwd)/kernel_build/FireAsf/$FIRE_DAY_MONTH.$FIRE_MONTH.$FIRE_YEAR/FireAsf-${FIRE_VERSION}-${FIRE_TYPE}-${FIRE_VARIANT}-${FIRE_HOUR}.zip"
  KERNELTAR="$(pwd)/kernel_build/FireAsf/$FIRE_DAY_MONTH.$FIRE_MONTH.$FIRE_YEAR/FireAsf-${FIRE_VERSION}-${FIRE_TYPE}-${FIRE_VARIANT}-${FIRE_HOUR}.tar"
fi

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

if [[ $(whoami) != "ksawlii" ]]; then
  export PATH="$(pwd)/kernel_build/bin:$PATH"
fi

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

MKBOOTIMG="$(pwd)/kernel_build/mkbootimg/mkbootimg.py"
MKDTBOIMG="$(pwd)/kernel_build/dtb/mkdtboimg.py"

OUT_KERNEL="$OUTDIR/arch/arm64/boot/Image"
OUT_BOOTIMG="$(pwd)/kernel_build/fire_zip/boot.img"
OUT_VENDORBOOTIMG="$(pwd)/kernel_build/fire_zip/vendor_boot.img"
OUT_DTBIMAGE="$TMPDIR/dtb.img"

kfinish() {
    rm -rf "$TMPDIR"
    rm -rf "$MODULES_OUTDIR"
}

kfinish

DIR="$(readlink -f .)"
PARENT_DIR="$(readlink -f ${DIR}/..)"

export CROSS_COMPILE="$PARENT_DIR/clang-r547379/bin/aarch64-linux-gnu-"
if [ "$USE_CCACHE" = "1" ]; then
  export CC="$PARENT_DIR/clang-r547379/bin/clang ccache"
else
  export CC="$PARENT_DIR/clang-r547379/bin/clang"
fi

export PLATFORM_VERSION=15.0
export ANDROID_MAJOR_VERSION=s
export PATH="$PARENT_DIR/build-tools/path/linux-x86:$PARENT_DIR/clang-r547379/bin:$PATH"
export TARGET_SOC=s5e8825
export LLVM=1 LLVM_IAS=1
export ARCH=arm64

if [ ! -d "$PARENT_DIR/clang-r547379" ]; then
    mkdir -p "$PARENT_DIR/clang-r547379"
    wget -P "$PARENT_DIR" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r547379.tar.gz"
    tar -xzf "$PARENT_DIR/clang-r547379.tar.gz" -C "$PARENT_DIR/clang-r547379"
fi

if [ ! -d "$PARENT_DIR/build-tools" ]; then
    git clone https://android.googlesource.com/platform/prebuilts/build-tools "$PARENT_DIR/build-tools" --depth=1
fi

echo ""
echo -e "Check in btop, htop, top (whatever you use) if its building.
If you have some errors when trying to rebuild, delete $OUTDIR"

make -j$(nproc --all) -C $(pwd) O=out $FIRE_LOCALVERSION $FIRE_KBUILD $FIRE_DEFCONFIG >/dev/null
make -j$(nproc --all) -C $(pwd) O=out $FIRE_LOCALVERSION $FIRE_KBUILD dtbs >/dev/null
make -j$(nproc --all) -C $(pwd) O=out $FIRE_LOCALVERSION $FIRE_KBUILD >/dev/null
make -j$(nproc --all) -C $(pwd) O=out INSTALL_MOD_STRIP="--strip-debug --keep-section=.ARM.attributes" INSTALL_MOD_PATH="$MODULES_OUTDIR" modules_install >/dev/null

rm -rf "$TMPDIR"
rm -f "$OUT_BOOTIMG"
rm -f "$OUT_VENDORBOOTIMG"
mkdir "$TMPDIR"
mkdir -p "$MODULES_DIR/0.0"
mkdir "$PLATFORM_RAMDISK_DIR"

cp -rf "$IN_PLATFORM"/* "$PLATFORM_RAMDISK_DIR/"
mkdir "$PLATFORM_RAMDISK_DIR/first_stage_ramdisk"
cp -f "$PLATFORM_RAMDISK_DIR/fstab.s5e8825" "$PLATFORM_RAMDISK_DIR/first_stage_ramdisk/fstab.s5e8825"

if ! find "$MODULES_OUTDIR/lib/modules" -mindepth 1 -type d | read; then
    echo "Unknown error!"
    exit 1
fi

missing_modules=""

for module in $(cat "$IN_DLKM/modules.load"); do
    i=$(find "$MODULES_OUTDIR/lib/modules" -name $module);
    if [ -f "$i" ]; then
        cp -f "$i" "$MODULES_DIR/0.0/$module"
    else
	missing_modules="$missing_modules $module"
    fi
done

if [ "$missing_modules" != "" ]; then
        echo "ERROR: the following modules were not found: $missing_modules"
	exit 1
fi

depmod 0.0 -b "$DLKM_RAMDISK_DIR"
sed -i 's/\([^ ]\+\)/\/lib\/modules\/\1/g' "$MODULES_DIR/0.0/modules.dep"
cd "$MODULES_DIR/0.0"
for i in $(find . -name "modules.*" -type f); do
    if [ $(basename "$i") != "modules.dep" ] && [ $(basename "$i") != "modules.softdep" ] && [ $(basename "$i") != "modules.alias" ]; then
        rm -f "$i"
    fi
done
cd "$DIR"

cp -f "$IN_DLKM/modules.load" "$MODULES_DIR/0.0/modules.load"
mv "$MODULES_DIR/0.0"/* "$MODULES_DIR/"
rm -rf "$MODULES_DIR/0.0"

echo "Building dtb image..."
python2 "$MKDTBOIMG" create "$OUT_DTBIMAGE" --custom0=0x00000000 --custom1=0xff000000 --version=0 --page_size=2048 "$IN_DTB" || exit 1

echo "Building boot image..."

# TODO: Create a seperate shell script for dependencies
if [ ! -d "$FIRE_ANYKERNEL3" ]; then
  git clone -j$(nproc --all) https://github.com/Ksawlii-Android-Repos/AnyKernel3-a53x.git -b master "$FIRE_ANYKERNEL3"
fi

$MKBOOTIMG --header_version 4 \
    --kernel "$OUT_KERNEL" \
    --output "$OUT_BOOTIMG" \
    --ramdisk "$PREBUILT_RAMDISK" \
    --os_version 12.0.0 \
    --os_patch_level 2024-09 || exit 1

echo "Building vendor_boot image..."

cd "$DLKM_RAMDISK_DIR"
find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > ../ramdisk_dlkm.lz4
cd ../ramdisk_platform
find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > ../ramdisk_platform.lz4
cd ..
echo "buildtime_bootconfig=enable" > bootconfig

$MKBOOTIMG --header_version 4 \
    --vendor_boot "$OUT_VENDORBOOTIMG" \
    --vendor_bootconfig "$(pwd)/bootconfig" \
    --dtb "$OUT_DTBIMAGE" \
    --vendor_ramdisk "$(pwd)/ramdisk_platform.lz4" \
    --ramdisk_type dlkm \
    --ramdisk_name dlkm \
    --vendor_ramdisk_fragment "$(pwd)/ramdisk_dlkm.lz4" \
    --os_version 12.0.0 \
    --os_patch_level 2024-09 || exit 1

cd "$DIR"


echo "Building a flashable zip file (Recovery)..."
mkdir -p "$(pwd)/kernel_build/FireAsf/$FIRE_DAY_MONTH.$FIRE_MONTH.$FIRE_YEAR"
cd "$FIRE_ANYKERNEL3"
rm -f "$KERNELZIP"
if [ "$FIRE_VARIANT" = "StableAsf" ]; then
  zip -r9 -q "$KERNELZIP" $TMPDIR/dtb.img anykernel.sh banner boot.br META-INF modules patch ramdisk tools vendor_boot.br
else
  zip -r0 -q "$KERNELZIP" $TMPDIR/dtb.img anykernel.sh banner boot.img META-INF modules patch ramdisk tools vendor_boot.img
fi
rm -f boot.br vendor_boot.br
cd "$DIR"
echo "Done! Output: $KERNELZIP"

echo "Building a flashable tar file (Download Mode)..."
cd "$(pwd)/kernel_build"
rm -f "$KERNELTAR"
if [ "$FIRE_VARIANT" = "StableAsf" ]; then
  lz4 -c -12 -B6 --content-size "$OUT_BOOTIMG" > boot.img.lz4
  lz4 -c -12 -B6 --content-size "$OUT_VENDORBOOTIMG" > vendor_boot.img.lz4
  tar -cf "$KERNELTAR" boot.img.lz4 vendor_boot.img.lz4
else
  lz4 -c -1 -B6 --content-size "$OUT_BOOTIMG" > boot.img.lz4
  lz4 -c -1 -B6 --content-size "$OUT_VENDORBOOTIMG" > vendor_boot.img.lz4
  tar -cf "$KERNELTAR" boot.img.lz4 vendor_boot.img.lz4
fi
cd "$DIR"
rm -f boot.img.lz4 vendor_boot.img.lz4
echo "Done! Output: $KERNELTAR"

echo "Cleaning..."
rm -f "${OUT_VENDORBOOTIMG}" "${OUT_BOOTIMG}"
kfinish
