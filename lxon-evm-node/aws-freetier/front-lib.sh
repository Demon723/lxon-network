#!/usr/bin/env bash
# Shared plumbing for the public fronts on the free-tier node. Sourced, not executed.
#
# Why this exists as a file: rpc.lxon.in and www.lxon.in are two SITE BLOCKS IN ONE Caddyfile.
# The first expose-rpc.sh wrote /etc/caddy/Caddyfile from a single template, so the moment a second
# front existed, installing it would have deleted the first. Each front now owns one fragment in
# /etc/caddy/sites-enabled/ and nothing else, and neither template contains a `:80` catch-all except
# rpc's, which is checked before install.
#
# Nothing here prints a conclusion it has not measured: the mode (http vs https) comes from a live
# dig, the ports opened come from the mode, and every remote write reports its own exit status.

FRONT_LIB_REGION="${REGION:-eu-north-1}"
FRONT_LIB_EXPECTED_ACCOUNT="044409363656"
FRONT_LIB_EIP_TAG="lxon-node-eip"
FRONT_LIB_SSH_USER="ubuntu"
FRONT_LIB_KEY_FILE="${KEY_FILE:-$HOME/.ssh/lxon-eu-north-1.pem}"
FRONT_LIB_SITES_DIR="/etc/caddy/sites-enabled"

fl_fail() { echo "ERROR: $*" >&2; exit 1; }

# ---- identity + target ------------------------------------------------------
fl_resolve_target() {
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>&1) \
    || fl_fail "no usable AWS credentials: $ACCOUNT"
  [ "$ACCOUNT" = "$FRONT_LIB_EXPECTED_ACCOUNT" ] \
    || fl_fail "credentials are for $ACCOUNT, not $FRONT_LIB_EXPECTED_ACCOUNT"

  local addr
  addr=$(aws ec2 describe-addresses --region "$FRONT_LIB_REGION" \
           --filters "Name=tag:Name,Values=$FRONT_LIB_EIP_TAG" \
           --query 'Addresses[0].[PublicIp,InstanceId]' --output text 2>/dev/null) \
    || fl_fail "could not read the EIP tagged $FRONT_LIB_EIP_TAG in $FRONT_LIB_REGION"
  EIP=$(echo "$addr" | awk '{print $1}')
  INSTANCE=$(echo "$addr" | awk '{print $2}')
  { [ -n "$EIP" ] && [ "$EIP" != "None" ] && [ -n "$INSTANCE" ] && [ "$INSTANCE" != "None" ]; } \
    || fl_fail "no EIP tagged $FRONT_LIB_EIP_TAG attached to an instance in $FRONT_LIB_REGION"
  [ -f "$FRONT_LIB_KEY_FILE" ] || fl_fail "$FRONT_LIB_KEY_FILE missing"

  SG_ID=$(aws ec2 describe-instances --region "$FRONT_LIB_REGION" --instance-ids "$INSTANCE" \
            --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
  [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ] || fl_fail "could not read the security group of $INSTANCE"
  echo "==> Target: $FRONT_LIB_SSH_USER@$EIP  (instance $INSTANCE, $FRONT_LIB_REGION, account $ACCOUNT)"
  echo "    security group $SG_ID"
}

fl_ssh() { ssh -i "$FRONT_LIB_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
                    -o ConnectTimeout=20 "$FRONT_LIB_SSH_USER@$EIP" "$@"; }
fl_scp() { scp -i "$FRONT_LIB_KEY_FILE" -o StrictHostKeyChecking=accept-new -q "$@"; }

# ---- which front is actually possible for this hostname? -------------------
# Measured, never remembered: a note from last week saying "DNS still points at the old EIP" rots
# silently the moment the owner moves the record, and then the script would keep shipping HTTP.
fl_mode_for() { # <hostname> -> prints http|https on STDOUT; all commentary goes to stderr, because
                # the caller captures stdout and a stray echo here becomes part of the mode (it did
                # on 2026-11-03 and produced a filename like "rpc.==> DNS: ...\nhttps.caddy")
  local host="$1" now
  now=$(dig +short A "$host" 2>/dev/null | tr '\n' ' ')
  echo "==> DNS: $host -> ${now:-<no answer>}" >&2
  if printf '%s' " $now " | grep -q " $EIP "; then
    echo "    resolves here -> TLS front" >&2
    printf 'https'
  else
    echo "    does NOT resolve here -> interim plain-HTTP front (no certificate is obtainable)" >&2
    printf 'http'
  fi
}

