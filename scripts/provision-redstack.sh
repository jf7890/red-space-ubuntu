#!/usr/bin/env bash
set -e

warn() {
  echo "WARN: $*" >&2
}

run_or_warn() {
  set +e
  "$@"
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    warn "command failed (rc=${rc}): $*"
  fi
  return 0
}

run_or_warn_silent() {
  set +e
  "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    warn "command failed (rc=${rc}): $*"
  fi
  return 0
}

# Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
run_or_warn_silent apt-get update -y

echo "[0/5] Ensure Universe repository"
run_or_warn_silent apt-get install -y --no-install-recommends software-properties-common
if command -v add-apt-repository >/dev/null 2>&1; then
  run_or_warn_silent add-apt-repository -y universe
  run_or_warn_silent apt-get update -y
else
  warn "add-apt-repository not available; skipping Universe enable"
fi

run_or_warn_silent apt-get upgrade -y

# Install standard utilities and Web Pentest tools
run_or_warn_silent apt-get install -y \
    curl wget vim git htop tmux unzip jq \
    python3 python3-pip python3-venv \
    sqlmap wfuzz gobuster nikto wpscan dirb

# Create a dedicated directory for the assistant
run_or_warn mkdir -p /opt/red-lab-assistant
if [ -d /tmp/capstone-userstack/red-lab-assistant ]; then
  run_or_warn cp -r /tmp/capstone-userstack/red-lab-assistant/* /opt/red-lab-assistant/
else
  warn "No assistant files found in /tmp/capstone-userstack/red-lab-assistant"
fi
run_or_warn chown -R ubuntu:ubuntu /opt/red-lab-assistant

# Setup Virtual Environment for Assistant
run_or_warn_silent su - ubuntu -c "python3 -m venv /opt/red-lab-assistant/venv"
run_or_warn_silent su - ubuntu -c "/opt/red-lab-assistant/venv/bin/pip install --upgrade pip"
if [ -f "/opt/red-lab-assistant/requirements.txt" ]; then
    run_or_warn_silent su - ubuntu -c "/opt/red-lab-assistant/venv/bin/pip install -r /opt/red-lab-assistant/requirements.txt"
fi

# Install systemd service for Assistant
if [ -f /tmp/capstone-userstack/red-lab-assistant.service ]; then
  run_or_warn cp /tmp/capstone-userstack/red-lab-assistant.service /etc/systemd/system/
else
  warn "Missing red-lab-assistant.service in /tmp/capstone-userstack"
fi
if command -v systemctl >/dev/null 2>&1; then
  run_or_warn_silent systemctl daemon-reload
  run_or_warn_silent systemctl enable red-lab-assistant.service
  run_or_warn_silent systemctl start red-lab-assistant.service
else
  warn "systemctl not available; skipping service enable/start"
fi

# Configure tmux to auto-start for ubuntu user to enable "Context-Awareness"
cat << 'EOF' >> /home/ubuntu/.bashrc || true

# Auto-start tmux session 'red_session' if not in one
if [ -z "$TMUX" ]; then
    tmux attach-session -t red_session || tmux new-session -s red_session
fi
EOF
run_or_warn chown ubuntu:ubuntu /home/ubuntu/.bashrc

# Enable cloud-init units that exist
for svc in cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service; do
  if systemctl list-unit-files "$svc" --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "$svc"; then
    run_or_warn_silent systemctl enable "$svc"
  else
    warn "Skipping enable $svc (unit not found)"
  fi
done

# Optional: inject SSH public key
if [[ -n "${PACKER_SSH_PUBLIC_KEY:-}" && -d /home/ubuntu ]]; then
  run_or_warn install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
  run_or_warn bash -c "echo \"$PACKER_SSH_PUBLIC_KEY\" > /home/ubuntu/.ssh/authorized_keys"
  run_or_warn chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
  run_or_warn chmod 0600 /home/ubuntu/.ssh/authorized_keys
fi

# Reset machine-id for cloning
run_or_warn truncate -s 0 /etc/machine-id
run_or_warn rm -f /var/lib/dbus/machine-id
run_or_warn ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Clean up
run_or_warn_silent rm -rf /tmp/capstone-userstack
run_or_warn_silent rm -rf /tmp/scripts
run_or_warn_silent apt-get clean
run_or_warn_silent rm -rf /var/lib/apt/lists/*
echo "Red VM provisioning complete."
