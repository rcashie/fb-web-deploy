#!/bin/bash
source ./common.sh

# Change the target at every release
target=v0.4.2-alpha
swarm_manager=swarm-node-generic-a
registry=registry.gitlab.com/rcashie/fbastard

# Parse the command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --app|-a) deployApp=1 ;;
        --couchbase|-c) deployCouchbase=1 ;;
        *) showInvalidOption "$1" ;;
    esac
    shift
done

dockerMachineExec() {
    ( eval "$(docker-machine env $1)"  && eval "$2" )
}

dockerMachineExec -u \
    "./build.sh --mode prod \
        --registry $registry \
        --target $target \
        --googleTagId GTM-T4DGPD \
    "
checkExitCode

docker login "$registry"
checkExitCode "Failed to log into docker registry '$registry'"

if [ -z "$deployApp" ] && [ -z "$deployCouchbase" ]; then
    echo "No stack (--app or --couchbase) was specified"
fi

if [ -n "$deployCouchbase" ]; then
    dockerMachineExec -u "docker push \"$registry/couchbase:prod-$target\""
    checkExitCode "Failed to push the couchbase image to the registry"

    export couchbase__volume="/mnt/blockstorage"
    dockerMachineExec "$swarm_manager" \
        "./deploy.sh --mode prod \
            --registry $registry \
            --target $target \
            --couchbase \
        "
    checkExitCode
fi

if [ -n "$deployApp" ]; then
    dockerMachineExec -u "docker push \"$registry/fb-web:prod-$target\""
    checkExitCode "Failed to push the fb-web image to the registry"

    dockerMachineExec -u "docker push \"$registry/haproxy:prod-$target\""
    checkExitCode "Failed to push the haproxy image to the registry"

    export fbweb__volume="/mnt/blockstorage"
    dockerMachineExec "$swarm_manager" \
        "./deploy.sh --mode prod \
            --registry $registry \
            --target $target \
            --app \
        "
    checkExitCode
fi
