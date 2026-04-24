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

if [ "$EUID" -ne 0 ]; then
  error "Run this script as root: sudo bash setup-vps.sh"
fi

DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
APPS_DIR="${APPS_DIR:-/apps}"
SSH_PORT="${SSH_PORT:-$(sshd -T 2>/dev/null | awk '/^port / { print $2; exit }')}"
SSH_PORT="${SSH_PORT:-22}"
APP_OWNER="$DEPLOY_USER"

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
  error "SSH_PORT must be numeric. Current value: $SSH_PORT"
fi

if id "$DEPLOY_USER" &>/dev/null; then
  APP_OWNER="$DEPLOY_USER"
else
  APP_OWNER="root"
fi

section "Update system packages"
apt-get update -qq >/dev/null 2>&1
apt-get upgrade -y -qq >/dev/null 2>&1
apt-get install -y -qq curl wget git unzip htop ncdu ufw fail2ban logrotate >/dev/null 2>&1
log "System packages updated."

section "Install Docker"
if command -v docker &>/dev/null; then
  warn "Docker already installed: $(docker --version)"
else
  curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
  systemctl enable docker >/dev/null 2>&1
  systemctl start docker >/dev/null 2>&1
  log "Docker installed: $(docker --version)"
fi

if id "$DEPLOY_USER" &>/dev/null; then
  usermod -aG docker "$DEPLOY_USER"
fi

section "Create application directory"
mkdir -p "$APPS_DIR"
chown "$APP_OWNER:$APP_OWNER" "$APPS_DIR"
log "Directory $APPS_DIR is ready."

section "Configure swap ($SWAP_SIZE)"
if swapon --show | grep -q '/swapfile'; then
  warn "Swap already exists."
else
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null 2>&1
  swapon /swapfile >/dev/null 2>&1
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
  log "Swap $SWAP_SIZE configured."
fi

section "Configure UFW firewall"
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1
log "UFW enabled. SSH port: $SSH_PORT."

section "Configure Fail2ban"
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1
log "Fail2ban enabled."

section "Configure Docker logrotate"
cat > /etc/logrotate.d/docker << 'EOF'
/var/lib/docker/containers/*/*.log {
  rotate 7
  daily
  compress
  missingok
  delaycompress
  copytruncate
}
EOF
log "Logrotate configured."

section "Configure Docker daemon"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker >/dev/null 2>&1
log "Docker daemon configured."

section "Create Docker networks"
if docker network inspect proxy &>/dev/null; then
  warn "Network 'proxy' already exists."
else
  docker network create proxy >/dev/null 2>&1
  log "Network 'proxy' created."
fi

if docker network inspect monitoring &>/dev/null; then
  warn "Network 'monitoring' already exists."
else
  docker network create monitoring >/dev/null 2>&1
  log "Network 'monitoring' created."
fi

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  VPS setup completed${NC}"
echo -e "${GREEN}============================================${NC}\n"
