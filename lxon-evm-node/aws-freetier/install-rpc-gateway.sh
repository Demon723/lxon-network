#!/usr/bin/env bash
# Runs ON THE INSTANCE. Installs the read-only RPC gateway and its systemd unit from
# /opt/lxon/staging. Written as a file on purpose: the previous version of this logic was a
# heredoc nested inside a single-quoted ssh argument, and the unit write it performed silently
# never happened -- while the caller still reported success.
set -euo pipefail
cd /opt/lxon/staging

for f in rpc-gateway.py lxon-rpc-gateway.service; do
  [ -f "$f" ] || { echo "ERROR: /opt/lxon/staging/$f missing -- did the scp run?"; exit 1; }
done

sudo install -m 0644 -o root -g root rpc-gateway.py            /usr/local/lib/lxon-rpc-gateway.py
sudo install -m 0644 -o root -g root lxon-rpc-gateway.service  /etc/systemd/system/lxon-rpc-gateway.service

# A no-write syntax check. py_compile would put __pycache__ next to the source, and an
# unprivileged user cannot write /usr/local/lib -- that aborted this install on 2026-11-03.
python3 - <<'PY'
import sys
src = open("/usr/local/lib/lxon-rpc-gateway.py").read()
compile(src, "/usr/local/lib/lxon-rpc-gateway.py", "exec")
print("    gateway parses")
PY

sudo systemctl daemon-reload
sudo systemctl enable --now lxon-rpc-gateway >/dev/null 2>&1 || true
sudo systemctl restart lxon-rpc-gateway
sleep 1
echo -n "    gateway: "; systemctl is-active lxon-rpc-gateway
echo -n "    enabled: "; systemctl is-enabled lxon-rpc-gateway

# The unit must say the same thing the file on disk says; a stale unit after a partial install is
# how a broken gateway keeps "running" with the old code.
systemctl show -p ExecStart --value lxon-rpc-gateway | grep -q 'lxon-rpc-gateway.py' \
  || { echo "ERROR: the running unit does not exec the gateway"; exit 1; }
echo "    unit points at the installed file"
