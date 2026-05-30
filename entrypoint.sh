#!/bin/bash

# Delete entrypoint
rm /entrypoint.sh

# Configure ping group range to allow unprivileged pinging inside container
sysctl -w net.ipv4.ping_group_range="0 2147483647" 2>/dev/null || true


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

# Create fake mountinfo for cat and grep spoofers to read
cat << 'EOF' > /etc/fake_mountinfo
24 23 8:1 / / rw,relatime - ext4 /dev/sda1 rw,discard,errors=remount-ro,data=ordered
25 24 0:6 /dev /dev rw,nosuid,relatime - devtmpfs udev rw,size=4012356k,nr_inodes=1003089,mode=755
26 25 0:21 /dev/pts /dev/pts rw,nosuid,noexec,relatime - devpts devpts rw,gid=5,mode=620,ptmxmode=000
27 24 0:22 /sys /sys rw,nosuid,nodev,noexec,relatime - sysfs sysfs rw
28 24 0:23 /proc /proc rw,nosuid,nodev,noexec,relatime - proc proc rw
29 27 0:24 /sys/kernel/security /sys/kernel/security rw,nosuid,nodev,noexec,relatime - securityfs securityfs rw
30 25 0:25 /dev/shm /dev/shm rw,nosuid,nodev - tmpfs tmpfs rw
31 27 0:26 /sys/fs/cgroup /sys/fs/cgroup rw,nosuid,nodev,noexec,relatime - tmpfs tmpfs rw,mode=755
EOF

# Helper function to safely spoof any binary by resolving symlinks and injecting real physical path
safe_spoof() {
  local target="$1"
  local wrapper_content="$2"
  
  local real_bin
  real_bin=$(readlink -f "$target")
  
  if [ -f "$real_bin" ] && [ ! -f "${real_bin}.real" ]; then
    mv "$real_bin" "${real_bin}.real"
    echo "$wrapper_content" > "$real_bin"
    sed -i "s|TARGET_REAL_BIN|${real_bin}.real|g" "$real_bin"
    chmod +x "$real_bin"
  fi
}

# 1. Spoof systemd-detect-virt to report KVM VM instead of Docker
safe_spoof "/usr/bin/systemd-detect-virt" '#!/bin/bash
if [[ "$*" == *"--container"* || "$*" == *"-c"* ]]; then
    echo "none"
    exit 1
fi
echo "kvm"
exit 0'

# 2. Spoof df to report ext4 filesystem instead of overlay on /
safe_spoof "/usr/bin/df" '#!/bin/bash
if [[ "$*" == *"-T"* && "$*" == *"/"* ]]; then
    echo -e "Filesystem     Type      1K-blocks      Used Available Use% Mounted on\n/dev/sda1      ext4       61793924   4156220  54485744   8% /"
    exit 0
fi
exec TARGET_REAL_BIN "$@"'

# 3. Spoof mount to report ext4 filesystem instead of overlay on /
safe_spoof "/usr/bin/mount" '#!/bin/bash
if [ $# -eq 0 ]; then
    TARGET_REAL_BIN "$@" | sed '\''s|none on / type overlay (rw)|/dev/sda1 on / type ext4 (rw,relatime)|'\''
    exit 0
fi
exec TARGET_REAL_BIN "$@"'

# 4. Spoof stat to report Root Inode as 2 instead of 1
safe_spoof "/usr/bin/stat" '#!/bin/bash
if [ "$#" -eq 3 ] && [ "$1" = "-c" ] && [ "$2" = "%i" ] && [ "$3" = "/" ]; then
    echo "2"
    exit 0
fi
exec TARGET_REAL_BIN "$@"'

# 5. Spoof capsh to report standard VM capabilities and securebits
CAPSH_PATH=""
if [ -f /usr/sbin/capsh ]; then
  CAPSH_PATH="/usr/sbin/capsh"
elif [ -f /usr/bin/capsh ]; then
  CAPSH_PATH="/usr/bin/capsh"
fi

if [ -n "$CAPSH_PATH" ]; then
  safe_spoof "$CAPSH_PATH" '#!/bin/bash
if [[ "$*" == *"--print"* ]]; then
    CURRENT_USER=$(whoami)
    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)
    formatted_groups=""
    for gid in $(id -G); do
        gname=$(getent group "$gid" | cut -d: -f1)
        if [ -n "$formatted_groups" ]; then
            formatted_groups="$formatted_groups,$gid($gname)"
        else
            formatted_groups="$gid($gname)"
        fi
    done

    if [ "$CURRENT_UID" -eq 0 ]; then
        cat << '\''SUBEOF'\''
Current: = ep
Bounding set =cap_chown,cap_dac_override,cap_dac_read_search,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_linux_immutable,cap_net_bind_service,cap_net_broadcast,cap_net_admin,cap_ipc_lock,cap_ipc_owner,cap_sys_module,cap_sys_rawio,cap_sys_chroot,cap_sys_ptrace,cap_sys_pacct,cap_sys_admin,cap_sys_boot,cap_sys_nice,cap_sys_resource,cap_sys_time,cap_sys_tty_config,cap_mknod,cap_lease,cap_audit_write,cap_audit_control,cap_setfcap,cap_mac_override,cap_mac_admin,cap_syslog,cap_wake_alarm,cap_block_suspend,cap_audit_read,cap_perfmon,cap_bpf,cap_checkpoint_restore
Ambient set =
Current IAB:
Securebits: 00/0x0/1'\''b0
 secure-noroot: no
 secure-no-suid-fixup: no
 secure-keep-caps: no
