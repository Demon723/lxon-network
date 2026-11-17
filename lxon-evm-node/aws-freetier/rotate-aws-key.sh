#!/usr/bin/env bash
# Rotate the leaked AWS access key for IAM user lxon_developer in account 044409363656.
#
# WHY THIS EXISTS AS A SCRIPT AND NOT AS FOUR PASTED COMMANDS
# The working credential on this machine (access key ID ending M3RF; the full ID is kept
# in ~/.lxon/secrets/aws-leaked-access-key-id, not here), was pasted into a chat transcript, and
# it is the key every script in this directory authenticates with (profile `lxon-remote`). It cannot be
# rotated with itself: measured 2026-11-04, `lxon_developer` has a permissions boundary that denies
# iam:ListAccessKeys, iam:ListUsers, iam:CreateAccessKey and cloudtrail:LookupEvents -- so self-service
# rotation and a usage audit are both impossible from here. Only an admin identity in this account can
# do it. This script does the parts that are easy to get wrong by hand:
#
#   - it never prints the new secret, and never puts it in argv (it goes stdin -> file, mode 0600);
#   - it swaps the key inside the SAME profile name, because every tool here uses AWS_PROFILE=lxon-remote;
#   - it verifies the new key really works before anything is deactivated, then deactivates -- not
#     deletes -- and only deletes on a second run with --confirm, because parallel sessions and cron
#     may still hold the old pair in their environment.
#
#   ./rotate-aws-key.sh --check                    # read-only report (works with the current key)
#   ./rotate-aws-key.sh --selftest                 # prove the guards can fail (no AWS writes)
#   ADMIN_AWS_PROFILE=<admin> ./rotate-aws-key.sh --phase create
#   ADMIN_AWS_PROFILE=<admin> ./rotate-aws-key.sh --phase finish
#   ADMIN_AWS_PROFILE=<admin> ./rotate-aws-key.sh --phase finish --confirm   # deletes the old key
set -uo pipefail

ACCOUNT="044409363656"
IAM_USER="lxon_developer"
# The leaked access key ID is deliberately NOT stored in this file. An access key ID is only half a
# credential, but it names a live one, and baking it into history is how it turns up in a search years
# later. It lives in ~/.lxon/secrets/aws-leaked-access-key-id (mode 600, outside any git tree); pass
# OLD_KEY=... on the command line to override. The last four (M3RF) are quoted below because the
# CloudTrail audit and the deactivate/delete calls both need to identify WHICH key they mean.
OLD_KEY_FILE="${OLD_KEY_FILE:-$HOME/.lxon/secrets/aws-leaked-access-key-id}"
# Read it only if it is there and readable, so a missing file produces the REFUSE line below and not a
# bare "No such file or directory" from bash ahead of it -- this is the tool that deactivates a leaked
# credential, and a confusing first line at that step costs trust.
if [ -r "$OLD_KEY_FILE" ]; then
  OLD_KEY="${OLD_KEY:-$(tr -d "[:space:]" < "$OLD_KEY_FILE" 2>/dev/null || true)}"
fi
[ -n "${OLD_KEY:-}" ] || { echo "REFUSE: no leaked key ID. Set OLD_KEY=AKIA... or write it to $OLD_KEY_FILE (see the comment above; last four should be M3RF)." >&2; exit 4; }
PROFILE="lxon-remote"
REGION="eu-north-1"
CREDS="${HOME}/.aws/credentials"
RUN_DIR="${HOME}/.lxon/runs/aws-rotate-$(date -u +%Y%m%dT%H%M%SZ)"

fail() { echo "REFUSE: $*" >&2; exit 1; }
say()  { echo "$*"; }

# ---------- aws wrapper: every call is pinned to one profile ----------
aws_as() { # <profile> <args...>
  local prof="$1"; shift
  AWS_PROFILE="$prof" AWS_REGION="$REGION" aws "$@"
}

