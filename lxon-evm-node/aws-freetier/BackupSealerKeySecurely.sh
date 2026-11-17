#!/usr/bin/env bash
# Secure export of the live sealer key: encrypt ON THE INSTANCE, carry only ciphertext.
#
#   ./BackupSealerKeySecurely.sh --show          # print the commands, run nothing
#   ./BackupSealerKeySecurely.sh 1.2.3.4         # do it
#   DEST=~/LXON-secrets-encrypted ./BackupSealerKeySecurely.sh 1.2.3.4
#
# Properties, and why each one is here:
#   - the passphrase is read with `read -s` into shell memory and streamed to openssl's stdin.
#     It is never an argv element (visible in `ps` and shell history) and never a file.
#   - the plaintext key is encrypted where it lives. What crosses the wire and what lands on
#     any laptop is AES-256-CBC + PBKDF2 (1e6 iters, random salt).
#   - the backup is verified by DECRYPTING it on the instance and comparing hashes, then shredding
#     the scratch. An unverified backup is a rumour: the whole reason this project is restarting is
#     that a bundle was taken without the thing that mattered ("with_db": false).
#   - the passphrase is not stored anywhere. Forget it and the backup is a brick, which is the
#     correct trade for a key that signs consensus blocks.
set -uo pipefail

REGION="${REGION:-eu-north-1}"
KEY_NAME="lxon-${REGION}"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SSH_USER="ubuntu"
REMOTE_KEY="/opt/lxon/besu/privatekey.txt"
DEST="${DEST:-$HOME/LXON-secrets-encrypted}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER="${ITER:-1000000}"

EIP=""
for a in "$@"; do case "$a" in --show) SHOW=1 ;; *) EIP="$a" ;; esac; done
: "${SHOW:=0}"

CMD_SHOW=$(cat <<'BLOCK'
# Run by hand, in this order. <EIP> = the node address, <addr8> = last 8 of the validator address.
ssh -i ~/.ssh/lxon-eu-north-1.pem ubuntu@<EIP> \
  'sha256sum /opt/lxon/besu/privatekey.txt'                      # record this hash

# encrypt in place; the passphrase is prompted twice and never touches argv or a file
ssh -t -i ~/.ssh/lxon-eu-north-1.pem ubuntu@<EIP> \
  'openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 1000000 -salt \
     -in /opt/lxon/besu/privatekey.txt -out /tmp/sealer-<addr8>.age.enc'

# copy only the ciphertext down, then destroy the remote ciphertext
scp -i ~/.ssh/lxon-eu-north-1.pem ubuntu@<EIP>:/tmp/sealer-<addr8>.age.enc ~/LXON-secrets-encrypted/
ssh -i ~/.ssh/lxon-eu-north-1.pem ubuntu@<EIP> 'shred -u -z /tmp/sealer-<addr8>.age.enc'

# prove the backup actually decrypts to the same bytes, then shred the proof
ssh -i ~/.ssh/lxon-eu-north-1.pem ubuntu@<EIP> 'umask 077; openssl enc -d -aes-256-cbc -pbkdf2 \
  -md sha256 -iter 1000000 -in /tmp/replica.enc -out /tmp/check.txt \
  && sha256sum /tmp/check.txt && shred -u -z /tmp/check.txt'

# recovery (only ever needed if the instance is gone) -- writes the key next to you, 0600:
umask 077 && openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 1000000 \
  -in ~/LXON-secrets-encrypted/sealer-<addr8>.age.enc -out ./privatekey.txt
BLOCK
)

if [ "$SHOW" = 1 ]; then echo "$CMD_SHOW"; exit 0; fi

[ -n "$EIP" ] || { echo "ERROR: pass the EIP (or use --show to print the commands)" >&2; exit 2; }
[ -f "$KEY_FILE" ] || { echo "ERROR: $KEY_FILE missing" >&2; exit 2; }
case "$DEST" in
  *"/LXON/"*|*"/LXON"*)
    echo "ERROR: $DEST sits inside the repository. An encrypted consensus key in the tree is one" >&2
    echo "       'git add -A' away from being public history -- which already happened once here." >&2
    exit 1;;
