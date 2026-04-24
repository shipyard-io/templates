#!/bin/bash
set -e

# Usage: bash scripts/build-docker.sh <registry_url> <app_name> <image_tag> <dockerfile> <context> <is_main_branch>

REGISTRY_URL=$1
APP_NAME=$2
IMAGE_TAG=$3
DOCKERFILE=${4:-Dockerfile}
CONTEXT=${5:-.}
IS_MAIN_BRANCH=${6:-false}

IMAGE_FQN="${REGISTRY_URL}/${APP_NAME}"

TAGS="-t ${IMAGE_FQN}:${IMAGE_TAG}"
if [ "$IS_MAIN_BRANCH" = "true" ] || [ "$IS_MAIN_BRANCH" = "main" ]; then
  TAGS="$TAGS -t ${IMAGE_FQN}:latest"
  IS_MAIN_BRANCH="true"
fi

echo "Building docker image: $IMAGE_FQN"
# Convert space-separated string to array for tags
docker build -f "$DOCKERFILE" $TAGS "$CONTEXT"

echo "Pushing docker image: ${IMAGE_FQN}:${IMAGE_TAG}"
docker push "${IMAGE_FQN}:${IMAGE_TAG}"

if [ "$IS_MAIN_BRANCH" = "true" ]; then
  echo "Pushing latest tag..."
  docker push "${IMAGE_FQN}:latest"
fi
