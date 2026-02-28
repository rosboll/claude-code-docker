FROM ubuntu:24.04
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
    unzip \
    zip \
    wget \
    tree \
    vim \
    make \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER ubuntu
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/ubuntu/.local/bin:${PATH}"
WORKDIR /workspace
CMD ["bash"]
