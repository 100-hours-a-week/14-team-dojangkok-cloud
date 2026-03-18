#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# install-alloy.sh - Install Grafana Alloy on a single instance (Ubuntu ARM64)
# =============================================================================
# Uses Grafana APT repository for reliable installation.
# Config file must be uploaded to /etc/alloy/config.alloy before running.
# =============================================================================

export DEBIAN_FRONTEND=noninteractive

# Skip if Alloy is already installed and running
if command -v alloy &>/dev/null && systemctl is-active alloy &>/dev/null; then
  echo "Alloy already installed and running: $(alloy --version 2>/dev/null || echo 'unknown')"
  systemctl status alloy --no-pager
  exit 0
fi

echo "=== Installing Grafana Alloy via APT ==="

# Add Grafana GPG key
echo "Adding Grafana GPG key ..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
chmod a+r /etc/apt/keyrings/grafana.gpg

# Add Grafana APT repository
echo "Adding Grafana APT repository ..."
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list

# Install Alloy
echo "Installing alloy ..."
apt-get update -qq
apt-get install -y -qq alloy

# Docker socket access: add alloy user to docker group
if getent group docker > /dev/null 2>&1; then
  usermod -aG docker alloy
  echo "alloy user added to docker group"
fi

# Create data directory
mkdir -p /etc/alloy /var/lib/alloy

# Enable and start
systemctl daemon-reload
systemctl enable alloy
systemctl restart alloy

echo "=== Alloy installed and started ==="
alloy --version 2>/dev/null || true
systemctl status alloy --no-pager
