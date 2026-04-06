ARG OLLAMA_TAG=0.5.11
FROM ollama/ollama:${OLLAMA_TAG}

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Use the existing 'ubuntu' user (UID 1000)
ENV HOME=/home/ubuntu

# Set environment variables
ENV OLLAMA_VULKAN=false
ENV ROCR_VISIBLE_DEVICES=""
ENV http_proxy=""
ENV https_proxy=""
ENV no_proxy=""

WORKDIR /home/ubuntu

# Ensure the .ollama directory exists and is owned by ubuntu
RUN mkdir -p /home/ubuntu/.ollama && chown -R ubuntu:ubuntu /home/ubuntu/.ollama

# Install dependencies for Claude Code and common tools
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory for the application and ensure ownership
RUN mkdir -p /workspace && chown ubuntu:ubuntu /workspace

# Install Claude Code as the ubuntu user
USER ubuntu
WORKDIR /home/ubuntu
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && \
    echo "431889ac7d056f636aaf5b71524666d04c89c45560f80329940846479d484778  /tmp/install.sh" | sha256sum -c - && \
    chmod +x /tmp/install.sh && \
    yes | /tmp/install.sh && \
    rm /tmp/install.sh

# Ensure Claude Code is in the PATH
ENV PATH="/home/ubuntu/.local/bin:${PATH}"

WORKDIR /workspace

# The entrypoint remains the same as the base ollama image to ensure the server starts correctly
ENTRYPOINT ["/bin/sh", "-c", "/usr/bin/ollama serve"]
