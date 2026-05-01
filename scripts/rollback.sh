#!/bin/bash
set -euo pipefail

# Usage: bash scripts/rollback.sh <app-name> [target-tag]

APP_NAME=$1
TARGET_TAG=$2

APP_DIR="/apps/$APP_NAME"

if [ -z "$APP_NAME" ]; then
  echo "Missing required argument: app-name"
  exit 1
fi

case "$APP_NAME" in
  *[!a-zA-Z0-9._-]*)
    echo "Invalid app-name: $APP_NAME. Allowed chars: a-z A-Z 0-9 . _ -"
    exit 1
    ;;
esac

if [ -n "${TARGET_TAG:-}" ] && ! [[ "$TARGET_TAG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Invalid target-tag: $TARGET_TAG. Allowed chars: a-z A-Z 0-9 . _ -"
  exit 1
fi

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
