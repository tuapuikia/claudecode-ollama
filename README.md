# Ollama & Claude Code Developer Environment

A powerful, containerized development environment that integrates local LLM hosting via **Ollama** with **Claude Code** (Anthropic's AI-powered coding agent). This environment is pre-configured with a modern DevOps toolset and a robust security architecture.

## 🚀 Features

- **Local LLM Engine**: Host and run models like `gemma4` and `qwen3.5` locally via Ollama.
- **Claude Code Integration**: Specialized AI agent for autonomous coding and system management.
- **Batteries-Included Toolset**: Go (1.24.5), Rust, Node.js (22.x), Terraform, AWS CLI, Ansible, and more.
- **GPU Acceleration**: Native support for NVIDIA GPUs.
- **Persistent Sessions**: Claude login info is persisted in your host's `~/.claude` directory.

## 🛡 Security Architecture

This environment is "secure by default," implementing multiple layers of protection:

1.  **Docker Security Proxy**: By default, all Docker commands from the AI agent are routed through a security proxy (`tecnativa/docker-socket-proxy`). This filters dangerous API calls and prevents the AI from gaining root access to your host machine.
2.  **Workspace Validation**: The environment blocks mounting of sensitive host system directories (e.g., `/etc`, `/root`) as workspaces.
3.  **Granular Capabilities**: The AI is granted limited but functional Docker access:
    - ✅ Manage Containers, Images, Networks, and Volumes.
    - ✅ Build new images (using Legacy Builder for proxy compatibility).
    - ✅ Authenticate with registries (Login/Push).
    - ❌ Blocked from Privileged mode and Host system modification.

## 🛠 Prerequisites

- **NVIDIA Drivers** and **[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)**.
- **Docker** and **Docker Compose**.

## 📦 Setup & Usage

### 1. Start the Ollama Server
Use the interactive script to initialize the background service.

```bash
./start_ollama.sh [options]
```

**Options:**
- `--docker-proxy`: (Default) Use the security proxy for Docker access.
- `--host-docker-proxy`: Mount the raw host socket (**WARNING**: Grants AI root access to host).
- `--no-docker`: Disable Docker access entirely.
- `--workspace <path>`: Mount a specific project directory.

### 2. Run Claude Code (Standalone)
Launch a fresh Claude Code session independent of the Ollama stack.

```bash
./run_claude.sh [options]
```
*Note: This script manages its own temporary security proxy and network for each session.*

### 3. Interact via Client
To enter a model shell or launch Claude inside the existing stack:
```bash
./run_model.sh
```

## ⚙️ Configuration Details

- **User**: Runs as `ubuntu` (UID 1000) with passwordless `sudo` inside the container.
- **Persistence**: 
    - Models: `./ollama_data/`
    - Claude Session: `~/.claude/` (Shared across all projects)
- **Networking**: Ollama API exposed at `localhost:11434`.
- **Builds**: Modern BuildKit is disabled (`DOCKER_BUILDKIT=0`) when using the proxy to ensure reliable API filtering.

## 🛡 Security Note
While the Docker Proxy provides a significant security boundary, granting an AI agent access to any Docker socket involves risk. Use `--host-docker-proxy` only when you trust the source of your models and prompts completely.
