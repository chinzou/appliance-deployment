#!/usr/bin/env bash
mkdir -p $1
set -e
if [ -p /dev/stdin ]; then
        args=()
        args+=( '--src' 'docker' '--dest' 'dir' '--override-arch' 'arm64' '--override-os' 'linux' );
        if [ ! -z ${REGISTRY_USER} ]; then 
                args+=("--src-creds" "${REGISTRY_USER}:${REGISTRY_PASSWORD}" );
        fi
        echo ${args[@]}
        while IFS= read line; do
                skopeo sync "${args[@]}" --scoped ${line} $1
        done
        
else
        echo "No input was found on stdin, skipping!"
        # Checking to ensure a filename was specified and that it exists
        if [ -f "$1" ]; then
                echo "Filename specified: ${1}"
                echo "Doing things now.."
        else
                echo "No input given!"
        fi
fi
