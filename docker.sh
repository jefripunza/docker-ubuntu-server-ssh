#!/bin/bash

# Variables
IMAGE_NAME="vps-ubuntu-server"
CONTAINER_NAME="$IMAGE_NAME-app"
DOCKER_USERNAME="jefriherditriyanto"

# SSH User and Password Configuration
SSH_PORT=${SSH_PORT:-2222}
TTYD_PORT=${TTYD_PORT:-6080}
SSH_USER=${SSH_USER:-ubuntu}
SSH_PASSWORD=${SSH_PASSWORD:-ubuntu}
SSH_HOSTNAME=${SSH_HOSTNAME:-server}

while true; do
  echo "📋 Select option:"
  echo "1) Build & Run locally (development)"
  echo "2) Build & Push to Docker Hub"
  read -p "Choice [1/2]: " choice
  if [[ "$choice" == "1" || "$choice" == "2" ]]; then
    break
  else
    echo "⚠️ Invalid choice. Please select 1 or 2."
    echo
  fi
done

if [ "$choice" = "2" ]; then
  DOCKER_HUB_REPO="$DOCKER_USERNAME/$IMAGE_NAME"
  echo "🔍 Fetching latest tags from Docker Hub..."
  latest_version=$(curl -s "https://hub.docker.com/v2/repositories/${DOCKER_HUB_REPO}/tags/?page_size=100" | \
    jq -r '.results[].name' 2>/dev/null | \
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
    sort -V | \
    tail -n 1)

  if [ -z "$latest_version" ]; then
    latest_version="0.0.0"
  fi
  echo "📢 Latest pushed version: $latest_version"

  # Helper function to check if version1 > version2
  version_gt() {
    local IFS=.
    local i t1=($1) t2=($2)
    for ((i=${#t1[@]}; i<3; i++)); do t1[i]=0; done
    for ((i=${#t2[@]}; i<3; i++)); do t2[i]=0; done
    for ((i=0; i<3; i++)); do
      if ((10#${t1[i]} > 10#${t2[i]})); then
        return 0
      elif ((10#${t1[i]} < 10#${t2[i]})); then
        return 1
      fi
    done
    return 1
  }

  while true; do
    read -p "Enter version tag (latest: $latest_version): " version_tag
    if [[ ! "$version_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "⚠️ Invalid version format. Please use 'x.x.x' format (e.g., 1.0.0)."
      echo
      continue
    fi

    if version_gt "$version_tag" "$latest_version"; then
      break
    else
      echo "⚠️ Version must be higher than the latest pushed version ($latest_version)!"
      echo
    fi
  done
  echo "🔨 Building and pushing multi-architecture Docker image using buildx to $DOCKER_HUB_REPO:latest and $DOCKER_HUB_REPO:$version_tag..."
  docker buildx build --no-cache --platform linux/amd64,linux/arm64 -t $DOCKER_HUB_REPO:latest -t $DOCKER_HUB_REPO:$version_tag . --push

  # Update version in docker-compose.yaml
  if [ -f "docker-compose.yaml" ]; then
    echo "📝 Updating version in docker-compose.yaml to $version_tag..."
    sed -i '' -E "s|image: $DOCKER_HUB_REPO:[0-9]+\.[0-9]+\.[0-9]+|image: $DOCKER_HUB_REPO:$version_tag|" docker-compose.yaml
  fi

  # Update Docker Hub overview
  if [ -f "README.md" ]; then
    read -p "❓ Do you want to update the Docker Hub repository overview? [y/N]: " update_choice
    if [[ "$update_choice" =~ ^[Yy]$ ]]; then
      echo "🌐 Updating Docker Hub repository overview from README.md..."
      if [ -z "$DOCKER_HUB_PASSWORD" ]; then
        DOCKER_HUB_PASSWORD=$(security find-internet-password -s index.docker.io -w 2>/dev/null)
      fi
      if [ -z "$DOCKER_HUB_PASSWORD" ]; then
        read -s -p "🔑 Enter Docker Hub Password or Access Token: " DOCKER_HUB_PASSWORD
        echo
      fi
      
      if [ -n "$DOCKER_HUB_PASSWORD" ]; then
        # Get JWT Token
        token=$(curl -s -H "Content-Type: application/json" -X POST \
          -d "{\"username\": \"$DOCKER_USERNAME\", \"password\": \"$DOCKER_HUB_PASSWORD\"}" \
          "https://hub.docker.com/v2/users/login" | jq -r '.token' 2>/dev/null)
        
        if [ -n "$token" ] && [ "$token" != "null" ]; then
          readme_content=$(cat README.md)
          update_status=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
            -H "Authorization: JWT $token" \
            -H "Content-Type: application/json" \
            -d "{\"full_description\": $(jq -Rs . <<< "$readme_content")}" \
            "https://hub.docker.com/v2/repositories/$DOCKER_HUB_REPO/")
          
          if [ "$update_status" -eq 200 ]; then
            echo "✅ Docker Hub repository overview updated successfully."
          else
            echo "⚠️ Failed to update Docker Hub overview (HTTP Status: $update_status)."
          fi
        else
          echo "⚠️ Failed to authenticate with Docker Hub. Overview update skipped."
        fi
      else
        echo "⚠️ No password provided. Skipping Docker Hub overview update."
      fi
    else
      echo "⏭️ Skipping Docker Hub overview update."
    fi
  fi
else
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
    --sysctl net.ipv4.ping_group_range="0 2147483647" \
    -p "$SSH_PORT":22 \
    -p "$TTYD_PORT":6080 \
    --name $CONTAINER_NAME \
    --hostname "$SSH_HOSTNAME" \
    -e SSH_USER="$SSH_USER" \
    -e SSH_PASSWORD="$SSH_PASSWORD" \
    $IMAGE_NAME
fi
