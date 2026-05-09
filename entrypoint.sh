#!/bin/bash
set -euo pipefail

HOST_UID="${DOCKER_UID:-1000}"
HOST_GID="${DOCKER_GID:-1000}"

UBUNTU_UID=$(id -u ubuntu)
UBUNTU_GID=$(id -g ubuntu)

if [ "$HOST_GID" != "$UBUNTU_GID" ]; then
    groupmod -g "$HOST_GID" ubuntu
fi

if [ "$HOST_UID" != "$UBUNTU_UID" ]; then
    usermod -u "$HOST_UID" ubuntu
fi

if [ "$HOST_UID" != "$UBUNTU_UID" ] || [ "$HOST_GID" != "$UBUNTU_GID" ]; then
    chown -R ubuntu:ubuntu /home/ubuntu
fi

exec runuser --preserve-environment -u ubuntu -- "$@"
