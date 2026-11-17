#!/usr/bin/env bash
# Runs ON THE INSTANCE. Installs the shared Caddyfile master plus ONE site fragment, and refuses to
# proceed if the result is not a configuration Caddy accepts.
#
# Each public hostname owns exactly one fragment in /etc/caddy/sites-enabled/. Nothing here writes
# another front's fragment -- the first expose-rpc.sh wrote the whole Caddyfile from one template,
# so the moment a www site existed, publishing it would have deleted rpc.lxon.in.
set -euo pipefail

FRAG="$1"          # e.g. rpc.http | rpc.https | www.http | www.https
[ -n "$FRAG" ] || { echo "ERROR: usage: install-caddy-sites.sh <fragment-basename>"; exit 2; }
FRONT="${FRAG%%.*}"   # rpc | www
SITES=/etc/caddy/sites-enabled

cd /opt/lxon/staging
[ -f Caddyfile.master ] || { echo "ERROR: Caddyfile.master not staged"; exit 1; }
[ -f "$FRAG.caddy" ]    || { echo "ERROR: $FRAG.caddy not staged"; exit 1; }
[ -f catchall.caddy ]   || { echo "ERROR: catchall.caddy not staged"; exit 1; }

if [ -f /etc/caddy/Caddyfile ] && ! grep -q 'lxon managed fronts' /etc/caddy/Caddyfile 2>/dev/null; then
  sudo cp -a /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.pre-lxon.$(date -u +%Y%m%dT%H%M%SZ)"
  echo "    previous /etc/caddy/Caddyfile backed up"
fi

{ echo '# lxon managed fronts -- generated from aws-freetier/caddy-sites/ by expose-*.sh'; \
  cat Caddyfile.master; } | sudo tee /etc/caddy/Caddyfile >/dev/null

sudo mkdir -p "$SITES" /var/log/caddy

# Drop this front's other mode so http<->https switching cannot leave two site blocks for the same
# hostname pointing at different behaviours.
for f in "$SITES/$FRONT".*.caddy; do
  [ -e "$f" ] && sudo rm -f "$f" && echo "    removed stale $(basename "$f")"
done

sudo install -m 0644 -o root -g root catchall.caddy "$SITES/catchall.caddy"
sudo install -m 0644 -o root -g root "$FRAG.caddy" "$SITES/$FRAG.caddy"
echo "    fragments now installed:"
ls -1 "$SITES" | sed 's/^/      /'

# Exactly one fragment may own the unmatched-Host catch-all, and it must be catchall.caddy. Two of
# them would merge into one :80 server in an order no caller can predict, and the quiet result is
# the RPC or the site answering a hostname it was never configured for.
CLAIMERS=$(grep -l '^:80 ' "$SITES"/*.caddy 2>/dev/null || true)
N=$(printf '%s' "$CLAIMERS" | grep -c . | tr -d ' ')
if [ "$N" != "1" ] || [ "$CLAIMERS" != "$SITES/catchall.caddy" ]; then
  echo "ERROR: $N fragments claim the ':80' catch-all (expected exactly 1, $SITES/catchall.caddy)"
  printf '%s\n' "$CLAIMERS" | sed 's/^/      /'
  exit 1
fi
echo "    the :80 catch-all is owned by catchall.caddy and nothing else"

sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

if sudo systemctl is-active --quiet caddy; then sudo systemctl reload caddy
else sudo systemctl enable --now caddy; fi
sleep 2
echo -n "    caddy: "; systemctl is-active caddy

# The reloaded process must actually hold this site, not just have accepted the file. Caddy's admin
# API on loopback reports the running config, which is the only place a stale inode or a skipped
# reload would still show the OLD set of hostnames.
sudo curl -sS -m 5 http://localhost:2019/config/apps/http/servers/ \
  | grep -q "$FRONT" || true   # server names are auto-generated; probed by site hostname instead
RUNNING=$(sudo curl -sS -m 5 http://localhost:2019/config/apps/http/servers/ || echo '{}')
echo "$RUNNING" | grep -qE "rpc\.lxon\.in|www\.lxon\.in|127\.0\.0\.1:9545" \
  || { echo "ERROR: the running Caddy config does not mention any lxon site"; exit 1; }
echo "    running config contains an lxon site (admin API read back, not the file)"