# ---- install master + one fragment, leave the other fragment alone ----------
fl_install_caddy() { # <sitesrc-dir> <fragment-basename>
  local src="$1" frag="$2"
  [ -f "$src/Caddyfile.master" ] || fl_fail "$src/Caddyfile.master missing"
  [ -f "$src/$frag.caddy" ]      || fl_fail "$src/$frag.caddy missing"
  [ -f "$src/catchall.caddy" ]   || fl_fail "$src/catchall.caddy missing"
  [ -f "$src/../install-caddy-sites.sh" ] || fl_fail "install-caddy-sites.sh missing"

  fl_ssh 'mkdir -p /opt/lxon/staging' || fl_fail "SSH to $EIP failed -- nothing was installed"
  fl_scp "$src/Caddyfile.master" "$src/catchall.caddy" "$src/$frag.caddy" \
         "$src/../install-caddy-sites.sh" \
         "$FRONT_LIB_SSH_USER@$EIP:/opt/lxon/staging/" \
    || fl_fail "scp failed -- nothing was installed"
  echo "    staged: Caddyfile.master + catchall.caddy + $frag.caddy"
  fl_ssh "bash /opt/lxon/staging/install-caddy-sites.sh '$frag'" \
    || fl_fail "Caddy config was not applied for $frag -- this site is NOT serving"
}

# ---- ports ------------------------------------------------------------------
fl_open_ports() { # <ports...>  (in TLS mode both are needed; HTTP mode must not open 443, because
                                  # nothing binds it and a rule for a dead port is dead surface)
  local want="$*"
  echo "==> Opening the ports this front actually serves ($want)"
  local p
  for p in $want; do
    if aws ec2 authorize-security-group-ingress --region "$FRONT_LIB_REGION" --group-id "$SG_ID" \
         --protocol tcp --port "$p" --cidr 0.0.0.0/0 >/dev/null 2>&1; then
      echo "    opened $p"
    else
      echo "    $p already open (or the call was refused)"
    fi
  done
}

# ---- publish a local directory and prove the SERVED bytes match -------------
# Asserting "HTTP 200" is not asserting the right bytes: on the old node /swap/ returned 200 while
# serving a three-day-old build with no bridge panel, because the verification only looked at /ui/.
fl_publish_dir() { # <local-dir> <remote-dir>
  local src="$1" dst="$2"
  [ -d "$src" ] || fl_fail "no directory to publish at $src"
  # Two traps this shape avoids:
  #  * COPYFILE_DISABLE=1 plus --exclude stops macOS bsdtar writing AppleDouble "._x" sidecars; the
  #    first publish put nine of them in the web root, where they became real URLs on a public site.
  #  * NO comments inside the remote command string. A "# ... \" line inside it is joined to the
  #    next line by the continuation before parsing, which silently turns the next command into part
  #    of the comment -- that is how a chown+chmod pair can vanish while the script still reports
  #    success. All prose lives here, above the pipe.
  COPYFILE_DISABLE=1 tar -cf - -C "$src" --exclude='.DS_Store' --exclude='._*' . \
    | ssh -i "$FRONT_LIB_KEY_FILE" -o StrictHostKeyChecking=accept-new \
        "$FRONT_LIB_SSH_USER@$EIP" \
        "set -e; rm -rf /tmp/wwwnew; mkdir -p /tmp/wwwnew; tar -xf - -C /tmp/wwwnew; \
         find /tmp/wwwnew -name '._*' -delete; \
         sudo mkdir -p '$dst'; \
         sudo find '$dst' -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
         sudo tar -cf - -C /tmp/wwwnew . | sudo tar -xf - -C '$dst'; \
         sudo chown -R root:root '$dst'; \
         sudo find '$dst' -type d -exec chmod 0755 {} +; \
         sudo find '$dst' -type f -exec chmod 0644 {} +; \
         rm -rf /tmp/wwwnew; \
         echo \"    published to $dst: \$(sudo find '$dst' -type f | wc -l | tr -d ' ') files, 0644/0755 root-owned so the caddy user can read them\"" \
    || fl_fail "publishing $src -> $dst failed"
}

# sha256 of a local file vs the bytes actually served for a path on this host.
# args: <local-file> <scheme> <host> <path>. Uses the instance EIP directly, with the hostname in
# the Host header, so it tests the site that is configured rather than whatever DNS says -- which is
# exactly what must be true before the owner moves the record.
fl_serve_matches() {
  local f="$1" scheme="$2" host="$3" path="$4" port=80 want got
  [ "$scheme" = "https" ] && port=443
  want=$(shasum -a 256 "$f" | awk '{print $1}')
  got=$(curl -sS -m 25 --resolve "$host:$port:$EIP" "$scheme://$host$path" 2>/dev/null \
        | shasum -a 256 | awk '{print $1}')
  if [ -n "$got" ] && [ "$want" = "$got" ]; then
    echo "      same bytes: $path"
    return 0
  fi
  echo "      BYTES DIFFER: $path  local=$want served=${got:-<none>}"
  return 1
}

# Let's Encrypt issuance happens after 443 becomes reachable, so the first TLS probe can legitimately
# fail for a few seconds. Wait a bounded time for a command to start succeeding; report honestly if
# it never does. This is a retry, not a claim.
fl_wait() { # <seconds> <label> <shell command that must exit 0>
  local secs="$1" label="$2" cmd="$3" t=0
  while true; do
    if bash -c "$cmd" >/dev/null 2>&1; then
      echo "      $label after ${t}s"
      return 0
    fi
    [ "$t" -ge "$secs" ] && { echo "      $label DID NOT succeed within ${secs}s"; return 1; }
    sleep 5; t=$((t + 5))
  done
}
