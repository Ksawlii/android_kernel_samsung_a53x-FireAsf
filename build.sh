#!/bin/bash

command_one() {
    echo "Building without KernelSU..."
    ./kernel_build/build.sh "$(pwd)" || exit 1
}

command_two() {
    echo "Building with KernelSU..."
    ./kernel_build/build-ksu.sh "$(pwd)" || exit 1
}

command_three() {
    rm -rf setup.sh*
    rm -rf KernelSU*
    wget https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh
    chmod +x setup.sh
    ./setup.sh next-susfs-a12-5.10
    rm -rf setup.sh*
}

command_four() {
    echo "Exiting, really that quickly? :sob:"
}

# Main loop
while true; do
    echo ""
    echo "Choose what to do:"
    echo "1: Build FireAsf kernel without KernelSU"
    echo "2: Build FireAsf kernel with KernelSU"
    echo "3: Setup KernelSU Susfs (run before 2)"
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
        exit)
            echo "Exiting the program. Goodbye!"
            break
            ;;
        *)
            echo "Invalid. Learn how to type."
            ;;
    esac
done