require_admin() {
  [ -n "${ADMIN_AWS_PROFILE:-}" ] || fail "ADMIN_AWS_PROFILE is unset. Rotate needs an identity that
  can call iam:CreateAccessKey; lxon_developer's boundary denies it (measured 2026-11-04). Run as:
    ADMIN_AWS_PROFILE=<your-admin-profile> $0 --phase create"
  [ "$ADMIN_AWS_PROFILE" != "$PROFILE" ] || fail "ADMIN_AWS_PROFILE is '$PROFILE' -- that IS the leaked
  key. It cannot manage IAM (the boundary says so), and if it ever could, you would be rotating a
  credential using the credential that leaked."
}

gate_account() { # <profile>
  local acct
  acct="$(aws_as "$1" sts get-caller-identity --query Account --output text 2>/dev/null)" || fail \
    "profile '$1' did not answer sts:GetCallerIdentity"
  [ "$acct" = "$ACCOUNT" ] || fail "profile '$1' is account $acct, not $ACCOUNT. Refusing to touch
  credentials in an account other than the one this node lives in."
  say "  account gate ok: $1 -> $acct"
}

# ---------- --check: report only ----------
do_check() {
  say "== which profile holds which key id (secrets are never read or printed) =="
  python3 - "$CREDS" "$OLD_KEY" <<'PY'
import configparser, os, sys
path, leak = os.path.expanduser(sys.argv[1]), sys.argv[2]
cp = configparser.RawConfigParser(); cp.read(path)
for s in cp.sections():
    if not cp.has_option(s, 'aws_access_key_id'):
        print("  [%-13s] no static key (role/credential_process)" % s); continue
    k = cp.get(s, 'aws_access_key_id')
    print("  [%-13s] %-21s %s" % (s, k, "<== THE LEAKED KEY" if k == leak else ""))
PY
  say "== does the leaked key still authenticate? =="
  if out="$(aws_as "$PROFILE" sts get-caller-identity --query Arn --output text 2>&1)"; then
    say "  $PROFILE -> $out"
    say "  VERDICT: the leaked pair is LIVE. This is an open exposure until it is deactivated."
  else
    say "  $PROFILE -> did not authenticate (${out:0:120}) -- already disabled or deleted"
  fi
  say "== can the working credential rotate itself? each probe reports its own exit status =="
  # A first draft grepped a lowercase phrase the AWS CLI never prints, so all three denied calls
  # reported "ANSWERED" -- a false claim about the boundary, in the one line the owner would act on.
  # Now the verdict comes from the exit code, and the allowed action below is the control that proves
  # the probe can report success at all.
  probe() { # <label> <aws args...>
    local label="$1"; shift
    local out rc=0
    out="$(aws_as "$PROFILE" "$@" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      say "  $label -> ANSWERED (not blocked by the boundary)"
    else
      say "  $label -> DENIED $(printf '%s' "$out" | grep -oiE '\(([A-Za-z]+)\)' | head -1)"
    fi
  }
  probe "ec2:DescribeInstances (control, must be allowed)" ec2 describe-instances --max-items 1
  probe "iam:ListAccessKeys"                               iam list-access-keys --user-name "$IAM_USER"
  probe "iam:ListUsers"                                    iam list-users
  probe "cloudtrail:LookupEvents (the audit you will need)" cloudtrail lookup-events --max-results 1
  # iam:CreateAccessKey is deliberately NOT probed here: the IAM API has no DryRun for it, so the only
  # way to ask is to actually try to create a key. Its denial was measured on 2026-11-04 (boundary):
  #   "not authorized to perform: iam:CreateAccessKey on resource: user lxon_developer"
  say "== what the boundary proves =="
  say "  Nothing in this script can run with '$PROFILE'. Rotation is an admin action in account $ACCOUNT."
}

