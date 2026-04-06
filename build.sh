#!/bin/bash

# Exit on error
set -e

# Repository name
REPO="ollama/ollama"
# Final image name we want to create
DEST_IMAGE="tuapuikia/ollama:claude"

echo "Fetching latest tag for $REPO from Docker Hub..."

# Fetch tags from Docker Hub API (v2)
# We filter for tags that:
# 1. Are not "latest"
# 2. Do not contain "rocm"
# 3. Do not contain "alpine"
# 4. Match a version-like pattern (start with a digit)
LATEST_TAG=$(curl -s "https://hub.docker.com/v2/repositories/$REPO/tags/?page_size=100" | \
    jq -r '.results[].name' | \
    grep -vE 'latest|rocm|alpine|rc' | \
    grep '^[0-9]' | \
    head -n 1)

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Could not find a suitable tag."
    exit 1
fi

echo "Found latest version: $LATEST_TAG"
VERSION_TAG="tuapuikia/ollama:claude-$LATEST_TAG"
LATEST_FLAVOR_TAG="tuapuikia/ollama:claude"

# Update Dockerfile to match the latest tag (ensures consistency)
sed -i "s/^ARG OLLAMA_TAG=.*/ARG OLLAMA_TAG=$LATEST_TAG/" Dockerfile

# Update .env file for docker-compose to use the specific versioned tag
echo "Updating .env with OLLAMA_IMAGE_TAG=$VERSION_TAG..."
echo "OLLAMA_IMAGE_TAG=$VERSION_TAG" > .env

# Build and push the image using buildx with both tags
echo "------------------------------------------"
echo "Building and pushing $VERSION_TAG and $LATEST_FLAVOR_TAG..."
echo "------------------------------------------"

# Use sudo if required by your environment
if groups | grep -q "\bdocker\b"; then
    docker buildx build --push --build-arg OLLAMA_TAG="$LATEST_TAG" \
        -t "$VERSION_TAG" \
        -t "$LATEST_FLAVOR_TAG" \
        -f Dockerfile .
else
    sudo docker buildx build --push --build-arg OLLAMA_TAG="$LATEST_TAG" \
        -t "$VERSION_TAG" \
        -t "$LATEST_FLAVOR_TAG" \
        -f Dockerfile .
fi


echo "------------------------------------------"
echo "Build complete: $DEST_IMAGE (based on $REPO:$LATEST_TAG)"
echo "------------------------------------------"

# Build and push the Claude-only image
CLAUDE_DEST_IMAGE="tuapuikia/claude-code:latest"
echo "------------------------------------------"
echo "Building and pushing $CLAUDE_DEST_IMAGE..."
echo "------------------------------------------"

if groups | grep -q "\bdocker\b"; then
    docker buildx build --push \
        -t "$CLAUDE_DEST_IMAGE" \
        -f Dockerfile-claude .
else
    sudo docker buildx build --push \
        -t "$CLAUDE_DEST_IMAGE" \
        -f Dockerfile-claude .
fi

echo "------------------------------------------"
echo "Claude Code Build complete: $CLAUDE_DEST_IMAGE"
echo "------------------------------------------"
