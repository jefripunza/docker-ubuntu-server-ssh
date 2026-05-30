FROM earthbuild/dind:ubuntu-24.04-docker-28.5.2-1 as base
LABEL maintainer="Jefri Herdi Triyanto <jefriherditriyanto@gmail.com>"
LABEL description="VPS Ubuntu Server - Easy setup ubuntu server on Docker with SSH & TTYD"

RUN apt-get update && apt-get install -y \
  software-properties-common \
  && add-apt-repository -y ppa:zhangsongcui3371/fastfetch \
  && apt-get update && apt-get install -y \
  sudo \
  openssh-server \
  ttyd \
  nano \
  vim \
  curl \
  wget \
  net-tools \
  iputils-ping \
  htop \
  btop \
  fastfetch \
  speedtest-cli \
  iproute2 \
  && curl -Lo /usr/local/bin/neofetch https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch \
  && chmod +x /usr/local/bin/neofetch \
  && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY banner.sh /etc/banner.sh
RUN chmod +x /entrypoint.sh /etc/banner.sh && echo "bash /etc/banner.sh" >> /etc/bash.bashrc

EXPOSE 22 6080

ENTRYPOINT ["/entrypoint.sh"]
