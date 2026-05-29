FROM earthbuild/dind:ubuntu-24.04-docker-28.5.2-1 as base
LABEL maintainer="Jefri Herdi Triyanto <jefriherditriyanto@gmail.com>"
LABEL description="Ubuntu Server SSH - Easy setup ubuntu server on Docker with SSH"

RUN apt-get update && apt-get install -y \
  software-properties-common \
  && add-apt-repository -y ppa:zhangsongcui3371/fastfetch \
  && apt-get update && apt-get install -y \
  openssh-server \
  sudo \
  curl \
  net-tools \
  vim \
  wget \
  htop \
  btop \
  fastfetch \
  novnc \
  python3-websockify \
  python3-numpy \
  && curl -Lo /usr/local/bin/neofetch https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch \
  && chmod +x /usr/local/bin/neofetch \
  && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
