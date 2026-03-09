#!/usr/bin/env bash
set -e
set -o pipefail

warn() {
  echo "WARN: $*" >&2
}

die() {
  echo "ERROR: $*" >&2
  exit 1
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

run_or_die() {
  set +e
  "$@"
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    die "command failed (rc=${rc}): $*"
  fi
  return 0
}

# Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
ASSIST_REQUIRED="${ASSIST_REQUIRED:-1}"
TMUX_AUTOSTART="${TMUX_AUTOSTART:-1}"

run_or_die apt-get update -y

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
BASE_PKGS=(
  curl wget vim git htop tmux unzip jq
  python3 python3-pip python3-venv
)
TOOL_PKGS=(
  sqlmap wfuzz gobuster nikto wpscan dirb
)

run_or_die apt-get install -y --no-install-recommends "${BASE_PKGS[@]}"
for pkg in "${TOOL_PKGS[@]}"; do
  run_or_warn_silent apt-get install -y --no-install-recommends "$pkg"
done

# Optimize SSH session performance
ensure_sshd_setting() {
  local key="$1"
  local val="$2"
  local conf="/etc/ssh/sshd_config"

  if [ ! -f "$conf" ]; then
    warn "Missing $conf; skipping SSH optimization"
    return 0
  fi

  if grep -qE "^[#[:space:]]*${key}\\b" "$conf"; then
    run_or_warn sed -i "s|^[#[:space:]]*${key}\\b.*|${key} ${val}|g" "$conf"
  else
    run_or_warn bash -c "echo '${key} ${val}' >> ${conf}"
  fi
}

ensure_sshd_setting "UseDNS" "no"
ensure_sshd_setting "GSSAPIAuthentication" "no"
ensure_sshd_setting "ClientAliveInterval" "120"
ensure_sshd_setting "ClientAliveCountMax" "3"

if command -v systemctl >/dev/null 2>&1; then
  run_or_warn_silent systemctl restart ssh || run_or_warn_silent systemctl restart sshd
else
  run_or_warn_silent service ssh restart || run_or_warn_silent service sshd restart
fi

# Create a dedicated directory for the assistant
run_or_die mkdir -p /opt/red-lab-assistant

ASSIST_SRC=""
if [ -d /tmp/capstone-userstack/red-lab-assistant ]; then
  ASSIST_SRC="/tmp/capstone-userstack/red-lab-assistant"
elif [ -d /tmp/capstone-userstack ] && [ -f /tmp/capstone-userstack/app.py ]; then
  ASSIST_SRC="/tmp/capstone-userstack"
elif [ -d /tmp/red-lab-assistant ]; then
  ASSIST_SRC="/tmp/red-lab-assistant"
elif [ -d /tmp/capstone-userstack/red-lab-assistant/red-lab-assistant ]; then
  ASSIST_SRC="/tmp/capstone-userstack/red-lab-assistant/red-lab-assistant"
fi

if [ -n "$ASSIST_SRC" ]; then
  run_or_die cp -r "$ASSIST_SRC"/* /opt/red-lab-assistant/
else
  if [ "$ASSIST_REQUIRED" = "1" ]; then
    die "No assistant files found under /tmp (expected red-lab-assistant). Set ASSIST_REQUIRED=0 to skip."
  else
    warn "No assistant files found under /tmp (expected red-lab-assistant); skipping install."
  fi
fi

run_or_die chown -R ubuntu:ubuntu /opt/red-lab-assistant

# Setup Virtual Environment for Assistant
if command -v python3 >/dev/null 2>&1; then
  run_or_die su - ubuntu -c "python3 -m venv /opt/red-lab-assistant/venv"
  run_or_die su - ubuntu -c "/opt/red-lab-assistant/venv/bin/pip install --upgrade pip"
  if [ -f "/opt/red-lab-assistant/requirements.txt" ]; then
    run_or_die su - ubuntu -c "/opt/red-lab-assistant/venv/bin/pip install --no-cache-dir -r /opt/red-lab-assistant/requirements.txt"
  else
    if [ "$ASSIST_REQUIRED" = "1" ]; then
      die "Missing /opt/red-lab-assistant/requirements.txt"
    else
      warn "Missing /opt/red-lab-assistant/requirements.txt; skipping pip install"
    fi
  fi
else
  if [ "$ASSIST_REQUIRED" = "1" ]; then
    die "python3 not available; cannot setup assistant venv"
  else
    warn "python3 not available; skipping venv setup"
  fi
fi

# Install systemd service for Assistant
ASSIST_SERVICE_INSTALLED=0
if [ -f /tmp/capstone-userstack/red-lab-assistant.service ]; then
  run_or_die cp /tmp/capstone-userstack/red-lab-assistant.service /etc/systemd/system/
  ASSIST_SERVICE_INSTALLED=1
else
  if [ "$ASSIST_REQUIRED" = "1" ]; then
    die "Missing red-lab-assistant.service in /tmp/capstone-userstack"
  else
    warn "Missing red-lab-assistant.service in /tmp/capstone-userstack"
  fi
fi
if command -v systemctl >/dev/null 2>&1; then
  if [ "$ASSIST_SERVICE_INSTALLED" = "1" ]; then
    run_or_die systemctl daemon-reload
    run_or_die systemctl enable red-lab-assistant.service
    run_or_die systemctl start red-lab-assistant.service
  else
    warn "Assistant service not installed; skipping enable/start"
  fi
else
  warn "systemctl not available; skipping service enable/start"
fi

# Configure tmux to auto-start for ubuntu user to enable "Context-Awareness"
if [ "$TMUX_AUTOSTART" = "1" ] && [ -f /home/ubuntu/.bashrc ]; then
  if ! grep -q "RED_LAB_TMUX_AUTOSTART" /home/ubuntu/.bashrc; then
    cat << 'EOF' >> /home/ubuntu/.bashrc || true

# RED_LAB_TMUX_AUTOSTART
# Red Lab: tmux autostart (interactive shells only)
if [[ $- == *i* ]] && [ -z "${TMUX:-}" ]; then
    tmux attach-session -t red_session || tmux new-session -s red_session
fi
EOF
  fi
  run_or_warn chown ubuntu:ubuntu /home/ubuntu/.bashrc
fi

# Enable cloud-init units that exist
if command -v systemctl >/dev/null 2>&1; then
  for svc in cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service; do
    if systemctl list-unit-files "$svc" --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "$svc"; then
      run_or_warn_silent systemctl enable "$svc"
    else
      warn "Skipping enable $svc (unit not found)"
    fi
  done
else
  warn "systemctl not available; skipping cloud-init enable"
fi

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
