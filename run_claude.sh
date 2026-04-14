#!/bin/bash

# Default values
WORKSPACE_DIR="$(pwd)"
DOCKER_MODE="proxy" # proxy (default), host, none
CLAUDE_HOME="$HOME/.claude"
OLLAMA_CONTEXT_LENGTH="64000"

# Ensure we are executing from the directory where the script lives
cd "$(dirname "$0")"

# Function to validate the workspace path (Fix VULN-002)
validate_workspace() {
    local path="$1"
    # Ensure the path exists and is a directory
    if [ ! -d "$path" ]; then
        echo "Error: Workspace path '$path' does not exist or is not a directory."
        exit 1
    fi
    # Security check: avoid mounting sensitive system directories
    case "$path" in
        /|/etc|/etc/|/root|/root/|/boot|/boot/|/sys|/sys/)
            echo "Security Error: Mounting sensitive system directory '$path' as workspace is not allowed."
            exit 1
            ;;
    esac
}

show_help() {
    echo "Usage: ./run_claude.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help            Show this help message"
    echo "  --docker-proxy        Use a security proxy for Docker access (Default, safe)"
    echo "  --host-docker-proxy   Mount direct host Docker socket (WARNING: Grant AI root access to host)"
    echo "  --no-docker           Disable Docker access completely"
    echo "  --workspace <path>    Specify a custom workspace directory to mount (Default: current directory)"
    echo "  --context-length <n>  Set the Ollama context length (Default: 64000)"
    echo ""
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --docker-proxy)
            DOCKER_MODE="proxy"
            shift
            ;;
        --host-docker-proxy)
            DOCKER_MODE="host"
            shift
            ;;
        --no-docker)
            DOCKER_MODE="none"
            shift
            ;;
        --workspace)
            if [[ -n "$2" ]]; then
                # Resolve to absolute path
                WORKSPACE_DIR=$(readlink -f "$2")
                validate_workspace "$WORKSPACE_DIR"
                shift 2
            else
                echo "Error: --workspace requires a path."
                exit 1
            fi
            ;;
        --context-length|-c)
            if [[ -n "$2" ]]; then
                OLLAMA_CONTEXT_LENGTH="$2"
                shift 2
            else
                echo "Error: --context-length requires a value."
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Cleanup function for proxy mode
cleanup() {
    if [ -n "$PROXY_NAME" ]; then
        echo "------------------------------------------"
        echo "Cleaning up independent security proxy..."
        docker stop "$PROXY_NAME" > /dev/null 2>&1
        docker rm "$PROXY_NAME" > /dev/null 2>&1
        docker network rm "$NET_NAME" > /dev/null 2>&1
    fi
}

# Set variables based on Docker mode
case $DOCKER_MODE in
    host)
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "WARNING: You are granting the AI agent DIRECT access to the"
        echo "host Docker socket. This is equivalent to root access on your"
        echo "host machine. Use only with trusted models and prompts."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        sleep 2
        DOCKER_MOUNT_ARG="-v /var/run/docker.sock:/var/run/docker.sock"
        DOCKER_ENV_ARG=""
        ;;
    proxy)
        # Create a temporary independent network and proxy
        SESSION_ID=$(date +%s)
        PROXY_NAME="claude-proxy-$SESSION_ID"
        NET_NAME="claude-net-$SESSION_ID"
        
        echo "Starting independent security proxy ($PROXY_NAME)..."
        docker network create "$NET_NAME" > /dev/null
        docker run -d --name "$PROXY_NAME" \
            --network "$NET_NAME" \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            -e CONTAINERS=1 -e IMAGES=1 -e NETWORKS=1 -e VOLUMES=1 -e BUILD=1 -e AUTH=1 -e POST=1 -e EXEC=1 -e ALLOW_BIND_MOUNTS=1 \
            tecnativa/docker-socket-proxy > /dev/null
            
        DOCKER_MOUNT_ARG=""
        # Enforce DOCKER_BUILDKIT=0 for maximum compatibility with restricted proxy
        DOCKER_ENV_ARG="-e DOCKER_HOST=tcp://$PROXY_NAME:2375 -e DOCKER_BUILDKIT=0 --network $NET_NAME"
        
        # Ensure cleanup on exit or interrupt
        trap cleanup EXIT INT TERM
        ;;
    *)
        DOCKER_MOUNT_ARG=""
        DOCKER_ENV_ARG=""
        ;;
esac

# Check for .env file in workspace
ENV_FILE_ARG=""
if [ -f "$WORKSPACE_DIR/.env" ]; then
    echo "Info: Found .env file in workspace. Mounting as environment variables."
    ENV_FILE_ARG="--env-file $WORKSPACE_DIR/.env"
fi

IMAGE="tuapuikia/claude-code:latest"

# Check if the image exists locally, or pull it
if [[ "$(docker images -q $IMAGE 2> /dev/null)" == "" ]]; then
    echo "Image $IMAGE not found locally. Attempting to pull..."
    docker pull "$IMAGE"
fi

echo "------------------------------------------"
echo "Select operation mode for Claude Code:"
echo "1) Launch Claude CLI (Default)"
echo "2) Open Bash Shell"
echo "------------------------------------------"
read -p "Choice [1-2]: " mode_choice

case $mode_choice in
    2) COMMAND="/bin/bash" ;;
    *) COMMAND="claude" ;;
esac

echo "------------------------------------------"
echo "Launching container..."
echo "Image:     $IMAGE"
echo "Docker Mode: $DOCKER_MODE"
echo "Workspace: $WORKSPACE_DIR"
echo "Claude session: $CLAUDE_HOME"
echo "------------------------------------------"

# Determine if sudo is needed for docker socket access (only for host mode)
DOCKER_CMD="docker"
if [ ! -w /var/run/docker.sock ] && [ "$DOCKER_MODE" == "host" ]; then
    echo "Note: /var/run/docker.sock is not writable by current user. Using sudo..."
    DOCKER_CMD="sudo docker"
fi

# Run the container
mkdir -p "$CLAUDE_HOME"
$DOCKER_CMD run -it --rm \
    --init \
    --add-host=host.docker.internal:host-gateway \
    --name "claude-runner-$(date +%s)" \
    $DOCKER_MOUNT_ARG \
    $DOCKER_ENV_ARG \
    $ENV_FILE_ARG \
    -e OLLAMA_CONTEXT_LENGTH="$OLLAMA_CONTEXT_LENGTH" \
    -v "$WORKSPACE_DIR:/workspace" \
    -v "$CLAUDE_HOME:/home/ubuntu/.claude" \
    -v "$HOME/.docker:/home/ubuntu/.docker:ro" \
    --workdir /workspace \
    "$IMAGE" \
    $COMMAND

echo "------------------------------------------"
echo "Container session finished."
echo "------------------------------------------"
