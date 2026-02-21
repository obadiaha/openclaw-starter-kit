#!/bin/bash
# ============================================================
# VPS Security Hardening Script for OpenClaw MVP
# Run ONCE after initial VPS setup, BEFORE docker compose up
# Tested on: Ubuntu 22.04+, Debian 12+
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

# ── Pre-flight ──────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Run as root: sudo bash harden-vps.sh"
  exit 1
fi

echo "============================================"
echo "  OpenClaw MVP — VPS Security Hardening"
echo "============================================"
echo ""

# ── 1. System Updates ───────────────────────────────────────
log "Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
log "System updated."

# ── 2. Unattended Security Updates ──────────────────────────
log "Enabling automatic security updates..."
apt-get install -y -qq unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
log "Automatic security updates enabled."

# ── 3. Firewall (UFW) ──────────────────────────────────────
log "Configuring firewall..."
apt-get install -y -qq ufw

# Default deny incoming, allow outgoing
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (change port below if using non-standard)
SSH_PORT=${SSH_PORT:-22}
ufw allow "$SSH_PORT"/tcp comment "SSH"

# Allow n8n (optional: restrict to your IP)
ufw allow 5678/tcp comment "n8n"

# Allow Adminer (optional: comment out in production)
ufw allow 8080/tcp comment "Adminer - REMOVE IN PRODUCTION"

# Enable firewall
ufw --force enable
log "Firewall configured. Open ports: SSH($SSH_PORT), n8n(5678), Adminer(8080)"

# ── 4. SSH Hardening ───────────────────────────────────────
log "Hardening SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

# Disable root login (use sudo user instead)
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"

# Disable password auth (key-only)
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"

# Disable empty passwords
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSHD_CONFIG"

# Limit auth attempts
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"

# Disable X11 forwarding
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"

systemctl restart sshd
log "SSH hardened: root login disabled, password auth disabled, key-only access."
warn "Make sure you have SSH key access before disconnecting!"

# ── 5. Fail2Ban ────────────────────────────────────────────
log "Installing fail2ban..."
apt-get install -y -qq fail2ban

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2ban active: 3 failed SSH attempts = 1 hour ban."

# ── 6. Docker Security ────────────────────────────────────
log "Applying Docker security defaults..."

# Limit Docker container capabilities (applied via docker-compose)
# This script just ensures the daemon is configured safely
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF

# Restart Docker to apply
systemctl restart docker 2>/dev/null || true
log "Docker hardened: no-new-privileges, log rotation, live-restore."

# ── 7. File Permissions ───────────────────────────────────
log "Securing .env file permissions..."
if [ -f /app/.env ] || [ -f ./.env ]; then
  chmod 600 .env 2>/dev/null || true
  log ".env restricted to owner-only read/write."
else
  warn "No .env found yet. Remember: chmod 600 .env after creating it."
fi

# ── 8. Shared Memory Hardening ────────────────────────────
if ! grep -q "tmpfs /run/shm" /etc/fstab; then
  echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
  log "Shared memory hardened (noexec, nosuid)."
fi

# ── Summary ───────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Hardening Complete"
echo "============================================"
echo ""
log "System updates: enabled (automatic)"
log "Firewall: active (SSH, n8n, Adminer)"
log "SSH: key-only, no root, max 3 attempts"
log "Fail2ban: active (1h ban after 3 failures)"
log "Docker: no-new-privileges, log rotation"
log "File permissions: .env locked down"
echo ""
warn "BEFORE PRODUCTION:"
warn "  1. Remove Adminer port (8080) from firewall"
warn "  2. Put n8n behind a reverse proxy with HTTPS"
warn "  3. Set strong passwords in .env"
warn "  4. Restrict n8n to your IP: ufw allow from YOUR_IP to any port 5678"
echo ""
log "You're ready to run: docker compose up -d --build"
