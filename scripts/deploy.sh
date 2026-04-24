#!/bin/bash
set -e

# Usage: bash scripts/deploy.sh <app-name> <image-tag> [health-check-path] [health-check-retries]

APP_NAME=$1
IMAGE_TAG=$2
HEALTH_CHECK_PATH=${3:-/}
HEALTH_CHECK_RETRIES=${4:-5}

APP_DIR="/apps/$APP_NAME"

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
    bash ~/shipyard/scripts/rollback.sh "$APP_NAME"
    exit 1
  fi
fi

echo "Deployment of $APP_NAME successful."