# ---------- --selftest: the guards must actually be able to fail ----------
# Every guard is exercised in a SUBSHELL, and each refusal has a matching control that must pass.
# A first draft called them in the current shell, so the very first `fail` exited the script and the
# selftest printed its own header and nothing else -- a check that cannot run is not a check.
do_selftest() {
  say "== selftest: negative controls for the gates (no AWS calls) =="
  local n=0 bad=0
  gate_real_account() {
    [ "$1" = "$ACCOUNT" ] || fail "profile x is account $1, not $ACCOUNT"
    say "    (accepted $1)"
  }

  if ( gate_real_account "999999999999" ) >/dev/null 2>&1; then
    say "  FAIL  account gate accepted a foreign account"; bad=$((bad+1))
  else say "  ok    account gate rejected 999999999999"; fi
  n=$((n+1))
  if ( gate_real_account "$ACCOUNT" ) >/dev/null 2>&1; then
    say "  ok    CONTROL: the same gate accepts the real account"; else
    say "  FAIL  CONTROL: the account gate rejected its own account -- it was refusing everything"; bad=$((bad+1)); fi
  n=$((n+1))

  if ( unset ADMIN_AWS_PROFILE; require_admin ) >/dev/null 2>&1; then
    say "  FAIL  require_admin allowed an empty admin profile"; bad=$((bad+1))
  else say "  ok    require_admin demands an admin profile"; fi
  n=$((n+1))
  if ( ADMIN_AWS_PROFILE="$PROFILE" require_admin ) >/dev/null 2>&1; then
    say "  FAIL  require_admin allowed rotation with the leaked profile"; bad=$((bad+1))
  else say "  ok    require_admin refuses rotating with the leaked key"; fi
  n=$((n+1))
  if ( ADMIN_AWS_PROFILE="some-admin-profile" require_admin ) >/dev/null 2>&1; then
    say "  ok    CONTROL: require_admin accepts a real admin profile name"; else
    say "  FAIL  CONTROL: require_admin refused a valid admin profile"; bad=$((bad+1)); fi
  n=$((n+1))

  local tmp errf; tmp="$(mktemp)"; errf="$(mktemp)"

  # 3. the INI rewriter must refuse a profile that is not there -- and refuse for THAT reason.
  #    Asserting only "it refused" is worthless: an earlier draft refused here because of an
  #    unrelated stdin bug, and the check read as a pass.
  printf '[other]\naws_access_key_id = AKIAOTHER\n' > "$tmp"
  if ( export CREDS="$tmp"; printf 'sekrit' | set_profile_keys "absent-profile" "AKIAX" ) >"$errf" 2>&1; then
    say "  FAIL  the rewriter invented a section for an unknown profile"; bad=$((bad+1))
  elif grep -q "is not in" "$errf"; then
    say "  ok    refuses an unknown profile section, for the stated reason"
  else
    say "  FAIL  it refused, but for an unrelated reason: $(head -c 140 "$errf" | tr '\n' ' ')"; bad=$((bad+1))
  fi
  n=$((n+1))

  printf '[good]\naws_access_key_id = OLDA\naws_secret_access_key = oldsecret\nregion = us-east-1\n[other]\naws_access_key_id = KEEPME\n' > "$tmp"
  if ( export CREDS="$tmp"; printf 'NEWSECRET' | set_profile_keys "good" "NEWID" ) >"$errf" 2>&1 \
     && grep -q '^aws_access_key_id = NEWID' "$tmp" \
     && grep -q '^aws_secret_access_key = NEWSECRET' "$tmp" \
     && grep -q 'region = us-east-1' "$tmp" \
     && grep -q 'KEEPME' "$tmp" \
     && ! grep -q 'oldsecret' "$tmp"; then
    say "  ok    CONTROL: replaces exactly the two lines in [good], keeps other keys and other profiles"
  else
    say "  FAIL  CONTROL: the rewriter did not do the one thing it must do"
    head -c 200 "$errf" | tr '\n' ' '; echo
    sed -e 's/NEWSECRET/<the new secret>/' "$tmp" | sed -n '1,8p'
    bad=$((bad+1))
  fi
  n=$((n+1))

  # 4. an empty secret must be refused, and named as the cause
  if ( export CREDS="$tmp"; printf '' | set_profile_keys "good" "NEWID2" ) >"$errf" 2>&1; then
    say "  FAIL  an empty secret was accepted"; bad=$((bad+1))
  elif grep -q "no secret read" "$errf"; then
    say "  ok    refuses an empty secret, for the stated reason"
  else
    say "  FAIL  refused for an unrelated reason: $(head -c 140 "$errf" | tr '\n' ' ')"; bad=$((bad+1))
  fi
  n=$((n+1))
  rm -f "$tmp" "$errf"

  say ""; say "selftest: $n checks, $bad failed"
  [ "$bad" -eq 0 ] || exit 1
}

