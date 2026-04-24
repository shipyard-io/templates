#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}===> $1${NC}"; }

section "Check dependencies"
command -v docker &>/dev/null || error "Docker is not installed."
docker network inspect proxy &>/dev/null || error "Docker network 'proxy' not found."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TRAEFIK_DIR="$REPO_ROOT/infrastructure/traefik"
CERTS_DIR="$TRAEFIK_DIR/certs"

section "Check certificates"
mkdir -p "$CERTS_DIR"

if [ -n "${CLOUDFLARE_ORIGIN_CERT:-}" ] || [ -n "${CLOUDFLARE_ORIGIN_KEY:-}" ]; then
  if [ -z "${CLOUDFLARE_ORIGIN_CERT:-}" ] || [ -z "${CLOUDFLARE_ORIGIN_KEY:-}" ]; then
    error "Missing CLOUDFLARE_ORIGIN_CERT or CLOUDFLARE_ORIGIN_KEY."
  fi
  printf '%s\n' "$CLOUDFLARE_ORIGIN_CERT" > "$CERTS_DIR/origin.pem"
  printf '%s\n' "$CLOUDFLARE_ORIGIN_KEY" > "$CERTS_DIR/origin.key"
  chmod 600 "$CERTS_DIR/origin.key"
  chmod 644 "$CERTS_DIR/origin.pem"
  log "Cloudflare certificates injected."
fi

if [ ! -f "$CERTS_DIR/origin.pem" ] || [ ! -f "$CERTS_DIR/origin.key" ]; then
  error "Cloudflare Origin Certificate is missing."
fi

section "Start Traefik"
cd "$TRAEFIK_DIR"
if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

[ -n "${DOMAIN:-}" ] || error "DOMAIN is required."
[ -n "${TRAEFIK_DASHBOARD_AUTH:-}" ] || error "TRAEFIK_DASHBOARD_AUTH is required."
[ -f docker-compose.yml ] || error "docker-compose.yml not found."

if docker compose ps --services --filter status=running 2>/dev/null | grep -qx "traefik"; then
  docker compose down
fi

docker compose up -d
log "Traefik started."

section "Verify"
sleep 3
if docker ps --filter "name=^/traefik$" --format '{{.Names}}' | grep -qx "traefik"; then
  log "Traefik container is running."
else
  error "Traefik container is not running."
fi

STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ping || echo "000")
if [ "$STATUS" = "200" ]; then
  log "Traefik ping healthy (HTTP $STATUS)."
else
  warn "Traefik ping returned HTTP $STATUS."
fi

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Traefik setup completed${NC}"
echo -e "${GREEN}============================================${NC}\n"
