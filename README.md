# claude-code-docker

Run [Claude Code](https://claude.ai/code) in an isolated Docker container, with any project folder on your host mounted as the workspace.

## Why

- Keeps Claude Code and its dependencies off your host system
- Reusable across any project folder — point it at whatever you're working on
- Auth and memory persist across sessions via volume mounts
- Files created inside the container are owned by your host user

## Prerequisites

- Docker with the Compose plugin
- A Claude account (you'll log in on first run)

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/rosboll/claude-code-docker.git ~/claude-code-docker
```

Clone it wherever you like — the launcher script finds `docker-compose.yml` relative to itself.

### 2. Build the image

```bash
cd ~/claude-code-docker
docker compose build
```

### 3. Make the launcher executable

```bash
chmod +x ~/claude-code-docker/dcc
```

### 4. Add to PATH (optional but recommended)

Symlink into `~/.local/bin/` so you can run `dcc` from anywhere:

```bash
ln -s ~/claude-code-docker/dcc ~/.local/bin/dcc
```

Make sure `~/.local/bin` is on your `PATH`.

### 5. Ensure `~/.claude.json` exists

Docker requires the source of a file bind-mount to already exist as a file on the host. If it doesn't, Docker silently creates a directory there instead, which breaks things:

```bash
touch ~/.claude.json
```

If you've previously run Claude Code on your host, this file already exists.

## Usage

```bash
# Launch with the current directory as workspace
dcc

# Launch with a specific project folder
dcc /path/to/project
```

On first run, authenticate inside the container:

```
claude login
```

## Notes

- **Auth and memory persist** across sessions via the `~/.claude` and `~/.claude.json` volume mounts on your host
- **Project files are never stored inside the container** — they live on your host, mounted at `/workspace`
- **The container is ephemeral** (`--rm` flag) — anything installed during a session is lost on exit. Add tools you want permanently to the `Dockerfile` and rebuild
- **Rebuilding the image** does not affect your project files or Claude config — those are on mounted volumes, not in the image
- **Claude project memory** is keyed to the path inside the container (`/workspace`), so all projects share the same memory namespace — generally harmless, but worth knowing

## Troubleshooting

### Claude asks to log in on every session

If Claude Code prompts for authentication every time you start a container, check whether any files inside `~/.claude/` are owned by `root`:

```bash
ls -la ~/.claude/
```

Root-owned files are created if the container ever ran without the `user:` UID mapping — for example during early testing. The container process (running as your host UID) can't read or write them, so auth state and session memory don't persist.

Fix it by taking ownership back:

```bash
sudo chown -R $USER:$USER ~/.claude/
```

After that, auth will persist normally across sessions.

## Updating

Pull the latest changes and rebuild if the Dockerfile changed:

```bash
cd ~/claude-code-docker
git pull
docker compose build
```

If you symlinked `dcc`, the updated script takes effect immediately after `git pull` — no re-linking needed.
