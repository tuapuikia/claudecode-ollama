ARG OLLAMA_TAG=0.20.7
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

# Install dependencies for repositories and common tools
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    git \
    gnupg \
    lsb-release \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    software-properties-common \
    sudo \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Add repositories for Dart, Terraform, Docker, and Node.js
RUN curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" | tee /etc/apt/sources.list.d/dart_stable.list > /dev/null && \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    chmod a+r /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

# Install packages from the added repositories
RUN apt-get update && apt-get install -y \
    terraform \
    dart \
    docker-ce-cli \
    docker-compose-plugin \
    nodejs \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install AWS CLI, Terragrunt, and Go
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip ./aws && \
    curl -sLo /usr/local/bin/terragrunt https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64 && \
    chmod +x /usr/local/bin/terragrunt && \
    curl -LO https://go.dev/dl/go1.24.5.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf go1.24.5.linux-amd64.tar.gz && \
    rm go1.24.5.linux-amd64.tar.gz

# Set up Go and Python environment
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH=/gohome
RUN ln -s /usr/bin/python3 /usr/bin/python && \
    PIP_BREAK_SYSTEM_PACKAGES=1 pip install --no-cache-dir ansible ansible-lint uv weasyprint youtube-dl && \
    mkdir /gohome && chown ubuntu:ubuntu /gohome

# Configure sudo for the ubuntu user
RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set the working directory for the application and ensure ownership
RUN mkdir -p /workspace && chown ubuntu:ubuntu /workspace

# Install Rust and Claude Code as the ubuntu user
USER ubuntu
WORKDIR /home/ubuntu
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && \
    echo "431889ac7d056f636aaf5b71524666d04c89c45560f80329940846479d484778  /tmp/install.sh" | sha256sum -c - && \
    chmod +x /tmp/install.sh && \
    yes | /tmp/install.sh && \
    rm /tmp/install.sh

# Ensure Rust and Claude Code are in the PATH
ENV PATH="/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:${PATH}"

WORKDIR /workspace

# The entrypoint remains the same as the base ollama image to ensure the server starts correctly
ENTRYPOINT ["/bin/sh", "-c", "/usr/bin/ollama serve"]
