FROM ubuntu:24.04

ARG NODE_MAJOR=22

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    sudo \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    iproute2 \
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    unzip \
    zip \
    wget \
    tree \
    vim \
    make \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Node.js — not needed by Claude Code itself (the installer ships a bundled
# runtime), but kept because `npx`-based MCP servers and most JS tooling in a
# mounted project expect it. Drop this layer if you never need either.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*


USER ubuntu
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/ubuntu/.local/bin:${PATH}"
USER root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
