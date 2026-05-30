#!/bin/bash

# Delete entrypoint
rm /entrypoint.sh

# Default values if environment variables are not set
SSH_PORT=${SSH_PORT:-2222}
TTYD_PORT=${TTYD_PORT:-6080}
SSH_USER=${SSH_USER:-ubuntu}
SSH_PASSWORD=${SSH_PASSWORD:-ubuntu}
SSH_HOSTNAME=${SSH_HOSTNAME:-server}
FLAG_FILE="/var/local/initialize_ok"

# Spoof CPU to Intel Xeon Gold 6248 (honest core count)
ACTUAL_CORES=$(nproc)
TOTAL_INDEX=$((ACTUAL_CORES - 1))

echo "🔧 Spoofing CPU to Intel Xeon Gold 6248 with honest core count ($ACTUAL_CORES cores)..."
rm -f /etc/fake_cpuinfo
for i in $(seq 0 $TOTAL_INDEX); do
  cat << EOF >> /etc/fake_cpuinfo
processor	: $i
vendor_id	: GenuineIntel
cpu family	: 6
model		: 85
model name	: Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz
stepping	: 7
cpu MHz		: 2500.000
cache size	: 28160 KB
physical id	: 0
siblings	: $ACTUAL_CORES
core id		: $i
cpu cores	: $ACTUAL_CORES

EOF
done
umount /proc/cpuinfo >/dev/null 2>&1 || true
if mount --bind /etc/fake_cpuinfo /proc/cpuinfo >/dev/null 2>&1 || sudo mount --bind /etc/fake_cpuinfo /proc/cpuinfo >/dev/null 2>&1; then
  echo "✅ CPU spoofing applied successfully."
else
  echo "⚠️ CPU spoofing via bind-mount failed (insufficient privileges / non-privileged container). Falling back to native /proc/cpuinfo."
fi

# Configure system-wide fastfetch default config for CPU spoofing
mkdir -p /etc/fastfetch
cat << EOF > /etc/fastfetch/config.jsonc
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "modules": [
    "title",
    "separator",
    "os",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "display",
    "de",
    "wm",
    "wmtheme",
    "theme",
    "icons",
    "font",
    "cursor",
    "terminal",
    "terminalfont",
    {
      "type": "cpu",
      "format": "Intel Xeon Gold 6248 ($ACTUAL_CORES)"
    },
    "memory",
    "swap",
    "disk",
    "localip",
    "locale",
    "break"
  ]
}
EOF

# Make sure SSH run directory exists
mkdir -p /var/run/sshd

if [ ! -f "$FLAG_FILE" ]; then
  echo "⚙️ Initializing container for user '$SSH_USER'..."

  # Create SSH user if not exists
  if ! id -u "$SSH_USER" >/dev/null 2>&1; then
    useradd -ms /bin/bash "$SSH_USER"
  fi

  # Set password for SSH_USER and root
  echo "$SSH_USER:$SSH_PASSWORD" | chpasswd
  echo "root:$SSH_PASSWORD" | chpasswd

  # Add user to sudo group
  usermod -aG sudo "$SSH_USER"

  # Add user to docker group if it exists
  if getent group docker >/dev/null; then
    usermod -aG docker "$SSH_USER"
  fi

  # Enable PasswordAuthentication and PermitRootLogin in SSH config
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

  # Configure passwordless sudo for this user
  if ! grep -q "^$SSH_USER " /etc/sudoers; then
    echo "$SSH_USER    ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
  fi

  # Generate SSH key pair for SSH_USER to enable passwordless localhost SSH elevation under gVisor
  mkdir -p /home/$SSH_USER/.ssh
  ssh-keygen -t rsa -N "" -f /home/$SSH_USER/.ssh/id_rsa
  chown -R $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh
  chmod 700 /home/$SSH_USER/.ssh
  chmod 600 /home/$SSH_USER/.ssh/id_rsa

  # Add it to root's authorized_keys
  mkdir -p /root/.ssh
  cat /home/$SSH_USER/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/authorized_keys

  # Create a custom sudo wrapper to bypass gVisor's SUID limitation via localhost SSH
  cat << EOF > /usr/local/bin/sudo
#!/bin/bash

# If already root, run directly
if [ "\$(id -u)" -eq 0 ]; then
    exec "\$@"
fi

# If no arguments, or if 'su', run a root login shell
if [ \$# -eq 0 ] || [ "\$1" = "su" ]; then
    exec ssh -i "\$HOME/.ssh/id_rsa" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t root@127.0.0.1
fi

# Build ssh flags
SSH_FLAGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
if [ -t 0 ]; then
    SSH_FLAGS="\$SSH_FLAGS -t"
else
    SSH_FLAGS="\$SSH_FLAGS -T"
fi

# Properly escape arguments to prevent remote shell splitting/unescaping issues
escaped_cmd=""
for arg in "\$@"; do
    escaped_cmd="\$escaped_cmd \$(printf '%q' "\$arg")"
done

exec ssh -i "\$HOME/.ssh/id_rsa" \$SSH_FLAGS root@127.0.0.1 "\$escaped_cmd"
EOF

  chmod +x /usr/local/bin/sudo

  # Force Docker Desktop macOS DNS Gateway inside gVisor (jangan dihapus, nanti "sudo apt update" nya error)
  echo "nameserver 192.168.65.2" > /etc/resolv.conf

  # Create the initialization flag file (format: YYYY-mm-dd_HH-mm-ss)
  mkdir -p "$(dirname "$FLAG_FILE")"
  date "+%Y-%m-%d_%H-%M-%S" > "$FLAG_FILE"

  echo "✅ Initialization complete at $(cat "$FLAG_FILE")."
else
  echo "🚀 Container already initialized at $(cat "$FLAG_FILE"), skipping setup."
fi

# Hide Docker environment indicators (delete /.dockerenv)
rm -f /.dockerenv

# Spoof systemd-detect-virt to report KVM VM instead of Docker
rm -f /usr/bin/systemd-detect-virt
cat << 'EOF' > /usr/bin/systemd-detect-virt
#!/bin/bash
if [[ "$*" == *"--container"* || "$*" == *"-c"* ]]; then
    echo "none"
    exit 1
fi
echo "kvm"
exit 0
EOF
chmod +x /usr/bin/systemd-detect-virt

# Dynamically set active system hostname in UTS namespace and update hosts/hostname files
hostname "$SSH_HOSTNAME" 2>/dev/null || true
echo "$SSH_HOSTNAME" > /etc/hostname || true
if ! grep -q "$SSH_HOSTNAME" /etc/hosts; then
  echo "127.0.0.1 $SSH_HOSTNAME" >> /etc/hosts || true
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
echo " 🔌 SSH: $SSH_USER@localhost:$SSH_PORT"
echo " 💻 Terminal: http://localhost:$TTYD_PORT"
echo " ------------------------------------------"

# Run ttyd server
echo "🚀 Starting ttyd server..."
exec ttyd -W -c "$SSH_USER":"$SSH_PASSWORD" -p 6080 su - "$SSH_USER"
