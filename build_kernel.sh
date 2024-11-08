#!/bin/bash

export PATH=$(pwd)/toolchain/clang-r498229b/bin:$PATH
export PATH=$(pwd)/toolchain/path/linux-x86:$(pwd)/toolchain/gas/linux-x86:$PATH

make PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s LLVM=1 LLVM_IAS=1 ARCH=arm64 TARGET_SOC=s5e8825 O=/home/romy/romy/a53/out CROSS_COMPILE=$(pwd)/toolchain/clang-r498229b/bin/aarch64-linux-gnu- s5e8825-a53xxx_defconfig
make PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s LLVM=1 LLVM_IAS=1 ARCH=arm64 TARGET_SOC=s5e8825 O=/home/romy/romy/a53/out CROSS_COMPILE=$(pwd)/toolchain/clang-r498229b/bin/aarch64-linux-gnu- -j$(nproc --all)
