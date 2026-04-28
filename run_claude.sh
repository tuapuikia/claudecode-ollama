#!/bin/bash

# Default values
ORIGINAL_PWD="$(pwd)"
WORKSPACE_DIR="$ORIGINAL_PWD"
DOCKER_MODE="proxy" # proxy (default), host, none
CLAUDE_HOME="$HOME/.claude"
CLAUDE_CONFIG="$HOME/.claude.json"
OLLAMA_CONTEXT_LENGTH="64000"
CUSTOM_ENV_FILE=""
HOST_MAP=false

# Ensure we are executing from the directory where the script lives
cd "$(dirname "$0")"

# Function to validate the workspace path (Fix VULN-004)
validate_workspace() {
    local path=$(readlink -f "$1")
    # Ensure the path exists and is a directory
    if [ ! -d "$path" ]; then
        echo "Error: Workspace path '$path' does not exist or is not a directory."
        exit 1
    fi

    # Sensitive system directories that should never be mounted
    local sensitive_dirs=(
        "/" "/etc" "/root" "/boot" "/sys" "/proc" "/dev" "/bin" "/sbin" "/lib" "/lib64" "/usr" "/var"
    )

    for dir in "${sensitive_dirs[@]}"; do
        if [[ "$path" == "$dir" ]] || [[ "$path" == "$dir/"* ]]; then
            echo "Security Error: Mounting sensitive system directory '$path' as workspace is not allowed."
            exit 1
        fi
    done

    # Block user-sensitive directories
    if [[ "$path" == "$HOME" ]] || [[ "$path" == "$HOME/.ssh"* ]] || [[ "$path" == "$HOME/.aws"* ]] || [[ "$path" == "$HOME/.gnupg"* ]] || [[ "$path" == "$HOME/.claude"* ]]; then
        echo "Security Error: Mounting user sensitive directory '$path' as workspace is not allowed."
        exit 1
    fi
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
    echo "  --env-file <path>     Specify a custom .env file to use"
    echo "  --context-length <n>  Set the Ollama context length (Default: 64000)"
    echo "  --hostmap             Mount host /etc/hosts to container /etc/hosts (read-only)"
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
        --env-file)
            if [[ -n "$2" ]]; then
                # Resolve to absolute path
                CUSTOM_ENV_FILE=$(readlink -f "$2")
                shift 2
            else
                echo "Error: --env-file requires a path."
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
        --hostmap)
            HOST_MAP=true
            shift
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

# Check for .env file
ENV_FILE_ARGS=()
ACTIVE_ENV_FILE=""
if [[ -n "$CUSTOM_ENV_FILE" ]]; then
    if [ -f "$CUSTOM_ENV_FILE" ]; then
        ACTIVE_ENV_FILE="$CUSTOM_ENV_FILE"
    else
        echo "Error: Specified .env file '$CUSTOM_ENV_FILE' not found."
        exit 1
    fi
elif [ -f "$ORIGINAL_PWD/.env" ]; then
    ACTIVE_ENV_FILE="$ORIGINAL_PWD/.env"
elif [ -f "$WORKSPACE_DIR/.env" ]; then
    ACTIVE_ENV_FILE="$WORKSPACE_DIR/.env"
fi

if [[ -n "$ACTIVE_ENV_FILE" ]]; then
    echo "Info: Using .env file: $ACTIVE_ENV_FILE"
    ENV_FILE_ARGS=("--env-file" "$ACTIVE_ENV_FILE")
fi

IMAGE="tuapuikia/claude-code:latest"

# Always check for the latest image before running
echo "Checking for latest image: $IMAGE..."
docker pull "$IMAGE"

echo "------------------------------------------"
echo "Select operation mode for Claude Code:"
echo "1) Launch Claude CLI (Default)"
echo "2) Open Bash Shell"
echo "------------------------------------------"
read -p "Choice [1-2]: " mode_choice

# Detect System Prompt File
SYSTEM_PROMPT_FILE_PATH=""
# Check ~/.claude/system.md first as a default if it exists
if [ -f "$HOME/.claude/system.md" ]; then
    SYSTEM_PROMPT_FILE_PATH="/home/ubuntu/.claude/system.md"
fi

# Override from .env file if present
if [[ -n "$ACTIVE_ENV_FILE" ]]; then
    # Try to extract SYSTEM_PROMPT_FILE from the .env file (case-insensitive)
    # Sanitize the input to allow only safe path characters (Fix VULN-002)
    ENV_SYSTEM_PROMPT=$(grep -i "^SYSTEM_PROMPT_FILE=" "$ACTIVE_ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | sed 's/[^a-zA-Z0-9._/ ~-]//g')
    if [[ -n "$ENV_SYSTEM_PROMPT" ]]; then
        SYSTEM_PROMPT_FILE_PATH="$ENV_SYSTEM_PROMPT"
    fi
fi

# Build command as an array to prevent shell injection and handle spaces (Fix VULN-002)
case $mode_choice in
    2) COMMAND=("/bin/bash") ;;
    *) 
        COMMAND=("claude") 
        if [[ -n "$SYSTEM_PROMPT_FILE_PATH" ]]; then
            echo "Info: Using system prompt file: $SYSTEM_PROMPT_FILE_PATH"
            COMMAND=("claude" "--system-prompt-file" "$SYSTEM_PROMPT_FILE_PATH")
        fi
        ;;
esac

echo "------------------------------------------"
echo "Launching container..."
echo "Image:     $IMAGE"
echo "Docker Mode: $DOCKER_MODE"
echo "Workspace: $WORKSPACE_DIR"
echo "Claude session: $CLAUDE_HOME"
echo "Claude config: $CLAUDE_CONFIG"
echo "Host Map:  $HOST_MAP"
echo "------------------------------------------"

# Determine if sudo is needed for docker socket access (only for host mode)
DOCKER_CMD="docker"
if [ ! -w /var/run/docker.sock ] && [ "$DOCKER_MODE" == "host" ]; then
    echo "Note: /var/run/docker.sock is not writable by current user. Using sudo..."
    DOCKER_CMD="sudo docker"
fi

# Prepare hostmap mount if requested
HOSTMAP_MOUNT_ARG=""
if [ "$HOST_MAP" = true ]; then
    if [ -f "/etc/hosts" ]; then
        HOSTMAP_MOUNT_ARG="-v /etc/hosts:/etc/hosts:ro"
    else
        echo "Warning: /etc/hosts not found on host. Skipping hostmap."
    fi
fi

# Run the container
mkdir -p "$CLAUDE_HOME"
[ ! -f "$CLAUDE_CONFIG" ] && touch "$CLAUDE_CONFIG"
$DOCKER_CMD run -it --rm \
    --init \
    --add-host=host.docker.internal:host-gateway \
    --name "claude-runner-$(date +%s)" \
    $DOCKER_MOUNT_ARG \
    $DOCKER_ENV_ARG \
    $HOSTMAP_MOUNT_ARG \
    "${ENV_FILE_ARGS[@]}" \
    -e OLLAMA_CONTEXT_LENGTH="$OLLAMA_CONTEXT_LENGTH" \
    -v "$WORKSPACE_DIR:/workspace" \
    -v "$CLAUDE_HOME:/home/ubuntu/.claude" \
    -v "$CLAUDE_CONFIG:/home/ubuntu/.claude.json:rw" \
    -v "$HOME/.docker:/home/ubuntu/.docker:ro" \
    --workdir /workspace \
    "$IMAGE" \
    "${COMMAND[@]}"

echo "------------------------------------------"
echo "Container session finished."
echo "------------------------------------------"
