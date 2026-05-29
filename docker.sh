#!/bin/bash

IMAGE_NAME="ubuntu-server-ssh"
APP_NAME="$IMAGE_NAME-app"

# Konfigurasi SSH User dan Password (bisa disesuaikan atau di-override via env)
SSH_PORT=${SSH_PORT:-2222}
TTYD_PORT=${TTYD_PORT:-6080}
SSH_USER=${SSH_USER:-ubuntu}
SSH_PASSWORD=${SSH_PASSWORD:-ubuntu}
SSH_HOSTNAME=${SSH_HOSTNAME:-server}

# Hapus file-file yang tidak perlu
echo "🗑️ Cleaning up..."

# Build ulang image dengan multi-arsitektur menggunakan buildx
echo "🔨 Building multi-architecture Docker image using buildx..."
docker buildx build --no-cache --platform linux/amd64,linux/arm64 -t $IMAGE_NAME . --load

# Cek apakah container sudah ada
if [ "$(docker ps -aq -f name=^${APP_NAME}$)" ]; then
  echo "🛑 Stopping & removing old container..."
  docker stop $APP_NAME >/dev/null 2>&1
  docker rm $APP_NAME >/dev/null 2>&1
fi

# Run container baru
echo "🚀 Running new container..."
docker run -d --privileged \
  -p "$SSH_PORT":22 \
  -p "$TTYD_PORT":6080 \
  --name $APP_NAME \
  --hostname "$SSH_HOSTNAME" \
  -e SSH_USER="$SSH_USER" \
  -e SSH_PASSWORD="$SSH_PASSWORD" \
  $IMAGE_NAME
