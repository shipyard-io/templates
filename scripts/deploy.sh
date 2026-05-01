#!/bin/bash
set -euo pipefail

# Usage: bash scripts/deploy.sh <app-name> <image-tag> [health-check-path] [health-check-retries] [registry-url]

APP_NAME=$1
IMAGE_TAG=$2
HEALTH_CHECK_PATH=${3:-/}
HEALTH_CHECK_RETRIES=${4:-5}
REGISTRY_URL=$(echo "${5:-ghcr.io/shipyard-io}" | tr '[:upper:]' '[:lower:]')

APP_DIR="/apps/$APP_NAME"

if [ -z "$APP_NAME" ]; then
  echo "Missing required argument: app-name"
  exit 1
fi

if [ -z "$IMAGE_TAG" ]; then
  echo "Missing required argument: image-tag"
  exit 1
fi

case "$APP_NAME" in
  *[!a-zA-Z0-9._-]*)
    echo "Invalid app-name: $APP_NAME. Allowed chars: a-z A-Z 0-9 . _ -"
    exit 1
    ;;
esac

if ! [[ "$HEALTH_CHECK_RETRIES" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid health-check-retries: $HEALTH_CHECK_RETRIES. Must be a positive integer."
  exit 1
fi

if [ -z "$HEALTH_CHECK_PATH" ]; then
  echo "health-check-path cannot be empty"
  exit 1
fi

if [ ! -d "$APP_DIR" ]; then
  echo "Directory $APP_DIR does not exist. Please ensure docker-compose.yml and .env are uploaded first."
  exit 1
fi

cd "$APP_DIR"

if [ ! -f docker-compose.yml ]; then
  echo "docker-compose.yml not found in $APP_DIR"
  exit 1
fi

CURRENT_TAG=$(cat .current-tag 2>/dev/null || echo "latest")
echo "$CURRENT_TAG" > .previous-tag
echo "$IMAGE_TAG" > .current-tag

# Inject variables into .env
sed -i '/^IMAGE_TAG=/d' .env 2>/dev/null || true
echo "IMAGE_TAG=$IMAGE_TAG" >> .env

sed -i '/^APP_NAME=/d' .env 2>/dev/null || true
echo "APP_NAME=$APP_NAME" >> .env

sed -i '/^DOCKER_IMAGE=/d' .env 2>/dev/null || true
echo "DOCKER_IMAGE=${REGISTRY_URL}/${APP_NAME}" >> .env

echo "Pulling image..."
docker compose pull
echo "Starting container..."
docker compose up -d --remove-orphans

echo "Container started with image tag: $IMAGE_TAG"

APP_PORT=$(grep '^APP_PORT=' .env | tail -1 | cut -d= -f2 || true)
if [ -z "$APP_PORT" ]; then
  echo "APP_PORT not found in .env. Skipping local health check."
else
  echo "Running health check on port=$APP_PORT, path=$HEALTH_CHECK_PATH."
  PASSED=false
  for i in $(seq 1 "$HEALTH_CHECK_RETRIES"); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${APP_PORT}${HEALTH_CHECK_PATH}" || echo '000')
    if [ "$STATUS" = "200" ]; then
      echo "Health check passed."
      PASSED=true
      break
    fi
    echo "Health check returned HTTP $STATUS. Retrying in 10 seconds ($i/$HEALTH_CHECK_RETRIES)..."
    sleep 10
  done

  if [ "$PASSED" = "false" ]; then
    echo "Health check failed after $HEALTH_CHECK_RETRIES attempts. Rolling back..."
    curl -sSL https://raw.githubusercontent.com/shipyard-io/templates/main/scripts/rollback.sh | bash -s -- "$APP_NAME"
    exit 1
  fi
fi

echo "Deployment of $APP_NAME successful."