# ---------- the INI edit: replace one profile's two keys, keep everything else ----------
set_profile_keys() { # <profile> <key-id> ; secret on stdin
  local prof="$1" kid="$2" secret=""
  # read returns non-zero at a newline-less EOF while still filling the variable, so judge the VALUE,
  # not the exit status -- a secret with no trailing newline is the normal case, not an error.
  IFS= read -r secret || true
  [ -n "$secret" ] || fail "no secret read on stdin"
  CREDS_FILE="$CREDS" TARGET_PROFILE="$prof" NEW_KEY_ID="$kid" NEW_SECRET="$secret" python3 - <<'PY'
import os, re, sys
path    = os.environ["CREDS_FILE"]
profile = os.environ["TARGET_PROFILE"]
kid     = os.environ["NEW_KEY_ID"]
secret  = os.environ["NEW_SECRET"]

with open(path, encoding="utf-8") as fh:
    lines = fh.read().split("\n")

# locate the section header for this profile, and where it ends
start = end = None
for i, ln in enumerate(lines):
    m = re.match(r"^\s*\[([^\]]+)\]\s*$", ln)
    if m:
        if m.group(1) == profile and start is None:
            start = i
        elif start is not None and end is None:
            end = i
if start is None:
    sys.stderr.write("REFUSE: profile [%s] is not in %s -- refusing to invent a section\n" % (profile, path))
    sys.exit(1)
if end is None:
    end = len(lines)

body = lines[start + 1:end]
had_id = had_secret = False
out = []
for ln in body:
    if re.match(r"^\s*aws_access_key_id\s*=", ln):
        out.append("aws_access_key_id = %s" % kid); had_id = True; continue
    if re.match(r"^\s*aws_secret_access_key\s*=", ln):
        out.append("aws_secret_access_key = %s" % secret); had_secret = True; continue
    out.append(ln)
if not had_id:
    out.insert(0, "aws_access_key_id = %s" % kid)
if not had_secret:
    out.insert(1 if not had_id else len(out), "aws_secret_access_key = %s" % secret)

new = lines[:start + 1] + out + lines[end:]
tmp = path + ".new"
umask = os.umask(0o077)
try:
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(new))
        fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    os.umask(umask)
print("rewrote [%s] in %s: aws_access_key_id -> %s, secret replaced (%d chars, not printed)"
      % (profile, path, kid, len(secret)))
PY
}

# ---------- phase create ----------
do_create() {
  require_admin
  say "== phase create =="
  gate_account "$ADMIN_AWS_PROFILE"
  mkdir -p "$RUN_DIR" || fail "cannot create $RUN_DIR"
  chmod 700 "$RUN_DIR"
  [ -f "$CREDS" ] || fail "$CREDS not found"
  cp -p "$CREDS" "$RUN_DIR/credentials.before" && chmod 600 "$RUN_DIR/credentials.before" \
    && say "  backed up $CREDS -> $RUN_DIR/credentials.before (0600)"

  local json="$RUN_DIR/new-key.json"
  say "  calling iam:CreateAccessKey for $IAM_USER (max 2 keys per user; if it is already at 2 the
  call fails with LimitExceeded -- in that case deactivate the leaked key FIRST, then re-run)"
  umask 077
  if ! aws_as "$ADMIN_AWS_PROFILE" iam create-access-key --user-name "$IAM_USER" --output json >"$json" 2>"$RUN_DIR/create.err"; then
    say "  FAILED: $(head -c 300 "$RUN_DIR/create.err")"
    say "  Nothing was changed. Credentials file untouched."
    exit 1
  fi
  chmod 600 "$json"

  local pair kid
  pair="$(python3 - "$json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["AccessKey"]
