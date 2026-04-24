#!/bin/bash
set -e

# Usage: bash scripts/rollback.sh <app-name> [target-tag]

APP_NAME=$1
TARGET_TAG=$2

APP_DIR="/apps/$APP_NAME"

cd "$APP_DIR"

if [ -z "$TARGET_TAG" ]; then
  TARGET_TAG=$(cat .previous-tag 2>/dev/null || echo "")
fi

if [ -z "$TARGET_TAG" ]; then
  echo "No previous tag found to rollback to."
  exit 1
fi

echo "Rolling back $APP_NAME to tag: $TARGET_TAG"

echo "$TARGET_TAG" > .current-tag
sed -i '/^IMAGE_TAG=/d' .env 2>/dev/null || true
echo "IMAGE_TAG=$TARGET_TAG" >> .env

docker compose pull
docker compose up -d --remove-orphans

echo "Rollback to $TARGET_TAG completed."