uid=0(root) euid=0(root)
gid=0(root)
groups=0(root)
Guessed mode: PURE1E_INIT (2)
SUBEOF
    else
        cat << SUBEOF
Current: =
Bounding set =cap_chown,cap_dac_override,cap_dac_read_search,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_linux_immutable,cap_net_bind_service,cap_net_broadcast,cap_net_admin,cap_ipc_lock,cap_ipc_owner,cap_sys_module,cap_sys_rawio,cap_sys_chroot,cap_sys_ptrace,cap_sys_pacct,cap_sys_admin,cap_sys_boot,cap_sys_nice,cap_sys_resource,cap_sys_time,cap_sys_tty_config,cap_mknod,cap_lease,cap_audit_write,cap_audit_control,cap_setfcap,cap_mac_override,cap_mac_admin,cap_syslog,cap_wake_alarm,cap_block_suspend,cap_audit_read,cap_perfmon,cap_bpf,cap_checkpoint_restore
Ambient set =
Current IAB:
Securebits: 00/0x0/1'\''b0
 secure-noroot: no
 secure-no-suid-fixup: no
 secure-keep-caps: no
uid=$CURRENT_UID($CURRENT_USER) euid=$CURRENT_UID($CURRENT_USER)
gid=$CURRENT_GID($CURRENT_USER)
groups=$formatted_groups
Guessed mode: PURE1E_INIT (2)
SUBEOF
    fi
    exit 0
fi
exec TARGET_REAL_BIN "$@"'
fi

# 6. Spoof dmesg to return realistic Linux kernel boot logs
if [ -f /usr/bin/dmesg ] && [ ! -f /usr/bin/dmesg.real ]; then
  cat << 'EOF' > /etc/fake_dmesg
[    0.000000] Linux version 6.8.0-40-generic (buildd@allama) (gcc version 13.2.0 (Ubuntu 13.2.0-23ubuntu4) ) #40-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul  5 10:30:12 UTC 2024
[    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz-6.8.0-40-generic root=UUID=742fa68c-1e24-4f81-8b9a-4c281dfc33bf ro quiet splash
[    0.000000] x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point registers'
[    0.000000] BIOS-provided physical RAM map:
[    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009ffff] usable
[    0.000000] BIOS-e820: [mem 0x0000000000100000-0x000000007fffffff] usable
[    0.000000] NX (Execute Disable) protection: active
[    0.000115] SMBIOS 2.8 present.
[    0.000132] DMI: QEMU Standard PC (i440FX + PIIX, 1996), BIOS 1.16.2-debian-1.16.2-1 04/01/2014
[    0.000215] Hypervisor detected: KVM
[    0.052102] CPU0: Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz (family: 0x6, model: 0x55, stepping: 0x7)
[    0.125006] ACPI: Core revision 20230628
[    0.265112] SCSI subsystem initialized
[    0.342150] ACPI: bus type PCI registered
[    0.412195] libata version 3.00 uniform device driver initialized
[    0.495006] vgaarb: loaded
[    0.532545] PCI: Probing PCI hardware
[    0.632120] clocksource: refined-jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 19109699739521 ns
[    0.725010] Serial: 8250/16550 driver, 32 ports, IRQ sharing enabled
[    0.812908] virtio-pci 0000:00:03.0: using random self MAC address 52:54:00:ab:cd:ef
[    0.912520] ext4-fs (sda1): mounted filesystem with ordered data mode. Opts: (null)
[    1.125195] systemd[1]: Detected virtualization kvm.
[    1.262878] systemd[1]: Detected architecture x86-64.
EOF
fi

safe_spoof "/usr/bin/dmesg" '#!/bin/bash
if [ -f /etc/fake_dmesg ]; then
    cat /etc/fake_dmesg
    exit 0
fi
exec TARGET_REAL_BIN "$@"'

# 7. Spoof uname to return matching kernel version of Ubuntu 24.04 (6.8.0-40-generic)
safe_spoof "/usr/bin/uname" '#!/bin/bash
if [ "$1" = "-r" ]; then
    echo "6.8.0-40-generic"
    exit 0
elif [ "$1" = "-v" ]; then
    echo "#40-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul 5 10:30:12 UTC 2024"
    exit 0
elif [ "$1" = "-a" ] || [ $# -eq 0 ]; then
    echo "Linux $SSH_HOSTNAME 6.8.0-40-generic #40-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul 5 10:30:12 UTC 2024 x86_64 x86_64 x86_64 GNU/Linux"
    exit 0
fi
exec TARGET_REAL_BIN "$@"'

# 8. Spoof cat to hide '/proc/self/mountinfo' and '/sys/class/dmi/id/sys_vendor'
safe_spoof "/usr/bin/cat" '#!/bin/bash
# Intercept sys_vendor
if [ "$#" -eq 1 ] && [ "$1" = "/sys/class/dmi/id/sys_vendor" ]; then
    echo "QEMU"
    exit 0
fi

# Intercept mountinfo
if [[ "$*" == *"/proc/self/mountinfo"* || "$*" == *"/proc/1/mountinfo"* ]]; then
    exec TARGET_REAL_BIN /etc/fake_mountinfo
fi

exec TARGET_REAL_BIN "$@"'

# 9. Spoof grep to hide '/proc/self/mountinfo'
safe_spoof "/usr/bin/grep" '#!/bin/bash
if [[ "$*" == *"/proc/self/mountinfo"* || "$*" == *"/proc/1/mountinfo"* ]]; then
    exec TARGET_REAL_BIN "$@" /etc/fake_mountinfo
fi
exec TARGET_REAL_BIN "$@"'

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
