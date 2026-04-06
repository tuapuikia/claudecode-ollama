# Ollama & Claude Code Developer Environment

A powerful, containerized development environment that integrates local LLM hosting via **Ollama** with **Claude Code** (Anthropic's AI-powered coding agent). This environment is pre-configured with a modern DevOps and programming toolset, providing a unified workspace for AI-assisted engineering.

## 🚀 Features

- **Local LLM Engine**: Host and run models like `gemma4`, `qwen3.5`, and `gemma2` locally using Ollama.
- **Claude Code Integration**: Use Claude's specialized coding agent to interact with your codebase and local tools.
- **Batteries-Included Toolset**:
    - **Languages**: Go (1.24.5), Rust, Node.js (22.x), Python 3, Dart.
    - **DevOps**: Terraform, Terragrunt, AWS CLI, Ansible, Ansible-Lint.
    - **System**: Docker CLI, uv, weasyprint, youtube-dl.
- **GPU Acceleration**: Built-in support for NVIDIA GPUs via Docker Compose.
- **Persistent Storage**: Local volume mapping for model data and workspace persistence.

## 🛠 Prerequisites

- **NVIDIA Drivers** installed
- **[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)** installed
- **Docker** and **Docker Compose**
- `sudo` access (depending on your Docker socket permissions)

## 📦 Setup & Usage

### 1. Build the Environment
Ensure your Docker images are built and tagged correctly. (Assuming a `build.sh` exists to tag images as `tuapuikia/ollama:claude` and `tuapuikia/claude-code:latest`).

### 2. Start the Ollama Server
Use the interactive startup script to select a model family and launch the background service.

```bash
./start_ollama.sh [--no-docker]
```
- **Option 1 (Default)**: Starts the API server without pre-loading any models.
- **Option 2**: Interactive model selection and pre-loading.
- **--no-docker**: Optional flag to skip mounting the Docker socket (useful for enhanced security when Claude Code's container management features are not needed).

### 3. Interact with Models & Claude Code
To run a local model shell or launch Claude Code inside the existing Ollama container:

```bash
./run_model.sh
```
**Options:**
- **Ollama Shell**: Direct interaction with the loaded model.
- **Claude Code**: Launch Claude Code within the Ollama environment to leverage installed tools.

### 4. Standalone Claude Code
To run Claude Code in a fresh, isolated container with access to your current directory and host Docker socket:

```bash
./run_claude.sh
```

## 📂 Project Structure

- `Dockerfile`: Based on `ollama/ollama`, includes the full developer toolset.
- `Dockerfile-claude`: A standalone Ubuntu 24.04-based developer environment.
- `docker-compose.yml`: Defines the `ollama` service with GPU support and volume mounts.
- `start_ollama.sh`: Interactive server initialization and model pre-loading.
- `run_model.sh`: Interactive client for model shells and Claude Code.
- `run_claude.sh`: Standalone Claude Code runner.
- `ollama_data/`: Persistent storage for pulled Ollama models.
- `.claude/`: Persistent storage for Claude Code login and session tokens.

## ⚙️ Configuration

- **Environment Variables**: Managed via `.env` (automatically updated by `start_ollama.sh`).
- **User**: Runs as the `ubuntu` user (UID 1000) with passwordless `sudo` privileges inside the containers.
- **Persistence**: Login tokens and models are stored in local hidden directories (`.claude/` and `ollama_data/`).
- **Docker Support**: The host's `/var/run/docker.sock` is mounted to allow Claude Code to manage other containers.
- **Workspace**: The project root is mounted to `/workspace` inside the containers with write access for coding tasks.
- **API Access**: Port `11434` is exposed for REST API access.

## 🛡 Security Note

The environment mounts `/var/run/docker.sock` to allow containers to manage other Docker resources. Ensure you trust the scripts and models you are running in this environment.
