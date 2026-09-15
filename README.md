# claude-code-docker

Run [Claude Code](https://claude.ai/code) in an isolated Docker container, with any project folder on your host mounted as the workspace.

Two launchers, one image, one binary — the only difference is which model backend Claude Code talks to:

| Command | Agent | Model backend |
| --- | --- | --- |
| `dcc` | Claude Code | Anthropic, via your Claude account |
| `dco` | Claude Code | Your own model, behind an Anthropic-compatible endpoint |

Each launcher gets its own config tree, so the two never share auth, history, or onboarding state and can run against the same project at the same time.

## Why

- Keeps Claude Code and its dependencies off your host system
- Reusable across any project folder — point it at whatever you're working on
- Auth and memory persist across sessions via volume mounts
- Files created inside the container are owned by your host user
- Local-model endpoint config lives in one gitignored `.env`, never in the image

## Prerequisites

- Docker with the Compose plugin
- For `dcc`: a Claude account (you'll log in on first run)
- For `dco`: a model served behind an **Anthropic-compatible** API — see below

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/rosboll/claude-code-docker.git ~/claude-code-docker
```

Clone it wherever you like — the launcher scripts find `docker-compose.yml` relative to themselves.

### 2. Build the image

```bash
cd ~/claude-code-docker
docker compose build
```

Both services share the image `claude-code-docker:latest`, so this builds once.

### 3. Add to PATH (optional but recommended)

```bash
ln -s ~/claude-code-docker/dcc ~/.local/bin/dcc
ln -s ~/claude-code-docker/dco ~/.local/bin/dco
```

Make sure `~/.local/bin` is on your `PATH`. Symlinks are fine — the scripts resolve back to the repo to find `_run.sh` and the compose file.

## Usage

```bash
# Claude Code via your Anthropic account, current directory as workspace
dcc

# Claude Code via your local model, current directory as workspace
dco

# Either one, against a specific project folder
dcc /path/to/project
dco /path/to/project

# Run a one-off command instead of an interactive shell
dco /path/to/project claude --version
```

For `dcc`, authenticate inside the container on first run with `/login`.

## Pointing `dco` at your local model

### The base URL, and the `/v1` trap

Claude Code speaks the Anthropic wire format and appends the path itself, so
`ANTHROPIC_BASE_URL` is the **host and port only** — no trailing `/v1`:

```bash
ANTHROPIC_BASE_URL=http://host.docker.internal:8000   # -> POST /v1/messages
```

Leaving a `/v1` on the end produces `/v1/v1/messages` and 404s.

This is the one thing that differs from an OpenAI-style client, which *does*
take the `/v1` as part of the base. Many gateways serve both formats off the
same host and port — OpenAI-shaped requests at `/v1/chat/completions`,
Anthropic-shaped ones at `/v1/messages` — so an endpoint you previously reached
with `OPENAI_BASE_URL=http://host:8000/v1` is usually reached here as
`http://host:8000`, with nothing to change server-side.

If your endpoint genuinely only speaks OpenAI, put an Anthropic-compatible shim
in front of it (claude-code-router, LiteLLM's Anthropic passthrough, or similar)
and point `dco` at the shim.

### Configuration

The first `dco` run copies `.env.example` to `.env` in the repo directory. `.env` is gitignored — put the real values there. The minimum that works:

```bash
ANTHROPIC_BASE_URL=http://host.docker.internal:8000
ANTHROPIC_AUTH_TOKEN=dummy

ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3.8
ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3.8
ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.8
ANTHROPIC_DEFAULT_MODEL=qwen3.8
```

Compose injects that file into the `claude-local` service only, so `dcc` keeps talking to Anthropic with your account.

Three things differ from the bare `export ANTHROPIC_BASE_URL=... && claude` you'd run on a host:

**`localhost` is the container, not your machine.** Use `host.docker.internal` to reach a port on the Docker host — see *Reaching a model on the Docker host* below.

**Set an auth token.** Without a credential Claude Code falls back to your Anthropic subscription login and sends *that* to your endpoint. `ANTHROPIC_AUTH_TOKEN` is sent as `Authorization: Bearer <value>`; any placeholder works if your endpoint ignores auth. Prefer it over `ANTHROPIC_API_KEY`, which also triggers a one-time approval prompt in interactive mode.

**Set all the model aliases, not just Opus.** Each alias resolves independently. `ANTHROPIC_DEFAULT_HAIKU_MODEL` in particular backs background work (session titles, summaries), so leaving it unset makes Claude Code request a real Anthropic Haiku ID your endpoint has never heard of — the visible session works while background calls fail.

### Other useful knobs

All are commented in `.env.example`:

| Variable | Purpose |
| --- | --- |
| `API_TIMEOUT_MS` | Request deadline in ms, default `600000`. Raise it for slow local inference; max `2147483647`, above which requests fail immediately. |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Caps requested output tokens — lower it for a model with a small context window |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Model for subagents, if you want a cheaper one than the main model |
| `ANTHROPIC_CUSTOM_MODEL_OPTION` | Adds a literal model ID to the `/model` picker |
| `ANTHROPIC_CUSTOM_HEADERS` | Extra headers, `Name: Value`, newline-separated |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Suppresses telemetry, error reporting and the auto-updater, so the only egress is to your endpoint |
| `ENABLE_TOOL_SEARCH` | Claude Code disables MCP tool search on a non-first-party base URL; re-enable only if your proxy forwards `tool_reference` blocks |

Two behaviours change automatically when `ANTHROPIC_BASE_URL` points somewhere other than `api.anthropic.com`: MCP tool search is off by default (above), and Remote Control is disabled. Both are expected, not misconfiguration.

### Reaching a model on the Docker host

The container is on a bridge network, so a model served on another machine works as-is. If the endpoint lives on the *same* host as Docker — including an SSH local forward, the common case — `localhost` inside the container is the container itself, and you need `host.docker.internal`.

The compose file already defines that alias for both services, so there is nothing to add:

```yaml
extra_hosts:
  - "host.docker.internal:${HOST_GATEWAY:-host-gateway}"
```

Just point the base URL at it:

```bash
ANTHROPIC_BASE_URL=http://host.docker.internal:8000
```

**The forward must not be loopback-only.** `ssh -L 8000:localhost:8000 host` listens on `127.0.0.1`, which the container cannot reach — `host.docker.internal` resolves to the bridge gateway address, not loopback. Bind it wider:

```bash
ssh -L 0.0.0.0:8000:localhost:8000 <user>@<host>      # exposes the port to your LAN
docker network inspect dco_default -f '{{(index .IPAM.Config 0).Gateway}}'
ssh -L 172.19.0.1:8000:localhost:8000 <user>@<host>   # bridge only, tighter
```

The bridge gateway address is stable until the network is recreated.

**If `host-gateway` doesn't resolve**, the magic value points at the *default* `docker0` bridge, which is down whenever nothing uses the default network. Set `HOST_GATEWAY` in `.env` to this project's own gateway — the same `docker network inspect` command above prints it.

### Reaching a model over a WireGuard tunnel

If the model server is reachable from your laptop only through WireGuard, the container generally needs no special treatment: its traffic is source-NATed to the host and then follows the host's routing table into `wg0`. No tunnel inside the container, no `network_mode: host`.

Note that an SSH local forward sidesteps most of this — the tunnel then terminates on the *host*, and the container only ever talks to the bridge. The items below apply when the container addresses the remote endpoint directly.

**MTU.** WireGuard usually runs at 1420 while the docker bridge defaults to 1500. The signature is distinctive — handshakes and small requests succeed, then the first prompt carrying real file context hangs. Check the tunnel and match it:

```bash
ip link show wg0 | grep -o 'mtu [0-9]*'
echo 'DOCKER_MTU=1420' >> .env      # use whatever the tunnel reports
docker compose -p dco down          # network is recreated with the new MTU
```

Exit any running `dco` session first: a network cannot be recreated while a container is attached to it. Sessions of the *other* launcher are unaffected.

**DNS.** On a systemd-resolved host, `/etc/resolv.conf` is the `127.0.0.53` stub. Docker refuses to hand a loopback resolver to containers and substitutes public ones, so an internal hostname that resolves fine on your laptop returns NXDOMAIN inside the container. Either put a literal IP in `ANTHROPIC_BASE_URL`, or uncomment the `dns:` block on the `claude-local` service and point it at the resolver behind the tunnel.

**Subnet collision.** If Docker auto-assigns a bridge subnet that overlaps a network reachable through the tunnel, the container treats the model host as link-local and never routes it to `wg0`. This is a daemon-level setting, not a per-project one — confine Docker to a range you know is free:

```json
// /etc/docker/daemon.json
{ "default-address-pools": [ { "base": "172.31.240.0/20", "size": 24 } ] }
```

followed by `sudo systemctl restart docker`.

Diagnosing, from the host outward:

```bash
ip route get <llm-ip>                              # host routes it via wg0?
dco . bash -lc 'ip route get <llm-ip>'             # container agrees it is non-local?
dco . bash -lc 'getent hosts <llm-hostname>'       # DNS works inside the container?
dco . bash -lc 'curl -sS -o /dev/null -w "%{http_code}\n" "$ANTHROPIC_BASE_URL/v1/models" -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN"'
```

If the small request returns 200 but real sessions stall, it is the MTU — nothing else produces that split.

## What's mounted

| Host path | Container path | Used by |
| --- | --- | --- |
| your project folder | `/workspace` | both |
| `~/.claude`, `~/.claude.json` | `/home/ubuntu/.claude`, `/home/ubuntu/.claude.json` | `dcc` |
| `~/.claude-local`, `~/.claude-local.json` | *the same container paths* | `dco` |
| `~/.ssh/claude` | `/home/ubuntu/.ssh` (read-only) | both |
| `/tmp/claude` / `/tmp/claude-local` | `/tmp/claude` | respective launcher |

The two launchers run the same binary at the same container paths; only the **host** side of each mount differs. That is what keeps their state separate without needing `CLAUDE_CONFIG_DIR` or any other relocation variable inside the container.

## Notes

- **Auth and memory persist** across sessions via the volume mounts above
- **Project files are never stored inside the container** — they live on your host, mounted at `/workspace`
- **The container is ephemeral** (`--rm`) — anything installed during a session is lost on exit. Add tools you want permanently to the `Dockerfile` and rebuild
- **Rebuilding the image** does not affect your project files or agent config — those are on mounted volumes, not in the image
- **Project memory** is keyed to the path inside the container (`/workspace`), so all projects share one memory namespace per launcher — generally harmless, but worth knowing
- **Missing host files** (`~/.claude.json`, `~/.claude-local.json`, the `/tmp` dirs) are created automatically by the launchers before each session, so no manual setup is required
- **UID/GID mapping** is handled by the container entrypoint — files created inside the container are owned by your host user even if your UID differs from the image default
- **Each launcher runs in its own Compose project** (`dcc` and `dco`), so they get separate networks. Reconfiguring or tearing down one cannot disturb a live session of the other — which matters, because `docker compose down` in a shared project would kill a running session of the *other* launcher
- **Node.js 22** is in the image for `npx`-based MCP servers and JS tooling in mounted projects, not for Claude Code itself — the installer ships its own runtime. Drop that layer from the `Dockerfile` if you need neither

## Troubleshooting

### Claude asks to log in on every `dcc` session

Check whether any files inside `~/.claude/` are owned by `root`:

```bash
ls -la ~/.claude/
```

Root-owned files can be created if the container was ever started directly (not via the launcher) before the UID mapping was in place. The container process can't read or write them, so auth state and session memory don't persist.

```bash
sudo chown -R $USER:$USER ~/.claude/
```

The same applies to `~/.claude-local/` for `dco`.

### `dco` can't reach the model

```bash
dco . bash -lc 'curl -sS -o /dev/null -w "%{http_code}\n" "$ANTHROPIC_BASE_URL/v1/models" -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN"'
```

A connection error means the endpoint isn't reachable from the bridge network — see *Reaching a model on the Docker host*. A `404` on `/v1/models` is fine on its own; some shims only implement `/v1/messages`. Nothing at all in the environment means `.env` wasn't picked up: it must sit next to `docker-compose.yml`.

### `dco` starts but calls fail with an unknown-model error

Usually one of the `ANTHROPIC_DEFAULT_*_MODEL` aliases is still unset and resolving to a real Anthropic model ID. Check all four inside a session:

```bash
dco . bash -lc 'env | grep ANTHROPIC_'
```

If only background features misbehave while the session itself works, it's `ANTHROPIC_DEFAULT_HAIKU_MODEL`.

### `400 Unexpected reasoning effort high`

Claude Code sends a reasoning-effort level on every request and defaults to
`high`. Gateways validate that field against their own list, which may not
include `high`:

```
API Error: 400 Unexpected reasoning effort high.
Supported types are xhigh (default), medium, and low.
```

Pin it to a level your endpoint accepts. Claude Code takes `low`, `medium`,
`high` or `xhigh`:

```bash
CLAUDE_CODE_EFFORT_LEVEL=xhigh
```

Note this is the *input*; `CLAUDE_EFFORT` is a different variable that Claude
Code exports read-only to hooks and Bash, and setting it does nothing.

Setting `CLAUDE_CODE_EFFORT_LEVEL` pins the level for the whole session, so
`/effort` in-session will report that it's overridden — which is what you want
when only some levels are valid on your gateway.

### `dco` uses my Anthropic account instead of the local model

`ANTHROPIC_AUTH_TOKEN` isn't set, so Claude Code fell back to a subscription login found in the mounted config. Set it in `.env`.

## Updating

```bash
cd ~/claude-code-docker
git pull
docker compose build --pull
```

If you symlinked the launchers, script changes take effect immediately after
`git pull` — no re-linking needed.

**That will not update Claude Code itself.** The install step is

```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash
```

whose cache key is the command string, which never changes. Docker reuses the
cached layer on every rebuild, so the Claude Code version in the image is frozen
at whenever that layer was first built. `--pull` only refreshes the `ubuntu:24.04`
base — if its digest is unchanged, every later layer stays cached and Claude Code
stays put. Check what you actually have:

```bash
docker run --rm claude-code-docker:latest claude --version
```

To force a refresh, bust the cache:

```bash
docker compose build --no-cache          # rebuilds everything, a few minutes
```

For `dcc` this matters less than it looks: Claude Code's own auto-updater runs
inside the session. But the container is `--rm` and `~/.local` isn't mounted, so
an in-session update is discarded on exit and re-downloaded next time — the image
is what determines your starting version. For `dco` the updater is suppressed by
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, so the image version is the *only*
version, which is usually what you want for a self-contained local-model setup.
