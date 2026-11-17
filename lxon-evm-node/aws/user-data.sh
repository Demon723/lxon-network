#!/bin/bash
# LXON node user-data: install Docker Engine + compose plugin, nothing else.
# Stack config arrives afterwards via scp (see deploy.sh).
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker.io curl ca-certificates

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/v2.35.1/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

usermod -aG docker ubuntu
systemctl enable --now docker
docker compose version
