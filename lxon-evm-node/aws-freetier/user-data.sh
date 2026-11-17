#!/bin/bash
# LXON free-tier node user-data: Docker Engine + Compose plugin + swap, nothing else.
#
# Two differences from ../aws/user-data.sh, both load-bearing on a Graviton micro instance:
#   1. The compose plugin URL is derived from `uname -m`. The old script hardcoded
#      docker-compose-linux-x86_64, which is an ELF that cannot exec on arm64 -- the install
#      would "succeed" and every `docker compose` call would fail with exec format error.
#   2. A 2 GiB swap file, because t4g.micro gives Besu ~1 GiB of address space and the JVM
#      will otherwise be OOM-killed during the first full sync/seal warm-up.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker.io curl ca-certificates

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  CARCH=x86_64 ;;
  aarch64) CARCH=aarch64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/v2.35.1/docker-compose-linux-${CARCH}" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Swap on a 1 GiB host. dd instead of fallocate: gp3 volumes and the ubuntu image handle both,
# but fallocate can pre-allocate extents that swap dislikes on some kernels.
if [ ! -e /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw,pri=1 0 0' >> /etc/fstab
fi

# Prefer not to thrash: the node should OOM visibly rather than stall on swap for minutes.
sysctl -w vm.swappiness=10 >/dev/null || true
echo 'vm.swappiness=10' >> /etc/sysctl.d/99-lxon.conf

# Keep container logs bounded -- on a 20 GB root, json-file defaults are a slow leak.
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" }
}
JSON
systemctl restart docker || true

usermod -aG docker ubuntu
systemctl enable --now docker
docker compose version
free -h
