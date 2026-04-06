FROM ollama/ollama:latest

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root

# Install dependencies for Claude Code and common tools
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code using the official installer
# We use 'yes' to handle any confirmation prompts during the install process
RUN yes | curl -fsSL https://claude.ai/install.sh | bash

# Ensure Claude Code is in the PATH (the installer usually puts it in ~/.local/bin)
ENV PATH="/root/.local/bin:${PATH}"

# Set the working directory
WORKDIR /workspace

# The entrypoint remains the same as the base ollama image to ensure the server starts correctly
ENTRYPOINT ["/bin/sh", "-c", "/usr/bin/ollama serve"]
