#!/bin/bash
source ./common.sh

# Default values
mode=local
target=master
registry=local

# Parse the command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --mode|-m) mode=$2; shift ;;
        --target|-t) target=$2; shift ;;
        --registry|-r) registry=$2; shift ;;
        --app|-a) deployApp=1 ;;
        --couchbase|-c) deployCouchbase=1 ;;
        *) showInvalidOption "$1" ;;
    esac
    shift
done

if [ -z "$deployApp" ] && [ -z "$deployCouchbase" ]; then
    printErr "Specify a stack to deploy: --app | --couchbase"
    exit 1
fi

networkId=$(docker network ls --filter name=fb_overlay -q)
if [ -z "$networkId" ]; then
    echo "Creating overlay network..."
    docker network create --driver overlay --subnet=173.0.0.0/24 fb_overlay
    checkExitCode "Failed to create overlay network"
fi

export mode
export target
export registry

if [ -n "$deployCouchbase" ]; then
    # Deploy the couchbase container
    if [ -z "$couchbase__volume" ]; then
        export couchbase__volume="./deploy/$mode/couchbase"
        mkdir -p "$couchbase__volume"
    fi

    docker stack deploy -c ./stack-couchbase.yml couchbase --with-registry-auth
    checkExitCode "Failed to deploy the couchbase stack"

    echo "To tear down the 'couchbase' stack run:"
    echo "docker stack rm couchbase"
fi

if [ -n "$deployApp" ]; then
    # Deploy the fb-web & haproxy service
    if [ -z "$fbweb__volume" ]; then
        export fbweb__volume="./deploy/$mode/fb-web"
        mkdir -p "$fbweb__volume"
    fi

    docker stack deploy -c ./stack-app.yml app --with-registry-auth
    checkExitCode "Failed to deploy the app stack"

    echo "To tear down the 'app' stack run:"
    echo "docker stack rm app"
fi
