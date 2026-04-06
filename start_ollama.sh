#!/bin/bash

# Ensure we are executing from the directory where the script and docker-compose.yml live
cd "$(dirname "$0")"

echo "------------------------------------------"
echo "Select a model family to pre-load:"
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

if [ -z "$FETCHED_TAGS" ]; then
    echo "Warning: Failed to fetch tags. Using fallback list."
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
    mapfile -t MODELS <<< "$FETCHED_TAGS"
fi

echo ""
echo "Select the specific version/tag for $FAMILY:"
echo "------------------------------------------"
for i in "${!MODELS[@]}"; do echo "$((i+1))) ${MODELS[$i]}"; done
read -p "Choice [1-${#MODELS[@]}] (Press Enter for 'latest'): " model_choice

if [ -z "$model_choice" ]; then
    SELECTED_TAG="latest"
else
    if [[ "$model_choice" =~ ^[0-9]+$ ]] && [ "$model_choice" -ge 1 ] && [ "$model_choice" -le "${#MODELS[@]}" ]; then
        SELECTED_TAG=${MODELS[$((model_choice-1))]}
    else
        SELECTED_TAG="latest"
    fi
fi

CLEAN_TAG=$(echo "$SELECTED_TAG" | awk '{print $1}')
FULL_MODEL_NAME="$FAMILY:$CLEAN_TAG"

# Ensure the .env file exists and has the image tag
if [ ! -f .env ] || ! grep -q "OLLAMA_IMAGE_TAG" .env; then
    # Fallback to the default if not set by build.sh
    DEFAULT_TAG=$(grep "ARG OLLAMA_TAG=" Dockerfile | cut -d'=' -f2)
    echo "OLLAMA_IMAGE_TAG=tuapuikia/ollama:claude-$DEFAULT_TAG" > .env
fi

echo "------------------------------------------"
echo "Starting Ollama container in the background..."
# Pre-create data directory to ensure it's not owned by root
mkdir -p ./ollama_data
docker compose up -d

echo "Waiting for Ollama server to initialize..."
READY=0
for i in {1..20}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:11434/api/tags | grep -q "200"; then
        READY=1
        break
    fi
    sleep 1
done

if [ $READY -eq 1 ]; then
    echo "Pulling $FULL_MODEL_NAME..."
    # We use 'pull' here so the server is ready for the interactive run later
    docker exec -u ubuntu ollama ollama pull "$FULL_MODEL_NAME"
    echo "------------------------------------------"
    echo "Ollama is ready and $FULL_MODEL_NAME is loaded."
    echo "Run ./run_model.sh to enter the shell."
else
    echo "Ollama container started, but API is taking longer than expected to initialize."
fi
