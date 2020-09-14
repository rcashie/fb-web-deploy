#!/bin/bash
printErr() {
    echo -e "\033[31mError: $1\033[0m" 1>&2
}

showInvalidOption() {
    printErr "Invalid parameter '$1'"
    exit 1
}

checkExitCode() {
    if [ $? -ne 0 ]; then
        [ -n "$1" ] && printErr "$1"
        exit 1
    fi
}
