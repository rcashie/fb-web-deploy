#!/bin/bash
source ./common.sh

# Default overridable values
mode=local
target=master
registry=local

# Parse the command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --mode|-m) mode=$2; shift ;;
        --target|-t) target=$2; shift ;;
        --registry|-r) registry=$2; shift ;;
        --googleTagId|-a) googleTagId=$2; shift ;;
        *) showInvalidOption "$1" ;;
    esac
    shift
done

# Download the target's source
workDir="./build/$target/$mode"
if [ -f "$workDir/src/README.md" ]; then
    echo "Source for '$target' already exists at '$workDir'."
else
    echo "Downloading source for '$target' to '$workDir'..."
    mkdir -p "$workDir/src"

    status=$(curl -s -L \
        -w "%{http_code}" \
        -H "Accept: application/vnd.github.v3+json" \
        -o "$workDir/src.tar" \
        "https://api.github.com/repos/rcashie/fb-web/tarball/$target")

    checkExitCode "Unable to download source for target"
    if [ "$status" -ne "200" ]; then
        printErr "Failed to download source for target with http status code: $status"
        exit 1
    fi

    tar -x -f "$workDir/src.tar" -C "$workDir/src" --strip-components 1
    checkExitCode "Unable to extract source from downloaded tar file"

    if [ -n "$googleTagId" ]; then
        echo "Updating Google Tag Manager id..."
        sed -i "s/GTM-52XHN7W/$googleTagId/" "$workDir/src/client/html/app.html"
        checkExitCode "Unable to replace Google Tag Manager id"
    fi
fi

# Build the fb-web container
docker build \
    --tag "$registry/fb-web:$mode-$target" \
    --build-arg "sourceDir=$workDir/src" \
    --file "./fb-web/dockerfile" \
    .

checkExitCode "Failed to build the fb-web image"

# Build the haproxy container
docker build \
    --tag "$registry/haproxy:$mode-$target" \
    --file "./haproxy/dockerfile" \
    .

checkExitCode "Failed to build the haproxy image"

# Build the couchbase container
docker build \
    --tag "$registry/couchbase:$mode-$target" \
    --file "./couchbase/dockerfile" \
    .

checkExitCode "Failed to build the couchbase image"
