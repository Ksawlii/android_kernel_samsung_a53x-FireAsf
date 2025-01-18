#!/bin/bash

command_one() {
    echo "Building without KernelSU Next..."
    ./kernel_build/build.sh "$(pwd)" || exit 1
    exit 0
}

command_two() {
    echo "Building with KernelSU Next..."
    ./kernel_build/build-ksu.sh "$(pwd)" || exit 1
    exit 0
}

command_three() {
    rm -rf setup.sh*
    rm -rf KernelSU*
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next
    cp $(pwd)/patches/0001-KernelSU-Next-Implement-SUSFS-v1.5.3-plus-GKI.patch $(pwd)/KernelSU-Next/0001-KernelSU-Next-Implement-SUSFS-v1.5.3-plus-GKI.patch
    cd $(pwd)/KernelSU-Next/
    patch -p1 < 0001-KernelSU-Next-Implement-SUSFS-v1.5.3-plus-GKI.patch
    cd ..
    echo "Applied susfs4ksu"
}

command_four() {
    echo "Regenerating defconfigs"
    ./kernel_build/regen.sh "$(pwd)" || exit 1
    exit 0
}

command_five() {
    OUTDIR="$(pwd)/out"
    MODULES_OUTDIR="$(pwd)/modules_out"
    TMPDIR="$(pwd)/kernel_build/tmp"
    rm -rf "$TMPDIR"
    rm -rf "$MODULES_OUTDIR"
    rm -rf "$OUTDIR"
    exit 0
}

# Main loop
while true; do
    echo ""
    echo "Choose what to do:"
    echo "1: Build FireAsf kernel without KernelSU Next"
    echo "2: Build FireAsf kernel with KernelSU Next"
    echo "3: Setup KernelSU Next (run before 2)"
    echo "4: Regenerate defconfigs"
    echo "5: Clean build dirs"
    echo "Type 'exit' to guess what? Exit, yeah exit!"
    read -p "Make a good choice: " choice

    case $choice in
        1)
            command_one
            ;;
        2)
            command_two
            ;;
        3)
            command_three
            ;;
        4)
            command_four
            ;;
        5)
            command_five
            ;;
        exit)
            echo "Exiting the program. Goodbye!"
            break
            ;;
        *)
            echo "Invalid. Learn how to type."
            ;;
    esac
done
