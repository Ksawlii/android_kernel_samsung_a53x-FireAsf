#!/bin/bash
# Unset some variables
unset REGEN

command_one() {
    echo "Building without KernelSU Next..."
    export FIREASF_VANILLA=true
    ./kernel_build/build-fireasf.sh "$(pwd)" || exit 1
    exit 0
}

command_two() {
    echo "Building with KernelSU Next..."
    export FIREASF_VANILLA=false
    ./kernel_build/build-fireasf.sh "$(pwd)" || exit 1
    exit 0
}

command_three() {
    rm -rf setup.sh*
    rm -rf KernelSU*
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs
    echo "Applied KernelSU-Next & susfs4ksu"
}

command_four() {
    if [ "$USE_CCACHE" = "1" ]; then
      export USE_CCACHE=0
    else
      export USE_CCACHE=1
    fi
}

command_five() {
    echo "Regenerating defconfigs"
    export REGEN=true
    ./kernel_build/build-fireasf.sh "$(pwd)" || exit 1
    exit 0
}

command_six() {
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
    if [ "$USE_CCACHE" = "1" ]; then
      echo "4: Disable ccache"
    else
      echo "4: Enable ccache"
    fi
    echo "5: Regenerate defconfigs"
    echo "6: Clean build dirs"
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
        6)
            command_six
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
