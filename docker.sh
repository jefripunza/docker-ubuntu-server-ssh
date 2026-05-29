#!/bin/bash

# Variables
IMAGE_NAME="vps-ubuntu-server"
CONTAINER_NAME="$IMAGE_NAME-app"

# SSH User and Password Configuration
SSH_PORT=${SSH_PORT:-2222}
TTYD_PORT=${TTYD_PORT:-6080}
SSH_USER=${SSH_USER:-ubuntu}
SSH_PASSWORD=${SSH_PASSWORD:-ubuntu}
SSH_HOSTNAME=${SSH_HOSTNAME:-server}

# Build multi-architecture Docker image using buildx
echo "🔨 Building multi-architecture Docker image using buildx..."
docker buildx build --no-cache --platform linux/amd64,linux/arm64 -t $IMAGE_NAME . --load

# Check if container already exists
if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
  echo "🛑 Stopping & removing old container..."
  docker stop $CONTAINER_NAME >/dev/null 2>&1
  docker rm $CONTAINER_NAME >/dev/null 2>&1
fi

# Run new container
echo "🚀 Running new container..."
docker run -d --privileged \
  --cpus="2.0" \
  --memory="2g" \
  -p "$SSH_PORT":22 \
  -p "$TTYD_PORT":6080 \
  --name $CONTAINER_NAME \
  --hostname "$SSH_HOSTNAME" \
  -e SSH_USER="$SSH_USER" \
  -e SSH_PASSWORD="$SSH_PASSWORD" \
  $IMAGE_NAME
