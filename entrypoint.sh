#!/bin/bash

# Delete entrypoint
rm /entrypoint.sh

# Default values if environment variables are not set
SSH_PORT=${SSH_PORT:-2222}
SSH_USER=${SSH_USER:-ubuntu}
SSH_PASSWORD=${SSH_PASSWORD:-ubuntu}
SSH_HOSTNAME=${SSH_HOSTNAME:-server}
FLAG_FILE="/var/local/initialize_ok"

# Make sure SSH run directory exists
mkdir -p /var/run/sshd

if [ ! -f "$FLAG_FILE" ]; then
  echo "⚙️ Initializing container for user '$SSH_USER'..."

  # Create SSH user if not exists
  if ! id -u "$SSH_USER" >/dev/null 2>&1; then
    useradd -ms /bin/bash "$SSH_USER"
  fi

  # Set password
  echo "$SSH_USER:$SSH_PASSWORD" | chpasswd

  # Add user to sudo group
  usermod -aG sudo "$SSH_USER"

  # Add user to docker group if it exists
  if getent group docker >/dev/null; then
    usermod -aG docker "$SSH_USER"
  fi

  # Enable PasswordAuthentication in SSH config
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

  # Configure passwordless sudo for this user
  if ! grep -q "^$SSH_USER " /etc/sudoers; then
    echo "$SSH_USER    ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
  fi

  # Set hostname inside FHS if writable
  echo "$SSH_HOSTNAME" > /etc/hostname || true
  if ! grep -q "$SSH_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1 $SSH_HOSTNAME" >> /etc/hosts || true
  fi

  # Create the initialization flag file (format: YYYY-mm-dd_HH-mm-ss)
  mkdir -p "$(dirname "$FLAG_FILE")"
  date "+%Y-%m-%d_%H-%M-%S" > "$FLAG_FILE"

  echo "✅ Initialization complete at $(cat "$FLAG_FILE")."
else
  echo "🚀 Container already initialized at $(cat "$FLAG_FILE"), skipping setup."
fi

# Run the SSH daemon in the foreground
echo "🚀 Starting SSH daemon..."
/usr/sbin/sshd -D &

# Start Docker daemon in the background
echo "🐳 Starting Docker daemon..."
dockerd >/var/log/dockerd.log 2>&1 &

# Wait for Docker daemon to start
timeout 15 sh -c 'until docker info >/dev/null 2>&1; do sleep 1; done'

# End
echo " ------------------------------------------"
echo " SSH: $SSH_USER@localhost:$SSH_PORT"

# Run noVNC WebSocket server
echo "🚀 Starting noVNC WebSocket server..."
exec websockify --web=/usr/share/novnc 6080 localhost:5901