sys.stdout.write(d["AccessKeyId"] + "\n" + d["SecretAccessKey"] + "\n")
PY
)" || fail "could not parse the CreateAccessKey response"
  kid="$(printf '%s' "$pair" | head -1)"
  say "  new key id: $kid"

  printf '%s' "$pair" | tail -1 | set_profile_keys "$PROFILE" "$kid" \
    || fail "the credentials rewrite failed; restore $RUN_DIR/credentials.before"
  rm -f "$json" "$RUN_DIR/create.err"
  say "  removed the response file containing the secret"

  say "  verifying the swapped profile authenticates as the right user with the NEW key"
  local arn
  arn="$(aws_as "$PROFILE" sts get-caller-identity --query Arn --output text 2>&1)" \
    || fail "the new key did not authenticate -- restore $RUN_DIR/credentials.before"
  say "    $arn"
  case "$arn" in
    *"user/$IAM_USER") say "    ok: profile $PROFILE now speaks as $IAM_USER";;
    *) fail "the profile now authenticates as $arn, expected user/$IAM_USER";;
  esac
  local configured
  configured="$(aws_as '' configure get aws_access_key_id --profile "$PROFILE" 2>/dev/null)"
  [ "$configured" = "$kid" ] || say "    NOTE: profile shows ${configured:-unknown}, expected $kid"

  say "  read-only EC2 probe with the new key (what the rest of this kit needs)"
  if AWS_PROFILE="$PROFILE" aws ec2 describe-instances --region "$REGION" --max-items 1 >/dev/null 2>&1; then
    say "    ok: ec2:DescribeInstances answered"
  else
    say "    FAIL: describe-institutions did not answer -- do NOT deactivate the old key yet"
    exit 1
  fi
  say ""
  say "New key installed and verified. The leaked key $OLD_KEY is STILL ACTIVE."
  say "Next: run the kit once (./expose-www.sh --check), then:"
  say "    ADMIN_AWS_PROFILE=$ADMIN_AWS_PROFILE $0 --phase finish        # deactivate + verify"
  say "    ADMIN_AWS_PROFILE=$ADMIN_AWS_PROFILE $0 --phase finish --confirm   # then delete it"
}

