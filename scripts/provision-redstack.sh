#!/usr/bin/env bash
set -e

# Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install standard utilities and Web Pentest tools
apt-get install -y \
    curl wget vim git htop tmux unzip jq \
    python3 python3-pip python3-venv \
    sqlmap wfuzz gobuster nikto wpscan dirb

# Create a dedicated directory for the assistant
mkdir -p /opt/red-lab-assistant
cp -r /tmp/capstone-userstack/red-lab-assistant/* /opt/red-lab-assistant/ || echo "No assistant files found in tmp, may need to be mapped"
chown -R ubuntu:ubuntu /opt/red-lab-assistant

# Setup Virtual Environment for Assistant
su - ubuntu -c "python3 -m venv /opt/red-lab-assistant/venv"
su - ubuntu -c "/opt/red-lab-assistant/venv/bin/pip install --upgrade pip"
if [ -f "/opt/red-lab-assistant/requirements.txt" ]; then
    su - ubuntu -c "/opt/red-lab-assistant/venv/bin/pip install -r /opt/red-lab-assistant/requirements.txt"
fi

# Install systemd service for Assistant
cp /tmp/capstone-userstack/red-lab-assistant.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable red-lab-assistant.service
systemctl start red-lab-assistant.service

# Configure tmux to auto-start for ubuntu user to enable "Context-Awareness"
cat << 'EOF' >> /home/ubuntu/.bashrc

# Auto-start tmux session 'red_session' if not in one
if [ -z "$TMUX" ]; then
    tmux attach-session -t red_session || tmux new-session -s red_session
fi
EOF
chown ubuntu:ubuntu /home/ubuntu/.bashrc

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
echo "Red VM provisioning complete."
