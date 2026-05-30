# Sawang.Cloud Premium VPS Environment
[![Docker Pulls](https://img.shields.io/docker/pulls/jefriherditriyanto/vps-ubuntu-server.svg?style=flat-square)](https://hub.docker.com/r/jefriherditriyanto/vps-ubuntu-server)
[![Docker Image Size](https://img.shields.io/docker/image-size/jefriherditriyanto/vps-ubuntu-server/latest.svg?style=flat-square)](https://hub.docker.com/r/jefriherditriyanto/vps-ubuntu-server)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64%20%7C%20linux%2Farm64-blue.svg?style=flat-square)](https://hub.docker.com/r/jefriherditriyanto/vps-ubuntu-server)

An ultra-realistic, secure, sandboxed, high-performance virtual private server (VPS) environment built on top of **Ubuntu 24.04 LTS (Noble Numbat)**. 

Engineered for production and development workloads, this environment is hardened using Google's **gVisor (`runsc`)** sandbox runtime. It is specifically designed to bypass Docker environment indicators, perfectly cloaking itself as a pure **KVM-based Virtual Machine** while offering full outbound network capabilities (such as unprivileged `ping`), a secure passwordless `sudo` localhost bridge, and a premium shell experience.

---

## 🚀 Key Features

*   **🔒 gVisor Sandboxing & Hardening**: Fully isolated kernel environment using Google’s `runsc` secure runtime, providing unmatched protection against container escape vulnerabilities.
*   **🎭 Perfect KVM Virtualization Masking**:
    *   `systemd-detect-virt` reports `kvm` (and `none` under container checks).
    *   Root filesystem (`/`) is masked as `ext4` on `/dev/sda1` (no `overlay` indicators).
    *   Root directory (`/`) possesses standard inode `2` (avoiding overlay's typical inode `1`).
    *   Intercepted `/proc/self/mountinfo` and `/proc/1/mountinfo` are cleaned of any docker/overlay references.
    *   DMI System Vendor reports `QEMU` under `/sys/class/dmi/id/sys_vendor`.
*   **💻 Enterprise CPU & Kernel Spoofing**:
    *   Simulates an **Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz** with matching core topology.
    *   `uname -a` reports a production **6.8.0-40-generic** kernel.
    *   `dmesg` yields realistic KVM VM boot logs instead of gVisor initialization markers.
*   **🔑 Passwordless Localhost SSH Sudo Escalation**: Bypasses gVisor SUID constraints seamlessly. Runs full `sudo` and `sudo su` via an automated internal SSH key-based escalation path.
*   **🌐 Out-of-the-Box Unprivileged Ping**: Auto-stripping SUID/capabilities and setting ICMP group bounds inside the container so `ping 8.8.8.8` works natively as an unprivileged user under hardened clouds.
*   **🖥️ Dual-Access Shell**:
    *   Standard SSH daemon running on port `22` for key/password logins.
    *   Elegant interactive web terminal running on port `6080` powered by **TTYD** with custom modern styling.
*   **☁️ Sawang.Cloud Premium Banner**: Sleek, high-contrast, dual-color ANSI ASCII login banner (Sawang in Indigo/Blue, Cloud in Cyan) detailing active virtualization, OS version, and sandbox specs upon login.

---

## ⚙️ Environment Variables

Customize your VPS container deployment by defining the following environment variables:

| Variable       | Default Value | Description                                           |
| :------------- | :------------ | :---------------------------------------------------- |
| `SSH_USER`     | `ubuntu`      | Main user account for shell terminal and SSH access.  |
| `SSH_PASSWORD` | `ubuntu`      | Password for both `SSH_USER` and `root` accounts.     |
| `SSH_HOSTNAME` | `server`      | Hostname of the simulated VPS system.                 |
| `SSH_PORT`     | `2222`        | Internal SSH port mapped to the host (default: `22`). |
| `TTYD_PORT`    | `6080`        | Internal web terminal port mapped to the host.        |

---

## 📦 Deployment Guides

Choose one of the following three highly optimized deployment methods to spin up your premium VPS environment:

### Method 1: Docker CLI (Fastest Local Launch)
Perfect for local testing, development, and standard VM simulation.

```bash
docker run -d --privileged \
  --cpus="2.0" \
  --memory="2g" \
  --sysctl net.ipv4.ping_group_range="0 2147483647" \
  -p 2222:22 \
  -p 6080:6080 \
  --name vps-ubuntu-server-app \
  --hostname "server" \
  -e SSH_USER="ubuntu" \
  -e SSH_PASSWORD="your_secure_password" \
  jefriherditriyanto/vps-ubuntu-server:latest
```

---

### Method 2: Enterprise Cloud Deployment via Coolify
Coolify is an excellent self-hosted alternative to Heroku/Vercel. Follow these steps to host your virtual environment:

1.  **Create Service**: In your Coolify dashboard, select **Create Resource** -> **Docker Image**.
2.  **Image Configuration**: Set the image name as:
    ```txt
    jefriherditriyanto/vps-ubuntu-server:latest
    ```
3.  **Environment Variables (.env)**: Add the following keys in your Coolify Environment tab:
    ```env
    SSH_USER=ubuntu
    SSH_PASSWORD=your_secure_password_here
    SSH_HOSTNAME=sawang-cloud-vps
    TTYD_PORT=6080
    ```
4.  **Network & Security Settings**:
    *   Navigate to **Configuration** -> **Settings**.
    *   Toggle **Privileged mode** to **Enabled** (Crucial for CPU spoofing, KVM masking, and nested Docker runtime).
    *   Allocate Resources: Set CPU limits to `2` and Memory limits to `2048MB` (`2G`).
5.  **Port Mappings**:
    *   Expose port `22` (SSH Console) and port `6080` (Web Console).
    *   Coolify will automatically map port `6080` to a public URL protected with Let's Encrypt SSL, allowing you to access your virtual terminal safely from anywhere in the world!
6.  **Deploy**: Click **Deploy** to launch.

---

### Method 3: Production Docker Compose (Recommended)
Excellent for managing persistent services, disk limits, and microservices in a single configuration file.

Create a `docker-compose.yaml` in your workspace:

```yaml
version: '3.8'

services:
  ubuntu-ssh:
    image: jefriherditriyanto/vps-ubuntu-server:latest
    container_name: vps-ubuntu-server-app
    # Set runsc runtime to enable Google gVisor
    # See: https://gvisor.dev/docs/user_guide/install/
    runtime: runsc
    privileged: true
    ports:
      - "2222:22"
      - "6080:6080"
    environment:
      - SSH_USER=ubuntu
      - SSH_PASSWORD=your_secure_password_here
      - SSH_HOSTNAME=sawang-server
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
    storage_opt:
      size: '60G'
    restart: always
```

Run the stack in the background:
```bash
docker compose up -d
```

---

## 💻 Connection & Usage

Once deployed, access your Premium VPS environment using either of the following paths:

1.  **SSH Direct Console**:
    ```bash
    ssh -p 2222 ubuntu@your-server-ip
    ```
2.  **Premium Web Terminal**: Open your web browser and navigate to:
    ```txt
    http://your-server-ip:6080
    ```
    Enter your defined `SSH_USER` and `SSH_PASSWORD` to log in. You will be greeted by the stunning, colorful **Sawang.Cloud** login banner and a fully configured KVM-spoofed environment!