# ---------- phase finish ----------
do_finish() {
  require_admin
  local confirm="${1:-}"
  say "== phase finish =="
  gate_account "$ADMIN_AWS_PROFILE"

  say "  read the current key ids on $IAM_USER"
  local keys
  keys="$(aws_as "$ADMIN_AWS_PROFILE" iam list-access-keys --user-name "$IAM_USER" --output json 2>&1)" \
    || fail "list-access-keys denied even for the admin profile: $(printf '%s' "$keys" | head -c 160)"
  printf '%s' "$keys" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for m in d["AccessKeyMetadata"]:
    print("    %-22s %-9s created %s" % (m["AccessKeyId"], m["Status"], m["CreateDate"]))
'
  say "  the profile in use must be the NEW key before anything is revoked"
  local cur
  cur="$(aws configure get aws_access_key_id --profile "$PROFILE" 2>/dev/null)"
  [ -n "$cur" ] || fail "could not read the key id configured for profile $PROFILE"
  [ "$cur" != "$OLD_KEY" ] || fail "profile $PROFILE still uses the leaked key -- run --phase create first"
  say "    profile $PROFILE uses $cur (not the leaked $OLD_KEY)"

  say "  deactivating $OLD_KEY (reversible: status Inactive, nothing deleted)"
  aws_as "$ADMIN_AWS_PROFILE" iam update-access-key --access-key-id "$OLD_KEY" \
    --status Inactive --user-name "$IAM_USER" || fail "update-access-key failed"

  say "  confirming IAM really reports it Inactive"
  local status
  status="$(aws_as "$ADMIN_AWS_PROFILE" iam list-access-keys --user-name "$IAM_USER" --output json \
            | python3 -c "
import json,sys
old='$OLD_KEY'
for m in json.load(sys.stdin)['AccessKeyMetadata']:
    if m['AccessKeyId']==old: print(m['Status'])
")"
  [ "$status" = "Inactive" ] || fail "expected status Inactive, got '${status:-absent}'"
  say "    status = $status"

  say "  and the functional proof: the old pair must now be refused"
  local old_secret=""
  if [ -f "$RUN_DIR/credentials.before" ]; then
    old_secret="$(python3 - "$RUN_DIR/credentials.before" "$PROFILE" <<'PY' 2>/dev/null
import configparser, os, sys
cp = configparser.RawConfigParser(); cp.read(os.path.expanduser(sys.argv[1]))
print(cp.get(sys.argv[2], 'aws_secret_access_key', fallback=''))
PY
)"
  fi
  if [ -n "$old_secret" ]; then
    local probe
    probe="$(AWS_ACCESS_KEY_ID="$OLD_KEY" AWS_SECRET_ACCESS_KEY="$old_secret" AWS_REGION="$REGION" \
             aws sts get-caller-identity 2>&1)"
    if printf '%s' "$probe" | grep -qE 'InvalidClientTokenId|Invalid security token'; then
      say "    ok: the leaked pair is refused by STS ($(printf '%s' "$probe" | grep -o 'an error occurred ([A-Za-z]*)' | head -1))"
    else
      say "    UNEXPECTED: the deactivated pair still authenticated. Stop and investigate before deleting."
      exit 1
    fi
  else
    say "    (skipped: no backup of the old secret to test with -- status check above still applies)"
  fi

  if [ "$confirm" != "--confirm" ]; then
    say ""
    say "Stop here and live on the new key for a while: the leaked key is INACTIVE, so anything still
  holding it (another session, a cron, the GitHub Action) will fail loudly rather than silently, and
  'aws iam update-access-key --status Active' puts it back if something breaks."
    say "When nothing complains:  ADMIN_AWS_PROFILE=$ADMIN_AWS_PROFILE $0 --phase finish --confirm"
    return 0
  fi
  say "  --confirm given: deleting $OLD_KEY"
  aws_as "$ADMIN_AWS_PROFILE" iam delete-access-key --access-key-id "$OLD_KEY" --user-name "$IAM_USER" \
    || fail "delete-access-key failed"
  local left
  left="$(aws_as "$ADMIN_AWS_PROFILE" iam list-access-keys --user-name "$IAM_USER" --output json \
          | python3 -c "
import json,sys
d=json.load(sys.stdin)['AccessKeyMetadata']
print('; '.join('%s=%s' % (m['AccessKeyId'], m['Status']) for m in d) or 'NONE')
")"
  case "$left" in
    *"$OLD_KEY"*) fail "the leaked key is STILL listed after delete: $left";;
    *) say "    rotation complete. remaining keys on $IAM_USER: $left";;
  esac
  say "  Do the audit you could not do from here: CloudTrail -> access events for $OLD_KEY, filtered to
  the last 90 days, from the console (this user is denied cloudtrail:LookupEvents)."
}

# ---------- dispatch ----------
[ -d "$HOME/.lxon/runs" ] || mkdir -p "$HOME/.lxon/runs"
case "${1:-}" in
  --check)    do_check ;;
  --selftest) do_selftest ;;
  --phase)    case "${2:-}" in
                create) do_create ;;
                finish) do_finish "${3:-}" ;;
                *) fail "--phase wants create or finish" ;;
              esac ;;
  --noop)     : ;;
  *)          sed -n '1,30p' "$0"; fail "no mode given (see the usage above)" ;;
esac
