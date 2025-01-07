#!/bin/bash

command_one() {
    echo "Building without KernelSU..."
    ./kernel_build/build.sh "$(pwd)" || exit 1
}

command_two() {
    echo "Building with KernelSU Next..."
    ./kernel_build/build-ksu.sh "$(pwd)" || exit 1
}

command_three() {
  echo "Regenerating ig"
  ./kernel_build/regenerate.sh "$(pwd)" || exit 1
}

# Main loop
while true; do
    echo ""
    echo "Choose what to do:"
    echo "1: Build FireAsf kernel without KernelSU"
    echo "2: Build FireAsf kernel with KernelSU Next"
    echo "3: Regenerate defconfigs and commit"
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
