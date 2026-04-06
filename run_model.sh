#!/bin/bash

# Ensure we are executing from the directory where the script lives
cd "$(dirname "$0")"

# Check if the container is running
if ! docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
    echo "Error: The 'ollama' container is not running."
    echo "Please run ./start_ollama.sh first."
    exit 1
fi

echo "------------------------------------------"
echo "Select operation mode:"
echo "1) Ollama Shell (Run model directly)"
echo "2) Claude Code   (Ollama launch claude)"
echo "------------------------------------------"
read -p "Choice [1-2]: " mode_choice

if [ "$mode_choice" == "2" ]; then
    echo "------------------------------------------"
    echo "Launching Claude Code with qwen3.5:latest..."
    # Ensure the model is pulled first to avoid timeout issues in Claude Code
    docker exec -it -u ubuntu ollama ollama pull qwen3.5:latest
    docker exec -it -u ubuntu ollama ollama launch claude --model qwen3.5:latest
    exit 0
fi

echo "------------------------------------------"
echo "Select a model family to run:"
echo "1) gemma   (Standard lightweight models)"
echo "2) gemma2  (Newer high-performing models)"
echo "3) gemma4  (Latest models)"
echo "4) qwen3.5 (Qwen 3.5 models)"
echo "------------------------------------------"
read -p "Choice [1-4]: " family_choice

case $family_choice in
    1) FAMILY="gemma" ;;
    2) FAMILY="gemma2" ;;
    3) FAMILY="gemma4" ;;
    4) FAMILY="qwen3.5" ;;
    *) 
        echo "Invalid choice. Defaulting to gemma4."
        FAMILY="gemma4"
        ;;
esac

echo ""
echo "Fetching latest tags and sizes for $FAMILY from Ollama library..."
FETCHED_TAGS=$(curl -s "https://ollama.com/library/$FAMILY/tags" | awk -F'"' '/href="\/library\/'"$FAMILY"':/ {
    split($2, parts, ":");
    tag=parts[2];
}
/class="col-span-2 text-neutral-500 text-\[13px\]">/ {
    if (tag != "") {
        size=$0;
        gsub(/<[^>]*>/, "", size);
        gsub(/^[ \t]+|[ \t]+$/, "", size);
        if (size ~ /GB|MB|KB|B|-/) {
            print tag " (" size ")";
            tag="";
        }
    }
}' | uniq)

# If the fetch fails or returns empty, fall back to a default list
if [ -z "$FETCHED_TAGS" ]; then
    echo "Warning: Failed to fetch tags from Ollama website. Using fallback list."
    if [ "$FAMILY" == "gemma4" ]; then
        MODELS=("latest (9.6GB)" "e2b (7.2GB)" "e4b (9.6GB)" "26b (18GB)" "31b (20GB)" "e2b-it-q4_K_M (7.2GB)" "e4b-it-q4_K_M (9.6GB)" "26b-a4b-it-q4_K_M (18GB)" "31b-it-q4_K_M (20GB)" "31b-cloud (-)")
    elif [ "$FAMILY" == "gemma2" ]; then
        MODELS=("latest (5.4GB)" "2b (1.6GB)" "9b (5.4GB)" "27b (16GB)" "instruct (5.4GB)" "2b-instruct (1.6GB)" "9b-instruct (5.4GB)" "27b-instruct (16GB)")
    elif [ "$FAMILY" == "qwen3.5" ]; then
        MODELS=("latest (6.6GB)" "0.8b (1.0GB)" "2b (2.7GB)" "4b (3.4GB)" "9b (6.6GB)" "27b (17GB)" "35b (24GB)" "122b (81GB)")
    else
        MODELS=("latest (5.0GB)" "2b (1.7GB)" "7b (5.0GB)" "instruct (5.0GB)" "2b-instruct (1.7GB)" "7b-instruct (5.0GB)")
    fi
else
    # Convert newline-separated string into a bash array
    mapfile -t MODELS <<< "$FETCHED_TAGS"
fi

echo ""
echo "Select the specific version/tag for $FAMILY:"
echo "------------------------------------------"

# List all options with numbers
for i in "${!MODELS[@]}"; do
    echo "$((i+1))) ${MODELS[$i]}"
done

# Read user input directly instead of using 'select' so we can capture an empty enter press
read -p "Choice [1-${#MODELS[@]}] (Press Enter for 'latest'): " model_choice

# If the user just pressed Enter, default to 'latest'
if [ -z "$model_choice" ]; then
    echo "No choice entered. Defaulting to 'latest'."
    SELECTED_TAG="latest"
else
    # Validate the choice is a number and within range
    if [[ "$model_choice" =~ ^[0-9]+$ ]] && [ "$model_choice" -ge 1 ] && [ "$model_choice" -le "${#MODELS[@]}" ]; then
        SELECTED_TAG=${MODELS[$((model_choice-1))]}
    else
        echo "Invalid selection. Defaulting to 'latest'."
        SELECTED_TAG="latest"
    fi
fi

# Extract just the tag name without the size for running
CLEAN_TAG=$(echo "$SELECTED_TAG" | awk '{print $1}')
FULL_MODEL_NAME="$FAMILY:$CLEAN_TAG"

echo "------------------------------------------"
echo "Entering $FULL_MODEL_NAME model shell..."
docker exec -it -u ubuntu ollama ollama run "$FULL_MODEL_NAME"

echo "Model shell exited. The Ollama container is still running in the background."