esac

ssh_q() { ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "${SSH_USER}@${EIP}" "$@"; }

PLAIN_SHA=$(ssh_q "sha256sum $REMOTE_KEY 2>/dev/null | awk '{print \$1}'")
[ -n "$PLAIN_SHA" ] || { echo "ERROR: no key at $REMOTE_KEY on $EIP -- run NewSealerKeyOnInstance.sh?" >&2; exit 1; }
# Name the backup by date, not by a prefix of the key: reading 8 hex chars of the private scalar
# off the wire is 32 bits of a 256-bit secret, and it buys nothing a filename cannot.
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "==> Backing up sealer key on $EIP (key sha256 ${PLAIN_SHA:0:16}…)"

ENC="/tmp/sealer-${STAMP}.age.enc"
read -r -s -p "  passphrase for the backup (NOT stored anywhere; forget it and this is a brick): " PW1; echo
read -r -s -p "  repeat: " PW2; echo
[ "$PW1" = "$PW2" ] || { echo "ERROR: passphrases differ; nothing written." >&2; exit 1; }
[ "${#PW1}" -ge 12 ] || { echo "ERROR: passphrase shorter than 12 chars -- refused." >&2; exit 1; }

printf '%s' "$PW1" | ssh_q "umask 077; openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter $ITER -salt \
  -passin stdin -in $REMOTE_KEY -out $ENC && echo '  encrypted on instance: '$(ssh_q "stat -c %s $ENC") bytes"
RET=$?
PW1=""; PW2=""
[ $RET -eq 0 ] || { echo "ERROR: encryption failed" >&2; exit 1; }

mkdir -p "$DEST" && chmod 700 "$DEST"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -q "${SSH_USER}@${EIP}:$ENC" "$DEST/"
CIPHER="$DEST/$(basename "$ENC")"
echo "  ciphertext -> $CIPHER"
echo "  ciphertext sha256: $(shasum -a 256 "$CIPHER" | awk '{print $1}')  size: $(wc -c < "$CIPHER") bytes"

# --- prove it decrypts, on the instance, against the recorded plaintext hash -------------------
read -r -s -p "  passphrase again to verify the round trip: " VPW; echo
echo "$VPW" | ssh_q "umask 077; openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter $ITER -passin stdin \
  -in $ENC -out /tmp/sealer-check.txt && sha256sum /tmp/sealer-check.txt | awk '{print \$1}'" > /tmp/gotsha.$$
GOT=$(cat /tmp/gotsha.$$); rm -f /tmp/gotsha.$$
VPW=""
ssh_q "shred -u -z /tmp/sealer-check.txt 2>/dev/null || rm -f /tmp/sealer-check.txt"
if [ "$GOT" = "$PLAIN_SHA" ]; then
  echo "  ok: decrypts to the same bytes the live key has"
else
  echo "  FAIL: round trip produced ${GOT:-<empty>}, expected ${PLAIN_SHA} -- DO NOT rely on this backup" >&2
  exit 1
fi

ssh_q "shred -u -z $ENC 2>/dev/null || rm -f $ENC"
echo "  ok: remote ciphertext shredded; the live key remains only at $REMOTE_KEY (0600, uid 1000)"

cat <<EOF

Recovery, when the instance is gone:
  openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter $ITER -in "$CIPHER"

Two things to hear:
  1. A QBFT sealer needs its key as plaintext on the host to sign blocks. There is no KMS/Vault
     path for Besu's node identity, so "encrypted at rest" is only true of the BACKUP, never of
     the running file. The mitigations that are real: no 8545 in the security group, root volume
     with DeleteOnTermination=false, and a snapshot before any destructive change.
  2. This laptop already holds three plaintext validator keys and one leaked-in-git deployer key,
     so treat $CIPHER as one artifact to move off this disk (encrypted external media, or a
     password manager attachment) rather than a backup that lives next to the original.
EOF
