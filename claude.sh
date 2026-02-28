#!/bin/bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export DOCKER_UID=$(id -u)
export DOCKER_GID=$(id -g)
export WORKSPACE_DIR="${1:-$(pwd)}"
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" run --rm claude
