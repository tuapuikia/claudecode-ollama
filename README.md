# Ollama with GPU support

This setup runs Ollama with NVIDIA GPU acceleration as a background service, exposing a full REST API for client applications.

## Requirements
- NVIDIA Drivers installed
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed

## Usage

### 1. Start the Background Service
Run this script to select a model, pull it, and keep the container running in the background. 
```bash
./start_ollama.sh
```
*Note: This script also ensures the model stays loaded in GPU memory (`OLLAMA_KEEP_ALIVE=-1`).*

### 2. Connect via API (Non-interactive)
You can now connect any client or tool to `http://localhost:11434`.

#### Example: Chat via `curl`
```bash
curl -X POST http://localhost:11434/api/generate -d '{
  "model": "gemma4:latest",
  "prompt": "Why is the sky blue?",
  "stream": false
}'
```

### 3. (Optional) Run Models Interactively
If you want to quickly test a model in the terminal without using an external client:
```bash
./run_model.sh
```

### 4. Stop the Server
When you are completely finished using Ollama, you can stop the background container:
```bash
docker compose stop
```

## Configuration
- Data is persisted in `./ollama_data`
- Port `11434` is exposed for API access
- The current directory (`.`) is mounted to `/workspace` inside the container for easy file access.
