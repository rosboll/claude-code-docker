#!/bin/bash
# Shared launcher for the containerised agents. Called by `dcc` and `dco`.
#   _run.sh <service> [workspace-dir] [command...]
set -euo pipefail

SERVICE="${1:?usage: _run.sh <claude|claude-local> [workspace-dir] [command...]}"
shift

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export DOCKER_UID=$(id -u)
export DOCKER_GID=$(id -g)
# Canonicalise: Compose resolves relative bind-mount sources against the
# compose file's directory, so a relative arg like "." would mount the repo.
WORKSPACE_DIR="$(readlink -m -- "${1:-$(pwd)}")"
if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "_run.sh: workspace '${1}' is not a directory" >&2
    exit 2
fi
export WORKSPACE_DIR
[ "$#" -gt 0 ] && shift || true

# These files must exist before the run, or Docker creates a directory at the
# bind-mount point. They must also be valid JSON: an empty file parses as
# "Unexpected end of JSON input", not as absent config. Never clobbers content.
seed_json() {
    for f in "$@"; do
        [ -s "$f" ] || printf '{}\n' > "$f"
    done
}

case "$SERVICE" in
    claude)
        mkdir -p "${HOME}/.claude" /tmp/claude
        seed_json "${HOME}/.claude.json"
        ;;
    claude-local)
        # A config tree of its own, so a session against the local model never
        # touches the Anthropic-account login, history, or onboarding state.
        mkdir -p "${HOME}/.claude-local" /tmp/claude-local
        seed_json "${HOME}/.claude-local.json"
        if [ ! -f "${SCRIPT_DIR}/.env" ]; then
            cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
            echo "Created ${SCRIPT_DIR}/.env from the template." >&2
            echo "Point ANTHROPIC_BASE_URL / the ANTHROPIC_DEFAULT_*_MODEL vars at your local LLM before you get useful output." >&2
        fi
        ;;
    *)
        echo "_run.sh: unknown service '${SERVICE}'" >&2
        exit 2
        ;;
esac

# One Compose project per agent, so the two never contend over the same
# network: reconfiguring or tearing down one cannot disturb a live session of
# the other. Container names become dcc-claude-run-* / dco-claude-local-run-*.
PROJECT="dcc"
[ "$SERVICE" = "claude-local" ] && PROJECT="dco"

exec docker compose -p "$PROJECT" -f "${SCRIPT_DIR}/docker-compose.yml" run --rm "$SERVICE" "$@"
