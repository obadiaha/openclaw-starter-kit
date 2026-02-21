#!/bin/bash
# ============================================================
# OpenClaw VPS Installer
# Sets up OpenClaw on a fresh Ubuntu/Debian VPS from scratch.
# Usage: curl -fsSL https://raw.githubusercontent.com/obadiaha/openclaw-starter-kit/main/scripts/install-openclaw.sh | sudo bash
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# ── Pre-flight ──────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Run as root: sudo bash install-openclaw.sh"
  exit 1
fi

echo ""
echo "============================================"
echo "  OpenClaw VPS Installer"
echo "  by Go Digital (godigitalapps.com)"
echo "============================================"
echo ""

# ── Config ──────────────────────────────────────────────────
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
WORKSPACE="/home/$OPENCLAW_USER/workspace"
STARTER_KIT_REPO="https://github.com/obadiaha/openclaw-starter-kit.git"
NODE_MAJOR=22

# ── 1. System Updates ──────────────────────────────────────
log "Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
log "System updated."

# ── 2. Install Node.js ─────────────────────────────────────
if command -v node &>/dev/null && [ "$(node -v | cut -d. -f1 | tr -d v)" -ge "$NODE_MAJOR" ]; then
  log "Node.js $(node -v) already installed."
else
  log "Installing Node.js $NODE_MAJOR..."
  apt-get install -y -qq ca-certificates curl gnupg
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq && apt-get install -y -qq nodejs
  log "Node.js $(node -v) installed."
fi

# ── 3. Install OpenClaw ────────────────────────────────────
if command -v openclaw &>/dev/null; then
  log "OpenClaw $(openclaw --version 2>/dev/null || echo 'unknown') already installed."
else
  log "Installing OpenClaw..."
  npm install -g openclaw
  log "OpenClaw $(openclaw --version 2>/dev/null) installed."
fi

# ── 4. Create dedicated user ───────────────────────────────
if id "$OPENCLAW_USER" &>/dev/null; then
  log "User '$OPENCLAW_USER' already exists."
else
  log "Creating user '$OPENCLAW_USER'..."
  useradd -m -s /bin/bash "$OPENCLAW_USER"
  log "User '$OPENCLAW_USER' created."
fi

# ── 5. Set up workspace ────────────────────────────────────
log "Setting up workspace at $WORKSPACE..."
mkdir -p "$WORKSPACE"

if [ -d "$WORKSPACE/.git" ]; then
  log "Starter kit already cloned. Pulling latest..."
  cd "$WORKSPACE" && sudo -u "$OPENCLAW_USER" git pull --ff-only origin main 2>/dev/null || true
else
  log "Cloning starter kit..."
  sudo -u "$OPENCLAW_USER" git clone "$STARTER_KIT_REPO" "$WORKSPACE"
fi

# Create memory subdirectories
mkdir -p "$WORKSPACE/memory/archive"
chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$WORKSPACE"
log "Workspace ready."

# ── 6. Create .env file ────────────────────────────────────
ENV_FILE="$WORKSPACE/.env"
if [ -f "$ENV_FILE" ]; then
  warn ".env already exists. Skipping creation."
else
  log "Creating .env file..."
  cat > "$ENV_FILE" << 'ENVEOF'
# OpenClaw Environment Variables
# Fill in your API keys below, then restart the service.

# AI Provider (at least one required)
ANTHROPIC_API_KEY=
# OPENROUTER_API_KEY=
# OPENAI_API_KEY=
# GOOGLE_GENERATIVE_AI_API_KEY=

# Telegram Bot (recommended)
# TELEGRAM_BOT_TOKEN=

# Web Search (optional, free tier: 2000 queries/month)
# BRAVE_API_KEY=
ENVEOF
  chmod 600 "$ENV_FILE"
  chown "$OPENCLAW_USER:$OPENCLAW_USER" "$ENV_FILE"
  log ".env created at $ENV_FILE (fill in your API keys)."
fi

# ── 7. Initialize OpenClaw config ──────────────────────────
OPENCLAW_DIR="/home/$OPENCLAW_USER/.openclaw"
mkdir -p "$OPENCLAW_DIR"
chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_DIR"

CONFIG_FILE="$OPENCLAW_DIR/clawdbot.json"
if [ -f "$CONFIG_FILE" ]; then
  warn "OpenClaw config already exists. Skipping."
else
  log "Creating OpenClaw config..."
  cat > "$CONFIG_FILE" << CFGEOF
{
  "workspace": "$WORKSPACE",
  "envFile": "$WORKSPACE/.env",
  "security": {
    "elevated": false,
    "exec": "allowlist"
  }
}
CFGEOF
  chown "$OPENCLAW_USER:$OPENCLAW_USER" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log "Config created at $CONFIG_FILE"
fi

# ── 8. Create systemd service ──────────────────────────────
SERVICE_FILE="/etc/systemd/system/openclaw.service"
log "Creating systemd service..."
cat > "$SERVICE_FILE" << SVCEOF
[Unit]
Description=OpenClaw AI Agent Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$OPENCLAW_USER
Group=$OPENCLAW_USER
WorkingDirectory=$WORKSPACE
ExecStart=$(which openclaw) gateway start --foreground
Restart=always
RestartSec=10
Environment=HOME=/home/$OPENCLAW_USER
EnvironmentFile=$ENV_FILE

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$WORKSPACE $OPENCLAW_DIR /tmp

# Resource limits
LimitNOFILE=65536
MemoryMax=1G

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable openclaw
log "Systemd service created and enabled (auto-start on boot)."

# ── 9. Run VPS hardening ───────────────────────────────────
HARDEN_SCRIPT="$WORKSPACE/scripts/harden-vps.sh"
if [ -f "$HARDEN_SCRIPT" ]; then
  echo ""
  info "VPS hardening script found."
  read -p "  Run security hardening now? (y/n): " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$HARDEN_SCRIPT"
  else
    warn "Skipped hardening. Run later with: sudo bash $HARDEN_SCRIPT"
  fi
else
  warn "Hardening script not found. Run manually if needed."
fi

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Installation Complete"
echo "============================================"
echo ""
log "OpenClaw installed: $(openclaw --version 2>/dev/null)"
log "User: $OPENCLAW_USER"
log "Workspace: $WORKSPACE"
log "Config: $CONFIG_FILE"
log "Service: openclaw.service"
echo ""
warn "NEXT STEPS:"
echo ""
echo "  1. Add your API keys:"
echo "     sudo -u $OPENCLAW_USER nano $ENV_FILE"
echo ""
echo "  2. Start OpenClaw:"
echo "     sudo systemctl start openclaw"
echo ""
echo "  3. Check status:"
echo "     sudo systemctl status openclaw"
echo "     sudo journalctl -u openclaw -f"
echo ""
echo "  4. Connect Telegram (if configured):"
echo "     Message your bot. The agent will run BOOTSTRAP.md"
echo "     and introduce itself on first contact."
echo ""
info "Logs: journalctl -u openclaw -f"
info "Stop: sudo systemctl stop openclaw"
info "Restart: sudo systemctl restart openclaw"
echo ""
