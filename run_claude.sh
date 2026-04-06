#!/bin/bash

# Ensure we are executing from the directory where the script lives
cd "$(dirname "$0")"

# Default values
WORKSPACE_DIR="$(pwd)"
CLAUDE_HOME="$HOME/.claude"

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
    echo "  --workspace <path>    Specify a custom workspace directory to mount (Default: current directory)"
    echo ""
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --workspace)
            if [[ -n "$2" ]]; then
                WORKSPACE_DIR=$(readlink -f "$2")
                validate_workspace "$WORKSPACE_DIR"
                shift 2
            else
                echo "Error: --workspace requires a path."
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
echo "Socket:    /var/run/docker.sock"
echo "Workspace: $WORKSPACE_DIR"
echo "Claude session: $CLAUDE_HOME"
echo "------------------------------------------"

# Determine if sudo is needed for docker socket access
DOCKER_CMD="docker"
if [ ! -w /var/run/docker.sock ]; then
    echo "Note: /var/run/docker.sock is not writable by current user. Using sudo..."
    DOCKER_CMD="sudo docker"
fi

# Run the container
# --rm: Automatically remove the container when it exits
# -it: Interactive terminal
# -v /var/run/docker.sock: Allow Claude to manage other containers
# -v "$WORKSPACE_DIR":/workspace: Mount custom directory to the container's workspace (RW)
# -v "$CLAUDE_HOME":/home/ubuntu/.claude: Persist Claude login and session info from host home
# --workdir /workspace: Ensure we start in the mounted directory
mkdir -p "$CLAUDE_HOME"
$DOCKER_CMD run -it --rm \
    --name claude-runner \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$WORKSPACE_DIR:/workspace" \
    -v "$CLAUDE_HOME:/home/ubuntu/.claude" \
    --workdir /workspace \
    "$IMAGE" \
    $COMMAND

echo "------------------------------------------"
echo "Container session finished."
echo "------------------------------------------"
